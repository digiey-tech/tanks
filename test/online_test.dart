import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/game.dart';
import 'package:tanks/lobby.dart';
import 'package:tanks/main.dart';
import 'package:tanks/maps.dart';
import 'package:tanks/net.dart';
import 'package:tanks/online.dart';

/// One end of an in-memory connection. Messages are delivered immediately.
class FakeLink implements NetLink {
  FakeLink? other;
  bool closed = false;
  int sent = 0;

  @override
  void Function(String message)? onMessage;

  @override
  void Function()? onClose;

  @override
  bool relayed = false;

  @override
  void send(String message) {
    if (closed) return;
    sent++;
    other?.onMessage?.call(message);
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    other?._remoteClosed();
  }

  void _remoteClosed() {
    if (closed) return;
    closed = true;
    onClose?.call();
  }
}

(FakeLink, FakeLink) linkPair() {
  final a = FakeLink();
  final b = FakeLink();
  a.other = b;
  b.other = a;
  return (a, b);
}

/// A host and guest with the first round started (the host's pick).
(OnlineMatch, OnlineMatch) matchPair() {
  final (hostLink, guestLink) = linkPair();
  final host = OnlineMatch(link: hostLink, isHost: true)
    ..pickMap(GameMap.classic);
  return (host, OnlineMatch(link: guestLink, isHost: false));
}

void run(OnlineMatch host, OnlineMatch guest, double seconds) {
  const dt = 1 / 60;
  for (var t = 0.0; t < seconds; t += dt) {
    guest.tick(dt);
    host.tick(dt);
  }
}

void main() {
  test('the guest plays blue and its joystick moves blue on both devices', () {
    final (host, guest) = matchPair();
    expect(host.me.team, Team.red);
    expect(guest.me.team, Team.blue);

    final start = host.game.blue.position;
    // The guest pushes up on its own screen: toward the host's side.
    guest.me.controls.move = const Offset(0, -1);
    run(host, guest, 0.5);
    expect(host.game.blue.position.dy, greaterThan(start.dy + 20));

    // Once blue stops, the guest's smoothed view settles on the host's.
    guest.me.controls.move = Offset.zero;
    run(host, guest, 0.3);
    expect(guest.game.blue.position, host.game.blue.position);
    expect(guest.game.red.position, host.game.red.position);
  });

  test('the guest sees shells, hits and the result from the host', () {
    final (host, guest) = matchPair();
    host.game.red.position = const Offset(150, 360);
    host.game.blue.position = const Offset(150, 330);
    host.game.blue.health = TankGame.damage;
    host.game.fire(host.game.red);

    run(host, guest, 0.05);
    expect(guest.game.shells, hasLength(host.game.shells.length));

    run(host, guest, 2);
    expect(host.game.winner, Team.red);
    expect(guest.game.isOver, isTrue);
    expect(guest.game.winner, Team.red);
    expect(guest.game.showResult, isTrue);
    expect(guest.game.blue.health, 0);
  });

  test('a guest double tap fires blue toward the tapped spot', () {
    final (host, guest) = matchPair();
    final blue = host.game.blue;
    // Blue starts aiming down the screen; tap to its right.
    guest.me.controls.aimAt = blue.position + const Offset(100, 0);
    guest.queueShot();
    expect(guest.me.controls.fireAtAim, isTrue);

    final blueShells = host.game.shells.where((s) => s.owner == Team.blue);
    for (var i = 0; i < 90 && blueShells.isEmpty; i++) {
      run(host, guest, 1 / 60);
    }
    expect(blueShells, hasLength(1));
    expect(blueShells.single.velocity.dx, greaterThan(0));

    // Once fired, the guest's marker stops showing a waiting shot.
    run(host, guest, 0.1);
    expect(guest.me.controls.fireAtAim, isFalse);
  });

  test('players take turns picking the map, host first', () {
    final (hostLink, guestLink) = linkPair();
    final host = OnlineMatch(link: hostLink, isHost: true);
    final guest = OnlineMatch(link: guestLink, isHost: false);
    run(host, guest, 0.1);
    expect(host.picker.value, Team.red);
    expect(guest.picker.value, Team.red);

    // Round 1: only the host can pick, and nothing moves until it does.
    guest.pickMap(GameMap.zigzag);
    host.me.controls.move = const Offset(1, 0);
    run(host, guest, 0.3);
    expect(host.picker.value, Team.red);
    expect(host.game.red.position, host.game.red.spawn);
    host.me.controls.move = Offset.zero;
    host.pickMap(GameMap.pillars);
    run(host, guest, 0.1);
    expect(guest.picker.value, isNull);
    expect(guest.game.map, same(GameMap.pillars));

    // The guest can move the game on after the round.
    host.game.red.health = 0;
    guest.me.controls.aimAt = const Offset(10, 10);
    run(host, guest, 1.5);
    expect(guest.game.showResult, isTrue);
    guest.nextRound();
    run(host, guest, 0.1);

    // Round 2: the guest's pick.
    expect(host.picker.value, Team.blue);
    expect(guest.picker.value, Team.blue);
    host.pickMap(GameMap.classic);
    run(host, guest, 0.1);
    expect(host.picker.value, Team.blue, reason: 'not the host\'s turn');
    guest.pickMap(GameMap.zigzag);
    run(host, guest, 0.1);
    expect(host.game.map, same(GameMap.zigzag));
    expect(guest.game.map, same(GameMap.zigzag));
    expect(guest.picker.value, isNull);
    expect(guest.game.red.health, TankGame.maxHealth);
    expect(guest.me.controls.aimAt, isNull);

    // Round 3: back to the host.
    host.game.blue.health = 0;
    run(host, guest, 1.5);
    host.nextRound();
    run(host, guest, 0.1);
    expect(guest.picker.value, Team.red);
  });

  test("playing again is the chooser's pick, and turns alternate", () {
    final (host, guest) = matchPair(); // Round 1: the host picked Classic.
    void finishRound() {
      host.game.blue.health = 0;
      run(host, guest, 1.5);
    }

    // After round 1 it's the guest's turn: the host can't choose.
    finishRound();
    expect(guest.myTurnNext, isTrue);
    expect(host.myTurnNext, isFalse);
    host.playAgain();
    host.nextRound();
    run(host, guest, 0.1);
    expect(host.game.showResult, isTrue);
    expect(host.picker.value, isNull);

    // The guest plays again on Classic. That uses the guest's turn.
    guest.playAgain();
    run(host, guest, 0.1);
    expect(host.game.isOver, isFalse);
    expect(guest.game.map, same(GameMap.classic));

    // Now it's the host's turn: the guest can't choose.
    finishRound();
    expect(host.myTurnNext, isTrue);
    expect(guest.myTurnNext, isFalse);
    guest.playAgain();
    guest.nextRound();
    run(host, guest, 0.1);
    expect(host.game.showResult, isTrue);
    host.nextRound();
    run(host, guest, 0.1);
    expect(guest.picker.value, Team.red);
  });

  test('playing again after a Random pick rolls a new random map', () {
    final (hostLink, guestLink) = linkPair();
    final host = OnlineMatch(link: hostLink, isHost: true);
    final guest = OnlineMatch(link: guestLink, isHost: false);
    host.pickMap(GameMap.pillars, random: true);

    for (var round = 0; round < 4; round++) {
      final before = host.game.map;
      host.game.blue.health = 0;
      run(host, guest, 1.5);
      // Whoever's turn it is plays again; the map still changes.
      (host.myTurnNext ? host : guest).playAgain();
      run(host, guest, 0.1);
      expect(host.game.isOver, isFalse);
      expect(host.game.map, isNot(same(before)));
      expect(guest.game.map, same(host.game.map));
    }
  });

  test('leaving tells the other device', () {
    final (host, guest) = matchPair();
    run(host, guest, 0.1);
    guest.dispose();
    expect(host.lost.value, isTrue);
  });

  test('a silent connection counts as lost', () {
    final (hostLink, _) = linkPair();
    final host = OnlineMatch(link: hostLink, isHost: true);
    for (var i = 0; i < 60 * 6; i++) {
      host.tick(1 / 60);
    }
    expect(host.lost.value, isTrue);
    expect(hostLink.closed, isTrue);
  });

  test(
    'host sends 20 updates a second, guest 15, and only keepalives when idle',
    () {
      final (hostLink, guestLink) = linkPair();
      final host = OnlineMatch(link: hostLink, isHost: true)
        ..pickMap(GameMap.classic);
      final guest = OnlineMatch(link: guestLink, isHost: false);

      // Red drives for a second (before it reaches the wall and stops)
      // while the guest's thumb wiggles every frame.
      host.me.controls.move = const Offset(1, 0);
      for (var i = 0; i < 60; i++) {
        guest.me.controls.move = Offset((i % 10) / 10, 0);
        run(host, guest, 1 / 60);
      }
      expect(hostLink.sent, inInclusiveRange(19, 21));
      expect(guestLink.sent, inInclusiveRange(14, 16));

      // A guest holding the stick steady sends nothing new.
      guest.me.controls.move = const Offset(1, 0);
      run(host, guest, 0.2);
      guestLink.sent = 0;
      run(host, guest, 1);
      expect(guestLink.sent, lessThanOrEqualTo(3));

      // Nobody touching anything for 4 seconds: just keepalives.
      host.me.controls.move = Offset.zero;
      guest.me.controls.move = Offset.zero;
      run(host, guest, 0.5);
      hostLink.sent = 0;
      guestLink.sent = 0;
      run(host, guest, 4);
      expect(hostLink.sent, lessThanOrEqualTo(9));
      expect(guestLink.sent, lessThanOrEqualTo(9));
      expect(host.lost.value || guest.lost.value, isFalse);
    },
  );

  test('the result screen only costs keepalives', () {
    final (hostLink, guestLink) = linkPair();
    final host = OnlineMatch(link: hostLink, isHost: true)
      ..pickMap(GameMap.classic);
    final guest = OnlineMatch(link: guestLink, isHost: false);
    host.game.blue.health = 0;
    run(host, guest, 2);
    expect(guest.game.showResult, isTrue);

    // Ten seconds sitting on the result screen.
    hostLink.sent = 0;
    guestLink.sent = 0;
    run(host, guest, 10);
    expect(hostLink.sent, lessThanOrEqualTo(21));
    expect(guestLink.sent, lessThanOrEqualTo(21));
    expect(guest.game.showResult, isTrue);
  });

  test('the guest glides between updates instead of jumping', () {
    final (host, guest) = matchPair();
    host.me.controls.move = const Offset(1, 0);
    run(host, guest, 0.5);

    // Track red on the guest frame by frame: no step should be much bigger
    // than one frame of driving.
    var last = guest.game.red.position;
    var biggest = 0.0;
    for (var i = 0; i < 60; i++) {
      run(host, guest, 1 / 60);
      final now = guest.game.red.position;
      biggest = math.max(biggest, (now - last).distance);
      last = now;
    }
    expect(biggest, lessThan(TankGame.moveSpeed / 60 * 1.6));
    expect(biggest, greaterThan(0));
  });

  group('screens', () {
    Future<void> setUp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 760) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Rect arenaRect(WidgetTester tester) => tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is ArenaPainter,
      ),
    );

    testWidgets('hosting shows a code, then starts the battle', (tester) async {
      await setUp(tester);
      final host = _FakeHost('4821');
      await tester.pumpWidget(
        MaterialApp(home: LobbyScreen(host: true, hostGame: () async => host)),
      );
      await tester.pump();
      expect(find.text('4821'), findsOneWidget);
      expect(find.text('Waiting for the other player…'), findsOneWidget);

      final (hostLink, _) = linkPair();
      host.connect(hostLink);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('YOU'), findsOneWidget);
      expect(find.text('BLUE'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('FIRE'), findsOneWidget);
    });

    testWidgets('joining sees the arena turned around', (tester) async {
      await setUp(tester);
      final (hostEnd, guestLink) = linkPair();
      String? joinedCode;
      await tester.pumpWidget(
        MaterialApp(
          home: LobbyScreen(
            host: false,
            joinGame: (code, {onStatus}) async {
              joinedCode = code;
              return guestLink;
            },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '0427');
      await tester.tap(find.text('Join'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(joinedCode, '0427');
      expect(find.text('RED'), findsOneWidget);
      expect(find.text('RED is picking the map…'), findsOneWidget);

      // The host picks a map and starts the round.
      hostEnd.send(
        jsonEncode({
          't': 'state',
          ...TankGame().toSnapshot(),
          'g': [0, 0],
          'p': null,
        }),
      );
      await tester.pump();
      expect(find.text('RED is picking the map…'), findsNothing);

      final state = tester.state<State>(find.byType(GameScreen));
      final match = (state as dynamic).widget.online as OnlineMatch;
      final blue = match.game.blue;

      // Blue is at the top of the arena in the game, but at the bottom of the
      // guest's screen.
      final arena = arenaRect(tester);
      final scale = arena.width / TankGame.world.width;
      final onScreen = arena.bottomRight - blue.position * scale; // turned 180°
      expect(onScreen.dy, greaterThan(arena.center.dy));

      // Tapping there aims at blue's own position in the game.
      final finger = await tester.startGesture(onScreen + const Offset(0, -30));
      expect(
        match.me.controls.aimAt!.dy,
        closeTo(blue.position.dy + 30 / scale, 0.5),
      );
      await finger.up();

      // The Up arrow moves toward the top of the guest's screen, which is
      // down in the game.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 16));
      expect(match.me.controls.keyMove, const Offset(0, 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 16));
    });

    testWidgets('connection errors are explained', (tester) async {
      await setUp(tester);
      // Tests don't run in a browser, so the real connection code refuses.
      await tester.pumpWidget(const MaterialApp(home: LobbyScreen(host: true)));
      await tester.pump();
      expect(
        find.textContaining('only works in the web version'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('the menu offers hosting and joining', (tester) async {
      await setUp(tester);
      await tester.pumpWidget(const TankApp());
      await tester.ensureVisible(find.text('Join'));
      await tester.tap(find.text('Join'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Join a game'), findsOneWidget);
    });
  });
}

class _FakeHost implements PeerHost {
  _FakeHost(this.code);

  @override
  final String code;
  final _opponent = Completer<NetLink>();
  bool cancelled = false;

  void connect(NetLink link) => _opponent.complete(link);

  @override
  Future<NetLink> get opponent => _opponent.future;

  @override
  void cancel() => cancelled = true;
}
