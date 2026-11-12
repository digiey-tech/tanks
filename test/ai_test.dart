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

  test('CPU only fires when it has a clear shot', () {
    final game = TankGame();
    final ai = TankAi(
      game: game,
      tank: game.blue,
      difficulty: Difficulty.hard,
      random: math.Random(2),
    );
    var shots = 0;
    for (var i = 0; i < 60 * 20 && !game.isOver; i++) {
      ai.update(1 / 60);
      if (game.blue.controls.fire) {
        shots++;
        expect(game.clearShot(game.blue.position, game.red.position), isTrue);
      }
      game.update(1 / 60);
    }
    expect(shots, greaterThan(0));
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
