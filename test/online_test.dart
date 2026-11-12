import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tanks/game.dart';
import 'package:tanks/lobby.dart';
import 'package:tanks/main.dart';
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

(OnlineMatch, OnlineMatch) matchPair() {
  final (hostLink, guestLink) = linkPair();
  return (
    OnlineMatch(link: hostLink, isHost: true),
    OnlineMatch(link: guestLink, isHost: false),
  );
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

  test('the guest can ask for a rematch', () {
    final (host, guest) = matchPair();
    host.game.red.health = 0;
    guest.me.controls.aimAt = const Offset(10, 10);
    run(host, guest, 1.5);
    expect(guest.game.showResult, isTrue);

    guest.rematch();
    run(host, guest, 0.1);
    expect(host.game.isOver, isFalse);
    expect(guest.game.isOver, isFalse);
    expect(guest.game.red.health, TankGame.maxHealth);
    expect(guest.me.controls.aimAt, isNull);
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

  test('sends at most 30 updates a second, and only keepalives when idle', () {
    final (hostLink, guestLink) = linkPair();
    final host = OnlineMatch(link: hostLink, isHost: true);
    final guest = OnlineMatch(link: guestLink, isHost: false);

    // Both moving for a second (before red reaches the wall and stops).
    host.me.controls.move = const Offset(1, 0);
    guest.me.controls.move = const Offset(1, 0);
    run(host, guest, 1);
    expect(hostLink.sent, inInclusiveRange(28, 31));

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
  });

  test('the result screen only costs keepalives', () {
    final (hostLink, guestLink) = linkPair();
    final host = OnlineMatch(link: hostLink, isHost: true);
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
      final (_, guestLink) = linkPair();
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
