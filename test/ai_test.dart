import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/ai.dart';
import 'package:tanks/game.dart';

/// Runs the AI and game together for up to [seconds], stopping at game over.
void simulate(TankGame game, List<TankAi> ais, double seconds) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds && !game.isOver; t += dt) {
    for (final ai in ais) {
      ai.update(dt);
    }
    game.update(dt);
  }
}

void main() {
  for (final difficulty in Difficulty.values) {
    test('${difficulty.label} CPU defeats a player who stands still', () {
      final game = TankGame();
      final ai = TankAi(
        game: game,
        tank: game.blue,
        difficulty: difficulty,
        random: math.Random(1),
      );
      simulate(game, [ai], 60);
      expect(game.isOver, isTrue);
      expect(game.winner, Team.blue);
    });
  }

  for (final difficulty in Difficulty.values) {
    test('${difficulty.label} CPU only fires shots that can reach', () {
      final game = TankGame();
      final ai = TankAi(
        game: game,
        tank: game.blue,
        difficulty: difficulty,
        random: math.Random(2),
      );
      var shots = 0;
      for (var i = 0; i < 60 * 20 && !game.isOver; i++) {
        ai.update(1 / 60);
        final blue = game.blue;
        if (blue.controls.fire && blue.cooldown <= 0) {
          shots++;
          final direct = game.clearShot(blue.position, game.red.position);
          if (!direct) {
            // Only Hard bounces shots, and only ones that get there.
            expect(difficulty.bankShots, isTrue);
            expect(
              game.previewShot(blue, blue.aim, game.red.position),
              isNotNull,
            );
          }
        }
        game.update(1 / 60);
      }
      expect(shots, greaterThan(0));
    });
  }

  /// Blue (the CPU) and red on either side of the top-left wall block, with
  /// no direct line between them, but a clear bounce off the left edge.
  (TankGame, TankAi) hiddenBehindWall(Difficulty difficulty) {
    final game = TankGame();
    game.blue.position = const Offset(60, 60);
    game.red.position = const Offset(60, 200);
    final ai = TankAi(
      game: game,
      tank: game.blue,
      difficulty: difficulty,
      random: math.Random(4),
    );
    return (game, ai);
  }

  /// Runs with the CPU pinned in place, so it can't just drive into view.
  void runPinned(TankGame game, TankAi ai, double seconds) {
    final spot = game.blue.position;
    for (var t = 0.0; t < seconds && !game.isOver; t += 1 / 60) {
      ai.update(1 / 60);
      game.update(1 / 60);
      game.blue.position = spot;
    }
  }

  test('Hard CPU bounces shots at a target hiding behind a wall', () {
    final (game, ai) = hiddenBehindWall(Difficulty.hard);
    expect(game.clearShot(game.blue.position, game.red.position), isFalse);
    runPinned(game, ai, 5);
    expect(game.red.health, lessThan(TankGame.maxHealth));
  });

  test('Easy and Normal CPUs hold fire when the target is hidden', () {
    for (final difficulty in [Difficulty.easy, Difficulty.normal]) {
      final (game, ai) = hiddenBehindWall(difficulty);
      var fired = 0;
      final spot = game.blue.position;
      for (var t = 0.0; t < 5; t += 1 / 60) {
        ai.update(1 / 60);
        if (game.blue.controls.fire) fired++;
        game.update(1 / 60);
        game.blue.position = spot;
      }
      expect(fired, 0, reason: difficulty.label);
      expect(game.red.health, TankGame.maxHealth);
    }
  });

  test('harder CPUs beat easier ones', () {
    var hardWins = 0;
    for (var seed = 0; seed < 10; seed++) {
      final game = TankGame();
      final hard = TankAi(
        game: game,
        tank: seed.isEven ? game.blue : game.red,
        difficulty: Difficulty.hard,
        random: math.Random(seed),
      );
      final easy = TankAi(
        game: game,
        tank: seed.isEven ? game.red : game.blue,
        difficulty: Difficulty.easy,
        random: math.Random(seed + 100),
      );
      simulate(game, [hard, easy], 120);
      if (game.winner == hard.tank.team) hardWins++;
    }
    expect(hardWins, greaterThanOrEqualTo(8));
  });

  test('CPU stops when the game is over and resets for a rematch', () {
    final game = TankGame();
    final ai = TankAi(
      game: game,
      tank: game.blue,
      difficulty: Difficulty.normal,
      random: math.Random(3),
    );
    simulate(game, [ai], 60);
    expect(game.isOver, isTrue);

    ai.update(1 / 60);
    final c = game.blue.controls;
    expect(c.fire || c.rotateLeft || c.rotateRight, isFalse);
    expect(c.move, Offset.zero);

    game.reset();
    ai.reset();
    simulate(game, [ai], 1);
    expect(game.blue.position, isNot(game.blue.spawn));
  });
}
