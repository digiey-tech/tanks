import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/ai.dart';
import 'package:tanks/game.dart';
import 'package:tanks/main.dart';

void run(TankGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.update(1 / 60);
  }
}

/// Puts [kind] under red, so red collects it on the next update.
TankGame collected(PowerUpKind kind) {
  final game = TankGame(powerUps: true);
  game.powerUp = PowerUp(game.red.position, kind);
  game.update(1 / 60);
  expect(game.powerUp, isNull);
  return game;
}

void main() {
  group('appearing', () {
    test('never appear when power-ups are off', () {
      final game = TankGame(random: math.Random(1));
      run(game, 120);
      expect(game.powerUp, isNull);
    });

    test('appear after a wait, one at a time, away from the tanks', () {
      final game = TankGame(powerUps: true, random: math.Random(2));
      run(game, TankGame.powerUpFirstWait - 0.1);
      expect(game.powerUp, isNull, reason: 'none during the first wait');

      var spawned = 0;
      PowerUp? last;
      for (var t = 0.0; t < 600; t += 1 / 60) {
        game.update(1 / 60);
        final current = game.powerUp;
        if (current != null && !identical(current, last)) {
          spawned++;
          expect(game.isOpen(current.position, margin: 4), isTrue);
          for (final tank in game.tanks) {
            expect(
              (tank.position - current.position).distance,
              greaterThanOrEqualTo(70),
            );
          }
        }
        last = current;
      }
      // Every kind turns up over ten minutes.
      expect(spawned, greaterThan(15));
    });

    test('after a timed one, the wait starts when its effect ends', () {
      final game = TankGame(powerUps: true, random: math.Random(3));
      game.powerUp = PowerUp(game.red.position, PowerUpKind.speed);
      game.update(1 / 60);
      expect(game.powerUp, isNull);
      run(game, TankGame.effectDuration + TankGame.powerUpWaitAfter - 0.1);
      expect(game.red.has(PowerUpKind.speed), isFalse);
      expect(game.powerUp, isNull);
      run(game, 30);
      expect(game.powerUp, isNotNull);
    });

    test('after Repair, the wait starts straight away', () {
      final game = TankGame(powerUps: true, random: math.Random(6));
      game.red.health = 40;
      game.powerUp = PowerUp(game.red.position, PowerUpKind.repair);
      game.update(1 / 60);
      run(game, TankGame.powerUpWaitAfter - 0.1);
      expect(game.powerUp, isNull);
      // Not held back by an effect's 8 seconds.
      PowerUp? appeared;
      for (
        var t = 0.0;
        t < TankGame.effectDuration && appeared == null;
        t += 1 / 60
      ) {
        game.update(1 / 60);
        appeared = game.powerUp;
      }
      expect(appeared, isNotNull);
    });

    test('vanish if nobody takes them', () {
      final game = TankGame(powerUps: true, random: math.Random(4));
      final waiting = PowerUp(const Offset(150, 150), PowerUpKind.rapid);
      game.powerUp = waiting;
      run(game, TankGame.powerUpLifetime - 0.2);
      expect(game.powerUp, same(waiting));
      run(game, 0.4);
      expect(game.powerUp, isNot(same(waiting)));
    });

    test('a new round clears the arena and the tanks\' effects', () {
      final game = collected(PowerUpKind.speed);
      game.powerUp = PowerUp(const Offset(20, 200), PowerUpKind.ice);
      game.reset();
      expect(game.powerUp, isNull);
      expect(game.red.effects, isEmpty);
    });
  });

  group('effects', () {
    test('Repair heals one hit, up to full', () {
      final game = TankGame(powerUps: true);
      game.red.health = 40;
      game.powerUp = PowerUp(game.red.position, PowerUpKind.repair);
      game.update(1 / 60);
      expect(game.red.health, 40 + TankGame.damage);

      game.red.health = TankGame.maxHealth - 5;
      game.powerUp = PowerUp(game.red.position, PowerUpKind.repair);
      game.update(1 / 60);
      expect(game.red.health, TankGame.maxHealth);
    });

    test('Power shot hits count double', () {
      final game = collected(PowerUpKind.power);
      game.red.position = const Offset(150, 360);
      game.blue.position = const Offset(150, 320);
      game.fire(game.red);
      expect(game.shells.single.damage, TankGame.damage * 2);
      run(game, 0.3);
      expect(game.blue.health, TankGame.maxHealth - TankGame.damage * 2);
    });

    test('Speed drives 50% faster', () {
      final plain = TankGame();
      final fast = collected(PowerUpKind.speed);
      for (final game in [plain, fast]) {
        game.red.controls.move = const Offset(-1, 0);
        game.update(0.1);
      }
      final plainMoved = plain.red.spawn.dx - plain.red.position.dx;
      final fastMoved = fast.red.spawn.dx - fast.red.position.dx;
      expect(fastMoved, closeTo(plainMoved * 1.5, 0.01));
    });

    test('Rapid fire reloads twice as fast', () {
      final game = collected(PowerUpKind.rapid);
      game.fire(game.red);
      expect(game.red.cooldown, TankGame.fireDelay / 2);
    });

    test('Ricochet shells bounce twice', () {
      final game = collected(PowerUpKind.ricochet);
      game.red.aim = -math.pi / 2;
      game.red.position = const Offset(20, 400);
      game.fire(game.red);
      final shell = game.shells.single;
      expect(shell.maxBounces, 2);
      // Straight up the clear left edge: off the top, then off the bottom,
      // and still flying.
      run(game, 2.6);
      expect(shell.bounces, 2);
      expect(game.shells, contains(shell));
    });

    test('Ice shot hits slow the enemy for a moment', () {
      final game = collected(PowerUpKind.ice);
      game.red.position = const Offset(150, 360);
      game.blue.position = const Offset(150, 320);
      game.fire(game.red);
      run(game, 0.2);
      expect(game.blue.chilled, greaterThan(0));

      final start = game.blue.position;
      game.blue.controls.move = const Offset(1, 0); // Left, from blue's side.
      game.update(0.1);
      final moved = (game.blue.position - start).distance;
      expect(moved, closeTo(TankGame.moveSpeed * 0.1 * 0.5, 0.01));

      game.blue.controls.move = Offset.zero;
      run(game, TankGame.chillDuration);
      expect(game.blue.chilled, 0);
    });

    test('timed effects wear off', () {
      final game = collected(PowerUpKind.rapid);
      expect(game.red.has(PowerUpKind.rapid), isTrue);
      run(game, TankGame.effectDuration + 0.1);
      expect(game.red.has(PowerUpKind.rapid), isFalse);
    });
  });

  group('power shot against shells', () {
    TankGame headOn(Shell red, Shell blue) {
      final game = TankGame()
        ..red.position = const Offset(280, 400)
        ..blue.position = const Offset(280, 20);
      game.shells.addAll([red, blue]);
      return game;
    }

    Shell redShell(double damage) => Shell(
      const Offset(20, 300),
      const Offset(0, -300),
      Team.red,
      damage: damage,
    );
    Shell blueShell(double damage, {double y = 100}) =>
        Shell(Offset(20, y), const Offset(0, 300), Team.blue, damage: damage);

    test('punches through an ordinary shell, then hits normally', () {
      final power = redShell(TankGame.damage * 2);
      final plain = blueShell(TankGame.damage);
      final game = headOn(power, plain);
      run(game, 0.4);
      expect(game.shells, [power]);
      expect(power.damage, TankGame.damage);
      expect(game.blasts, isNotEmpty);
    });

    test('is stopped by a second shell after losing its power', () {
      final power = redShell(TankGame.damage * 2);
      final game = headOn(power, blueShell(TankGame.damage))
        ..shells.add(blueShell(TankGame.damage, y: 40));
      run(game, 0.6);
      expect(game.shells, isEmpty);
    });

    test('two power shots destroy each other', () {
      final game = headOn(
        redShell(TankGame.damage * 2),
        blueShell(TankGame.damage * 2),
      );
      run(game, 0.4);
      expect(game.shells, isEmpty);
    });
  });

  test('the ring only flashes in the last couple of seconds', () {
    for (var left = TankGame.effectWarning + 0.05; left < 8; left += 0.05) {
      expect(TankGame.warningFlashOff(left), isFalse, reason: '$left');
    }
    final flashes = {
      for (var left = 0.0; left <= TankGame.effectWarning; left += 0.05)
        TankGame.warningFlashOff(left),
    };
    expect(flashes, {true, false});
  });

  test('online guests count effects down smoothly with the host', () {
    final host = collected(PowerUpKind.rapid);
    host.red.effects[PowerUpKind.rapid] = 5.3; // Sent as 6.
    final guest = TankGame()..applySnapshot(host.toSnapshot());
    expect(guest.red.effects[PowerUpKind.rapid], 6);

    guest.updateMirror(0.5);
    expect(guest.red.effects[PowerUpKind.rapid], closeTo(5.5, 1e-9));
    guest.applySnapshot(host.toSnapshot()); // Still 6: keeps counting.
    expect(guest.red.effects[PowerUpKind.rapid], closeTo(5.5, 1e-9));

    host.red.effects[PowerUpKind.rapid] = 0.3; // Sent as 1: catches up.
    guest.applySnapshot(host.toSnapshot());
    expect(guest.red.effects[PowerUpKind.rapid], 1);
  });

  test('online guests see power-ups and their effects', () {
    final host = collected(PowerUpKind.ice);
    host.red.effects[PowerUpKind.power] = 5;
    host.blue.chilled = 1;
    host.powerUp = PowerUp(const Offset(40, 200), PowerUpKind.speed);
    host.fire(host.red);

    final guest = TankGame()..applySnapshot(host.toSnapshot());
    expect(guest.powerUp?.kind, PowerUpKind.speed);
    expect(guest.powerUp?.position, const Offset(40, 200));
    expect(guest.red.has(PowerUpKind.ice), isTrue);
    expect(guest.red.has(PowerUpKind.power), isTrue);
    expect(guest.blue.chilled, greaterThan(0));
    final shell = guest.shells.single;
    expect(shell.icy, isTrue);
    expect(shell.damage, TankGame.damage * 2);
  });

  group('CPU', () {
    /// Blue (the CPU) at its spawn with a power-up [distance] below it.
    TankAi cpuNear(
      Difficulty difficulty,
      double distance, {
      PowerUpKind kind = PowerUpKind.speed,
    }) {
      final game = TankGame(powerUps: true);
      // Down and to the right of blue: open ground on the Classic map.
      final spot = game.blue.position + const Offset(0.6, 0.8) * distance;
      game.powerUp = PowerUp(spot, kind);
      final ai = TankAi(
        game: game,
        tank: game.blue,
        difficulty: difficulty,
        random: math.Random(5),
      );
      ai.update(1 / 60);
      return ai;
    }

    Offset spotOf(TankAi ai) => ai.game.powerUp!.position;

    test('Easy never goes for power-ups on purpose', () {
      final ai = cpuNear(Difficulty.easy, 60);
      expect(ai.destination, isNot(spotOf(ai)));
    });

    test('Normal and Hard go for a nearby power-up', () {
      for (final difficulty in [Difficulty.normal, Difficulty.hard]) {
        final ai = cpuNear(difficulty, 60);
        expect(ai.destination, spotOf(ai), reason: difficulty.label);
      }
    });

    test('Hard goes farther out of its way than Normal', () {
      final normal = cpuNear(Difficulty.normal, 150);
      expect(normal.destination, isNot(spotOf(normal)));
      final hard = cpuNear(Difficulty.hard, 150);
      expect(hard.destination, spotOf(hard));
    });

    test('nobody bothers with Repair at full health', () {
      final ai = cpuNear(Difficulty.hard, 60, kind: PowerUpKind.repair);
      expect(ai.destination, isNot(spotOf(ai)));
    });

    test('Normal actually collects one it goes for', () {
      final ai = cpuNear(Difficulty.normal, 60);
      final game = ai.game;
      for (var i = 0; i < 120 && game.powerUp != null; i++) {
        ai.update(1 / 60);
        game.update(1 / 60);
      }
      expect(game.blue.has(PowerUpKind.speed), isTrue);
    });
  });

  testWidgets('the menu switch turns power-ups on and off for a game', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 760) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TankApp());

    Future<TankGame> start() async {
      await tester.ensureVisible(find.text('1 Player vs CPU'));
      await tester.tap(find.text('1 Player vs CPU'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final state = tester.state<State>(find.byType(GameScreen));
      final game = (state as dynamic).game as TankGame;
      await tester.tap(find.text('Menu'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return game;
    }

    expect((await start()).powerUps, isTrue, reason: 'on by default');
    await tester.ensureVisible(find.text('Power-ups'));
    await tester.tap(find.text('Power-ups'));
    await tester.pump();
    expect((await start()).powerUps, isFalse);
  });
}
