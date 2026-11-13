import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/game.dart';

void main() {
  // The left edge of the arena has no walls in the way.
  TankGame faceOff() {
    final game = TankGame();
    game.red
      ..position = const Offset(20, 400)
      ..aim = -math.pi / 2;
    game.blue
      ..position = const Offset(20, 20)
      ..aim = math.pi / 2;
    return game;
  }

  for (final fps in [60, 30, 20]) {
    test('head-on shells knock each other out at $fps fps', () {
      final game = faceOff();
      game.fire(game.red);
      game.fire(game.blue);
      expect(game.shells, hasLength(2));

      for (var i = 0; i < fps && game.shells.isNotEmpty; i++) {
        game.update(1 / fps);
      }
      expect(game.shells, isEmpty);
      expect(game.blasts, isNotEmpty);
      // They met near the middle, well away from both tanks.
      expect(game.blasts.first.position.dy, closeTo(210, 25));
      expect(game.red.health, TankGame.maxHealth);
      expect(game.blue.health, TankGame.maxHealth);
    });
  }

  test('shells crossing at an angle knock each other out', () {
    final game = TankGame();
    // Paths cross at (20, 200), reached by both at the same moment.
    game.shells
      ..add(Shell(const Offset(20, 260), const Offset(0, -300), Team.red))
      ..add(Shell(const Offset(80, 200), const Offset(-300, 0), Team.blue));
    for (var i = 0; i < 30 && game.shells.isNotEmpty; i++) {
      game.update(1 / 60);
    }
    expect(game.shells, isEmpty);
    expect(game.blasts.first.position.dx, closeTo(20, 6));
    expect(game.blasts.first.position.dy, closeTo(200, 6));
  });

  test('a near miss flies past', () {
    final game = TankGame();
    // Parallel lanes 20 apart, passing each other head-on.
    game.shells
      ..add(Shell(const Offset(20, 300), const Offset(0, -300), Team.red))
      ..add(Shell(const Offset(40, 100), const Offset(0, 300), Team.blue));
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }
    expect(game.blasts, isEmpty);
  });

  test("a tank's own shells don't collide with each other", () {
    final game = TankGame();
    game.shells
      ..add(Shell(const Offset(20, 260), const Offset(0, -300), Team.red))
      ..add(Shell(const Offset(80, 200), const Offset(-300, 0), Team.red));
    game.update(0.2);
    expect(game.shells, hasLength(2));
    expect(game.blasts, isEmpty);
  });
}
