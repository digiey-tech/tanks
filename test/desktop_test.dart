import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/game.dart';
import 'package:tanks/main.dart';

void main() {
  test('keyboard movement drives the tank at full speed', () {
    final game = TankGame();
    final start = game.red.position;
    game.red.controls.keyMove = const Offset(-1, 0);
    game.update(0.1);
    expect(
      start.dx - game.red.position.dx,
      closeTo(TankGame.moveSpeed * 0.1, 0.01),
    );
  });

  test('keyboard and thumbstick together never exceed full speed', () {
    final game = TankGame();
    final start = game.red.position;
    game.red.controls
      ..keyMove = const Offset(-1, 0)
      ..move = const Offset(-1, 0);
    game.update(0.1);
    expect(
      start.dx - game.red.position.dx,
      closeTo(TankGame.moveSpeed * 0.1, 0.01),
    );
  });

  test('the turret turns toward the mouse at the normal turning speed', () {
    final game = TankGame();
    final red = game.red;
    // Red starts aiming straight up; point the mouse to its right.
    red.controls.aimAt = red.position + const Offset(100, 0);
    game.update(0.1);
    expect(red.aim, closeTo(-math.pi / 2 + TankGame.rotateSpeed * 0.1, 1e-9));

    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
    }
    expect(red.aim, closeTo(0, 1e-9));
  });

  test('rotate buttons override mouse aim', () {
    final game = TankGame();
    final red = game.red;
    red.controls
      ..aimAt = red.position + const Offset(100, 0)
      ..rotateLeft = true;
    game.update(0.1);
    expect(red.controls.aimAt, isNull);
    expect(red.aim, closeTo(-math.pi / 2 - TankGame.rotateSpeed * 0.1, 1e-9));
  });

  test('mouse button fires', () {
    final game = TankGame();
    game.red.controls.mouseFire = true;
    game.update(1 / 60);
    expect(game.shells, hasLength(1));
  });

  testWidgets('keyboard and mouse control the red tank', (tester) async {
    tester.view.physicalSize = const Size(480, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TankApp());
    await tester.tap(find.text('1 Player vs CPU'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final state = tester.state<State>(find.byType(GameScreen));
    final game = (state as dynamic).game as TankGame;
    final red = game.red;
    final start = red.position;

    // Hold D and W: up and to the right.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    expect(red.position.dx, greaterThan(start.dx));
    expect(red.position.dy, lessThan(start.dy));

    // Point the mouse at the arena's top-left corner and hold the button.
    final arena = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ArenaPainter,
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: arena.center);
    await mouse.moveTo(arena.topLeft + const Offset(10, 10));
    expect(red.controls.aimAt, isNotNull);
    expect(red.controls.aimAt!.dx, lessThan(red.position.dx));

    await mouse.down(arena.topLeft + const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.shells.where((s) => s.owner == Team.red), isNotEmpty);
    await mouse.up();
    expect(red.controls.mouseFire, isFalse);
    await mouse.removePointer();
  });

  testWidgets('two players share the keyboard', (tester) async {
    tester.view.physicalSize = const Size(480, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TankApp());
    await tester.tap(find.text('2 Players'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final state = tester.state<State>(find.byType(GameScreen));
    final game = (state as dynamic).game as TankGame;
    final red = game.red;
    final blue = game.blue;
    final redStart = red.position;
    final blueStart = blue.position;

    // Red drives left with A; Blue drives up the screen with the Up arrow,
    // even though Blue's on-screen controls are upside down.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));

    expect(red.position.dx, lessThan(redStart.dx));
    expect(red.position.dy, redStart.dy);
    expect(blue.position.dy, lessThan(blueStart.dy));
    expect(blue.position.dx, blueStart.dx);
    expect(game.shells.map((s) => s.owner).toSet(), {Team.red, Team.blue});

    for (final key in [
      LogicalKeyboardKey.keyA,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.slash,
    ]) {
      await tester.sendKeyUpEvent(key);
    }

    // Q and the period key turn the two guns.
    final redAim = red.aim;
    final blueAim = blue.aim;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.period);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.period);
    expect(red.aim, lessThan(redAim));
    expect(blue.aim, greaterThan(blueAim));

    // The mouse is off in two-player mode.
    final arena = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ArenaPainter,
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: arena.center);
    await mouse.moveTo(arena.topLeft + const Offset(10, 10));
    await mouse.down(arena.topLeft + const Offset(10, 10));
    expect(red.controls.aimAt, isNull);
    expect(red.controls.mouseFire, isFalse);
    await mouse.up();
    await mouse.removePointer();
  });

  Future<TankGame> startGame(WidgetTester tester, String button) async {
    tester.view.physicalSize = const Size(393, 660) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TankApp());
    await tester.ensureVisible(find.text(button));
    await tester.tap(find.text(button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final state = tester.state<State>(find.byType(GameScreen));
    return (state as dynamic).game as TankGame;
  }

  Rect arenaRect(WidgetTester tester) => tester.getRect(
    find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is ArenaPainter,
    ),
  );

  testWidgets('tapping the arena aims in single player', (tester) async {
    final game = await startGame(tester, '1 Player vs CPU');
    final red = game.red;
    final arena = arenaRect(tester);

    // Tap to the right of the red tank, level with it.
    final scale = arena.width / TankGame.world.width;
    final target =
        arena.topLeft + (red.position + const Offset(100, 0)) * scale;
    final finger = await tester.startGesture(target);
    expect(red.controls.aimAt, isNotNull);
    expect(red.controls.showAimMarker, isTrue);
    await finger.up();
    expect(game.shells, isEmpty, reason: 'tapping only aims');

    // The gun turns to face the tap (straight right) over the next second.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(red.aim, closeTo(0, 0.01));

    // Dragging a finger keeps updating the aim.
    final drag = await tester.startGesture(target);
    await drag.moveTo(arena.topLeft + const Offset(10, 10));
    expect(red.controls.aimAt!.dx, lessThan(red.position.dx));
    await drag.up();
  });

  testWidgets('tapping the arena does nothing in two-player mode', (
    tester,
  ) async {
    final game = await startGame(tester, '2 Players');
    await tester.tapAt(arenaRect(tester).topLeft + const Offset(20, 20));
    expect(game.red.controls.aimAt, isNull);
    expect(game.blue.controls.aimAt, isNull);
  });
}
