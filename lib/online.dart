import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'game.dart';
import 'maps.dart';
import 'net.dart';

/// A battle between two devices.
///
/// The host plays Red and runs the real game. The guest plays Blue: it sends
/// its controls to the host and draws whatever the host sends back, so both
/// screens always agree on positions, hits and health.
///
/// Before each round one player picks the map: the host for the first round,
/// then the guest, alternating. The host keeps track of whose turn it is and
/// tells the guest in every update.
class OnlineMatch {
  /// [powerUps] is the host's setting; the guest shows whatever power-ups
  /// the host's game puts on the arena.
  OnlineMatch({required this.link, required this.isHost, bool powerUps = false})
    : game = TankGame(powerUps: isHost && powerUps) {
    link
      ..onMessage = _onMessage
      ..onClose = _drop;
  }

  final NetLink link;
  final bool isHost;
  final TankGame game;

  /// Whose turn it is to pick the next map, or null while a round is being
  /// played. The host picks first.
  final ValueNotifier<Team?> picker = ValueNotifier(Team.red);

  /// Host: maps picked so far, which decides whose turn is next.
  int _picks = 0;

  Tank get me => isHost ? game.red : game.blue;
  Tank get opponent => isHost ? game.blue : game.red;

  /// Set when the other device leaves or the connection drops.
  final ValueNotifier<bool> lost = ValueNotifier(false);

  /// The host sends up to 20 updates a second and the guest's screen
  /// smooths between them. The guest sends its controls at most 15 times a
  /// second. Kept low because, when the network forces the relay, every
  /// message may count toward its free daily allowance.
  static const double hostInterval = 1 / 20;
  static const double guestInterval = 1 / 15;

  double get _sendInterval => isHost ? hostInterval : guestInterval;

  /// When nothing has changed, still send this often so each side knows
  /// the other is there.
  static const double keepAliveInterval = 0.5;

  /// This much silence means the connection is gone (some browsers never
  /// report the close).
  static const double silenceLimit = 5;

  double _sinceSent = double.infinity;
  double _sinceHeard = 0;
  String? _lastSent;

  /// Guest: double taps sent so far. Host: double taps received so far. A
  /// counter, so a queued shot is never lost or repeated.
  int _shots = 0;

  /// Guest: the host's count of double taps it has acted on.
  int _shotsAcknowledged = 0;
  bool _wasOver = false;

  void tick(double dt) {
    if (lost.value) return;
    _sinceHeard += dt;
    if (_sinceHeard > silenceLimit) {
      _drop();
      return;
    }
    if (isHost) {
      // Tanks wait while someone picks the map.
      if (picker.value == null) game.update(dt);
    } else {
      game.updateMirror(dt);
    }

    _sinceSent += dt;
    if (_sinceSent < _sendInterval * 0.8) return;
    final message = jsonEncode(isHost ? _snapshot() : _input());
    // Skip repeats (both tanks still, guest not touching anything) apart
    // from an occasional keepalive.
    if (message == _lastSent && _sinceSent < keepAliveInterval) return;
    _sinceSent = 0;
    _lastSent = message;
    link.send(message);
  }

  /// Double tap: shoot at the current aim point once the gun lines up.
  void queueShot() {
    me.controls.fireAtAim = true;
    if (!isHost) _shots++;
  }

  /// Picks [map] for the next round, if it's this player's turn. [random]
  /// says it came from the Random choice, so playing again rolls a new one.
  void pickMap(GameMap map, {bool random = false}) {
    if (picker.value != me.team) return;
    if (isHost) {
      _startRound(map, random: random);
    } else {
      link.send(
        jsonEncode({
          't': 'map',
          'i': GameMap.all.indexOf(map),
          'r': random ? 1 : 0,
        }),
      );
    }
  }

  /// Whose turn it is to choose the next round, either by playing again or
  /// picking a new map. Turns alternate, starting with the host.
  Team get nextPicker =>
      isHost ? (_picks.isEven ? Team.red : Team.blue) : _guestNextPicker;
  Team _guestNextPicker = Team.red;

  /// Whether this player chooses the next round.
  bool get myTurnNext => nextPicker == me.team;

  /// After a round, plays again on the same map (or a new random one if
  /// the map came from Random). Only the player whose turn it is can, and
  /// it counts as their pick.
  void playAgain() {
    if (isHost) {
      _playAgain(Team.red);
    } else if (myTurnNext) {
      link.send(jsonEncode({'t': 'again'}));
    }
  }

  /// After a round, moves on to picking a new map. Only the player whose
  /// turn it is can.
  void nextRound() {
    if (isHost) {
      _newMap(Team.red);
    } else if (myTurnNext) {
      link.send(jsonEncode({'t': 'next'}));
    }
  }

  /// Whether the current round's map came from Random.
  bool _roundRandom = false;

  bool _canChoose(Team by) =>
      picker.value == null && game.showResult && nextPicker == by;

  void _playAgain(Team by) {
    if (!_canChoose(by)) return;
    _startRound(
      _roundRandom ? game.randomMap() : game.map,
      random: _roundRandom,
    );
  }

  void _newMap(Team by) {
    if (!_canChoose(by)) return;
    picker.value = nextPicker;
  }

  void _startRound(GameMap map, {required bool random}) {
    game.reset(map: map);
    _roundRandom = random;
    _picks++;
    picker.value = null;
  }

  void dispose() {
    if (!lost.value) link.send(jsonEncode({'t': 'bye'}));
    link
      ..onMessage = null
      ..onClose = null
      ..close();
    lost.dispose();
    picker.dispose();
    game.dispose();
  }

  void _drop() {
    if (lost.value) return;
    lost.value = true;
    link.close();
  }

  Map<String, Object?> _snapshot() => {
    't': 'state',
    ...game.toSnapshot(),
    'p': picker.value?.index,
    'n': nextPicker.index,
    // Lets the guest show whether its double-tap shot is still waiting.
    'g': [_shots, opponent.controls.fireAtAim ? 1 : 0],
  };

  Map<String, Object?> _input() {
    final c = me.controls;
    // Turning by hand cancels tap aiming, the same as it does on the host.
    if (c.rotateLeft || c.rotateRight || c.keyRotate != 0) {
      c.aimAt = null;
      c.fireAtAim = false;
      _shotsAcknowledged = _shots;
    }
    // Coarse enough that tiny thumb jitter doesn't count as a change.
    double r(double v) => (v * 50).roundToDouble() / 50;
    final aimAt = c.aimAt;
    return {
      't': 'input',
      'm': [r(c.move.dx), r(c.move.dy)],
      'k': [r(c.keyMove.dx), r(c.keyMove.dy)],
      'r': [c.rotateLeft ? 1 : 0, c.rotateRight ? 1 : 0, c.keyRotate],
      'f': [c.fire ? 1 : 0, c.mouseFire ? 1 : 0, c.keyFire ? 1 : 0],
      'a': aimAt == null ? null : [r(aimAt.dx), r(aimAt.dy)],
      'q': _shots,
    };
  }

  void _onMessage(String text) {
    if (lost.value) return;
    _sinceHeard = 0;
    final Map<String, Object?> message;
    try {
      message = (jsonDecode(text) as Map).cast<String, Object?>();
    } on FormatException {
      return;
    }
    switch (message['t']) {
      case 'state' when !isHost:
        _applyState(message);
      case 'input' when isHost:
        _applyInput(message);
      case 'map' when isHost && picker.value == Team.blue:
        final index = message['i'] as int;
        if (index >= 0 && index < GameMap.all.length) {
          _startRound(GameMap.all[index], random: message['r'] == 1);
        }
      case 'next' when isHost:
        _newMap(Team.blue);
      case 'again' when isHost:
        _playAgain(Team.blue);
      case 'bye':
        _drop();
    }
  }

  void _applyInput(Map<String, Object?> m) {
    double d(Object? v) => (v as num).toDouble();
    List<Object?> list(String key) => m[key] as List;
    final c = opponent.controls;
    final move = list('m'),
        keys = list('k'),
        turn = list('r'),
        fire = list('f');
    c
      ..move = Offset(d(move[0]), d(move[1]))
      ..keyMove = Offset(d(keys[0]), d(keys[1]))
      ..rotateLeft = turn[0] == 1
      ..rotateRight = turn[1] == 1
      ..keyRotate = turn[2] as int
      ..fire = fire[0] == 1
      ..mouseFire = fire[1] == 1
      ..keyFire = fire[2] == 1;
    final aim = m['a'] as List?;
    c.aimAt = aim == null ? null : Offset(d(aim[0]), d(aim[1]));
    final shots = m['q'] as int;
    if (shots > _shots) {
      _shots = shots;
      c.fireAtAim = true;
    }
  }

  void _applyState(Map<String, Object?> m) {
    // Before applying, so the result screen sees whose turn it is when the
    // snapshot redraws it.
    final next = m['n'] as int?;
    if (next != null) _guestNextPicker = Team.values[next];
    game.applySnapshot(m);
    final pickerIndex = m['p'] as int?;
    picker.value = pickerIndex == null ? null : Team.values[pickerIndex];
    final c = me.controls;
    final shot = m['g'] as List;
    _shotsAcknowledged = shot[0] as int;
    c.fireAtAim = _shots > _shotsAcknowledged || shot[1] == 1;

    // A new round started: forget the last round's aim point, as the host
    // does for its own tank.
    if (_wasOver && !game.isOver) {
      c
        ..aimAt = null
        ..fireAtAim = false;
      _shotsAcknowledged = _shots;
    }
    _wasOver = game.isOver;
  }
}
