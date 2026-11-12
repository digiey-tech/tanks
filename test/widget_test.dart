import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/game.dart';
import 'package:tanks/main.dart';

void main() {
  test('walls stop shells', () {
    final game = TankGame();
    // Spawns face each other, but the center block sits between them.
    game.fire(game.red);
    for (var i = 0; i < 120 && game.shells.isNotEmpty; i++) {
      game.update(1 / 60);
    }
    expect(game.blue.health, TankGame.maxHealth);
  });

  test('a shell that hits the other tank reduces its health', () {
    final game = TankGame();
    game.red.position = const Offset(150, 360);
    game.blue.position = const Offset(150, 330);
    game.fire(game.red);
    for (var i = 0; i < 60 && game.shells.isNotEmpty; i++) {
      game.update(1 / 60);
    }
    expect(game.blue.health, TankGame.maxHealth - TankGame.damage);
    expect(game.red.health, TankGame.maxHealth);
  });

  test('movement ignores turret rotation', () {
    final game = TankGame();
    final start = game.red.position;
    game.red.aim = math.pi / 4;
    game.red.controls.move = const Offset(1, 0);
    game.update(0.1);
    expect(game.red.position.dx, greaterThan(start.dx));
    expect(game.red.position.dy, closeTo(start.dy, 0.001));
    expect(game.red.aim, math.pi / 4);
  });

  test('blue joystick input is flipped into world space', () {
    final game = TankGame();
    final start = game.blue.position;
    // Pushing "up" (away from the blue player) moves blue down the screen.
    game.blue.controls.move = const Offset(0, -1);
    game.update(0.1);
    expect(game.blue.position.dy, greaterThan(start.dy));
  });

  test('destroying a tank ends the game with a winner', () {
    final game = TankGame();
    game.blue.health = TankGame.damage;
    game.red.position = const Offset(150, 360);
    game.blue.position = const Offset(150, 330);
    game.fire(game.red);
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60);
    }
    expect(game.isOver, isTrue);
    expect(game.winner, Team.red);
    expect(game.showResult, isTrue);
  });

  // iPhone 15 and iPhone SE Safari viewports (toolbars visible).
  for (final size in const [Size(393, 660), Size(375, 548), Size(320, 460)]) {
    final name = '${size.width.toInt()}x${size.height.toInt()}';

    Future<void> openMenu(WidgetTester tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const TankApp());
    }

    testWidgets('two-player mode fits a $name screen', (tester) async {
      await openMenu(tester);
      // The menu scrolls on very short screens.
      await tester.ensureVisible(find.text('2 Players'));
      await tester.tap(find.text('2 Players'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('RED'), findsOneWidget);
      expect(find.text('BLUE'), findsOneWidget);
      expect(find.text('FIRE'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('single-player mode fits a $name screen', (tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Hard'));
      await tester.pump();
      await tester.tap(find.text('1 Player vs CPU'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('FIRE'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The close button returns to the menu.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('1 Player vs CPU'), findsOneWidget);
    });
  }
}
