import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/game.dart';
import 'package:tanks/maps.dart';

/// A game with only the given shell in play, tanks parked out of the way.
TankGame withShell(Shell shell, {Offset? blueAt}) {
  final game = TankGame();
  game.red.position = const Offset(280, 400);
  game.blue.position = blueAt ?? const Offset(280, 60);
  game.shells.add(shell);
  return game;
}

void run(TankGame game, double seconds, {double dt = 1 / 60}) {
  for (var t = 0.0; t < seconds; t += dt) {
    game.update(dt);
  }
}

void main() {
  test('a shell bounces off the arena edge, then ends at the next wall', () {
    // Straight up the middle: off the top edge, then down onto the center
    // block.
    final shell = Shell(const Offset(150, 30), const Offset(0, -300), Team.red);
    final game = withShell(shell);

    run(game, 0.2);
    expect(game.shells, [shell]);
    expect(shell.bounces, 1);
    expect(shell.velocity, const Offset(0, 300));
    expect(game.blasts, isEmpty);

    for (var i = 0; i < 60 && game.shells.isNotEmpty; i++) {
      game.update(1 / 60);
    }
    expect(game.shells, isEmpty);
    expect(game.blasts, hasLength(1));
    final center = GameMap.classic.walls.last;
    expect(
      game.blasts.single.position.dy,
      closeTo(center.top - TankGame.shellRadius, 1),
    );
  });

  test('a shell bounces off the side of a wall block', () {
    final block = GameMap.classic.walls.first;
    final shell = Shell(
      Offset(20, block.center.dy),
      const Offset(300, 0),
      Team.red,
    );
    final game = withShell(shell);
    run(game, 0.15);
    expect(shell.bounces, 1);
    expect(shell.velocity, const Offset(-300, 0));
    expect(shell.position.dx, lessThan(block.left));
  });

  test('a shell glancing off the top of a block keeps its sideways motion', () {
    final block = GameMap.classic.walls.first;
    final shell = Shell(
      Offset(block.center.dx, block.top - 30),
      const Offset(100, 300),
      Team.red,
    );
    final game = withShell(shell);
    run(game, 0.15);
    expect(shell.velocity, const Offset(100, -300));
    expect(shell.position.dy, lessThan(block.top));
  });

  test('a shell into a corner comes straight back out', () {
    final shell = Shell(
      const Offset(20, 20),
      const Offset(-300, -300),
      Team.red,
    );
    final game = withShell(shell);
    run(game, 0.1);
    expect(shell.velocity, const Offset(300, 300));
  });

  test('even a very fast shell cannot skip through a wall', () {
    final block = GameMap.classic.walls.first;
    // Ten times normal speed: over 30 units a frame, more than the block's
    // thickness.
    final shell = Shell(
      Offset(block.center.dx, block.top - 40),
      const Offset(0, 3200),
      Team.red,
    );
    final game = withShell(shell);
    game.update(1 / 60);
    expect(shell.bounces, 1);
    expect(shell.velocity.dy, lessThan(0));
    expect(shell.position.dy, lessThan(block.top));
  });

  test('a bounced shell can still hit the other tank', () {
    // Fired away from blue, it comes back off the top edge onto blue.
    final shell = Shell(const Offset(150, 30), const Offset(0, -300), Team.red);
    final game = withShell(shell, blueAt: const Offset(150, 90));
    run(game, 0.5);
    expect(game.blue.health, TankGame.maxHealth - TankGame.damage);
  });

  test('a bounced shell never hits its own tank', () {
    final shell = Shell(
      const Offset(150, 30),
      const Offset(0, -300),
      Team.blue,
    );
    final game = withShell(shell, blueAt: const Offset(150, 90));
    run(game, 0.5);
    expect(game.blue.health, TankGame.maxHealth);
  });

  test('online guests see the bounce count and bounces between updates', () {
    final host = withShell(
      Shell(const Offset(150, 30), const Offset(0, -300), Team.red),
    );
    run(host, 0.2);
    final guest = TankGame()..applySnapshot(host.toSnapshot());
    expect(guest.shells.single.bounces, 1);

    // Between updates the guest moves shells itself, bouncing like the host.
    final early = withShell(
      Shell(const Offset(150, 10), const Offset(0, -300), Team.red),
    );
    final mirror = TankGame()..applySnapshot(early.toSnapshot());
    mirror.updateMirror(0.05);
    final shell = mirror.shells.single;
    expect(shell.position.dy, greaterThanOrEqualTo(TankGame.shellRadius));
    expect(shell.velocity.dy, greaterThan(0));
    expect(shell.bounces, 1);
  });

  test('previewShot traces direct, blocked and bounced shots', () {
    final game = TankGame();
    game.blue.position = const Offset(60, 60);
    final behindWall = const Offset(60, 200);
    final inTheOpen = const Offset(20, 60);

    // Straight left at a target in the open.
    expect(game.previewShot(game.blue, math.pi, inTheOpen), isNotNull);
    // Straight down into the wall block.
    expect(game.previewShot(game.blue, math.pi / 2, behindWall), isNull);
    // Off the left edge: aim at the target's mirror image across it.
    final mirror = Offset(
      2 * TankGame.shellRadius - behindWall.dx,
      behindWall.dy,
    );
    final toMirror = mirror - game.blue.position;
    final time = game.previewShot(
      game.blue,
      math.atan2(toMirror.dy, toMirror.dx),
      behindWall,
    );
    expect(time, isNotNull);
    expect(time, greaterThan(0.3));
  });
}
