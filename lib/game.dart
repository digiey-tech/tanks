import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'maps.dart';

enum Team { red, blue }

/// Live input for one tank, written by the touch controls and, on a
/// computer, the keyboard and mouse.
class TankControls {
  /// Joystick vector in the player's own frame (up = away from the player).
  /// Length is between 0 and 1.
  Offset move = Offset.zero;

  /// Keyboard movement, in screen directions (up = toward the top of the
  /// screen) for either player, since everyone at a computer sees the screen
  /// the same way up.
  Offset keyMove = Offset.zero;

  bool rotateLeft = false;
  bool rotateRight = false;

  /// Keyboard turning: -1 counterclockwise, 1 clockwise, 0 none.
  int keyRotate = 0;

  /// Arena point the mouse is aiming at. The turret turns toward it at the
  /// normal turning speed. Cleared when the rotate buttons are used.
  Offset? aimAt;

  /// Whether to mark [aimAt] in the arena. On for taps, off for the mouse,
  /// which already shows a crosshair cursor.
  bool showAimMarker = false;

  /// A queued shot at [aimAt] (from a double tap). It fires once the gun is
  /// facing [aimAt] and reloaded, so the shell goes where the player tapped.
  bool fireAtAim = false;

  bool fire = false;
  bool mouseFire = false;
  bool keyFire = false;
}

/// The kinds of power-up. Online play sends them by index, so only add new
/// kinds to the end.
enum PowerUpKind {
  /// Heals one hit's worth of health, straight away.
  repair('Repair', 'Heals one hit.'),

  /// Hits count double.
  power(
    'Power shot',
    'Each hit counts double, and it punches through one enemy shell.',
  ),

  /// Drives faster.
  speed('Speed', 'Drive 50% faster.'),

  /// Reloads twice as fast.
  rapid('Rapid fire', 'Reload twice as fast.'),

  /// Shells bounce twice instead of once.
  ricochet('Ricochet', 'Shells bounce twice.'),

  /// Hits slow the enemy down for a moment.
  ice('Ice shot', 'Hits slow the enemy for a moment.');

  const PowerUpKind(this.label, this.description);

  final String label;
  final String description;

  /// Whether it lasts a while rather than acting once.
  bool get timed => this != repair;
}

/// A power-up waiting on the arena to be driven over.
class PowerUp {
  PowerUp(this.position, this.kind);

  final Offset position;
  final PowerUpKind kind;

  /// Seconds on the arena. It vanishes at [TankGame.powerUpLifetime].
  double age = 0;
}

class Tank {
  Tank({
    required this.team,
    required this.spawn,
    required this.spawnAim,
    required this.flipped,
  }) {
    reset();
  }

  final Team team;
  final Offset spawn;
  final double spawnAim;

  /// Whether this player's controls are rotated 180° (they sit at the top of
  /// the phone), so their joystick input must be flipped into world space.
  final bool flipped;

  final TankControls controls = TankControls();

  late Offset position;

  /// Direction the turret points, in radians. Only the rotate buttons change it.
  late double aim;

  /// Direction the hull faces. Purely cosmetic; follows movement.
  late double hull;

  late double health;
  double cooldown = 0;
  double hitFlash = 0;

  /// Timed power-ups in effect, with seconds left.
  final Map<PowerUpKind, double> effects = {};

  /// Seconds left of being slowed by an ice hit.
  double chilled = 0;

  bool get alive => health > 0;

  bool has(PowerUpKind kind) => (effects[kind] ?? 0) > 0;

  void reset() {
    position = spawn;
    aim = spawnAim;
    hull = spawnAim;
    health = TankGame.maxHealth;
    cooldown = 0;
    hitFlash = 0;
    effects.clear();
    chilled = 0;
    // Forget the last aim point so the gun doesn't swing toward it in the
    // next round. Held buttons stay as they are, since fingers may be down.
    controls.aimAt = null;
    controls.fireAtAim = false;
  }
}

class Shell {
  Shell(
    this.position,
    this.velocity,
    this.owner, {
    this.bounces = 0,
    this.maxBounces = TankGame.maxBounces,
    this.damage = TankGame.damage,
    this.icy = false,
  });

  Offset position;
  Offset velocity;
  final Team owner;

  /// How many times it has bounced. It ends at the next wall once this
  /// reaches [maxBounces].
  int bounces;
  final int maxBounces;

  /// Health it takes on a hit. A power shot drops back to normal after
  /// punching through an enemy shell.
  double damage;

  /// Whether a hit slows the target (the Ice shot power-up).
  final bool icy;

  Shell copy() => Shell(
    position,
    velocity,
    owner,
    bounces: bounces,
    maxBounces: maxBounces,
    damage: damage,
    icy: icy,
  );
}

class Blast {
  Blast(this.position, {this.big = false});

  final Offset position;
  final bool big;
  double age = 0;
}

class TankGame extends ChangeNotifier {
  /// Plays on [map], or on a randomly chosen map each round if [map] is
  /// null. [powerUps] turns power-ups on. [random] can be fixed for tests.
  TankGame({
    GameMap? map = GameMap.classic,
    this.powerUps = false,
    math.Random? random,
  }) : mapChoice = map,
       _random = random ?? math.Random() {
    reset();
  }

  /// The map picked for this game, or null to pick a new one at random
  /// every round.
  final GameMap? mapChoice;
  final math.Random _random;

  /// Whether power-ups appear during play.
  final bool powerUps;

  /// The power-up on the arena, if any. Only one at a time.
  PowerUp? powerUp;

  /// Seconds until the next chance for a power-up to appear.
  double _powerUpWait = 0;

  /// The map being played this round.
  GameMap get map => _map!;
  GameMap? _map;

  /// Cover blocks for this round's map.
  List<Rect> get walls => map.walls;

  static const Size world = Size(300, 420);
  static const double tankRadius = 13;
  static const double shellRadius = 3;
  static const double moveSpeed = 120;
  static const double rotateSpeed = 2.8;
  static const double shellSpeed = 320;
  static const double fireDelay = 0.45;
  static const double maxHealth = 100;
  static const double damage = 20;
  static const double blastDuration = 0.35;

  // Power-ups.
  static const double powerUpRadius = 9;

  /// Wait at the start of a round, and after one is used or vanishes,
  /// before there's any chance of another.
  static const double powerUpFirstWait = 4;
  static const double powerUpWaitAfter = 6;

  /// Once the wait is over, the chance each second that one appears.
  static const double powerUpChancePerSecond = 0.35;

  /// An untouched power-up vanishes after this long, so one can't sit in an
  /// awkward spot forever. It blinks for the last few seconds.
  static const double powerUpLifetime = 15;
  static const double powerUpBlinkTime = 3;

  /// How long timed power-ups last, and how long an ice hit slows a tank.
  static const double effectDuration = 8;

  /// A tank's power-up ring flashes for this long before the effect ends.
  static const double effectWarning = 2;

  /// Whether a power-up with [left] seconds to go is in the "off" part of
  /// its warning flash (about three flashes a second).
  static bool warningFlashOff(double left) =>
      left <= effectWarning && (left * 6).floor().isOdd;
  static const double chillDuration = 2.5;
  static const double resultDelay = 0.9;

  final Tank red = Tank(
    team: Team.red,
    spawn: Offset(world.width / 2, world.height - 50),
    spawnAim: -math.pi / 2,
    flipped: false,
  );

  final Tank blue = Tank(
    team: Team.blue,
    spawn: Offset(world.width / 2, 50),
    spawnAim: math.pi / 2,
    flipped: true,
  );

  List<Tank> get tanks => [red, blue];

  final List<Shell> shells = [];
  final List<Blast> blasts = [];

  bool _over = false;
  double _overTime = 0;
  Team? _winner;

  bool get isOver => _over;

  /// Null on a draw (both tanks destroyed on the same frame).
  Team? get winner => _winner;

  /// The result screen waits briefly so players see the final hit land.
  bool get showResult => _over && _overTime >= resultDelay;

  /// Starts a new round on [map], or else on [mapChoice] (a random map if
  /// that's null too).
  void reset({GameMap? map}) {
    _map = map ?? mapChoice ?? randomMap();
    for (final tank in tanks) {
      tank.reset();
    }
    powerUp = null;
    _powerUpWait = powerUpFirstWait;
    shells.clear();
    blasts.clear();
    _over = false;
    _overTime = 0;
    _winner = null;
    notifyListeners();
  }

  /// A random map, different from the last round's when there is one.
  GameMap randomMap() {
    final choices = [
      for (final m in GameMap.all)
        if (!identical(m, _map)) m,
    ];
    return choices[_random.nextInt(choices.length)];
  }

  /// Everything another device needs to draw the battle, as JSON-friendly
  /// values. Used by the host in online play.
  Map<String, Object?> toSnapshot() {
    double r(double v) => (v * 100).roundToDouble() / 100;
    double angle(double v) => (v * 1000).roundToDouble() / 1000;
    return {
      'k': [
        for (final t in tanks)
          [
            r(t.position.dx),
            r(t.position.dy),
            angle(t.aim),
            angle(t.hull),
            t.health,
            r(t.hitFlash),
            // Whole seconds, so countdowns don't make every update new.
            [
              for (final e in t.effects.entries)
                if (e.value > 0) [e.key.index, e.value.ceil()],
            ],
            t.chilled > 0 ? 1 : 0,
          ],
      ],
      's': [
        for (final s in shells)
          [
            r(s.position.dx),
            r(s.position.dy),
            r(s.velocity.dx),
            r(s.velocity.dy),
            s.owner.index,
            s.bounces,
            s.maxBounces,
            s.damage,
            s.icy ? 1 : 0,
          ],
      ],
      'b': [
        for (final b in blasts)
          [r(b.position.dx), r(b.position.dy), r(b.age), b.big ? 1 : 0],
      ],
      // The timer only matters until the result screen shows. Stopping it
      // there keeps snapshots identical, so the host can skip sending them
      // while players sit on the result screen.
      'o': _over ? [r(math.min(_overTime, resultDelay)), _winner?.index] : null,
      'm': GameMap.all.indexOf(map),
      'u': switch (powerUp) {
        final u? => [
          r(u.position.dx),
          r(u.position.dy),
          u.kind.index,
          u.age.floor(),
        ],
        null => null,
      },
    };
  }

  // Guest-side smoothing: tanks glide from where they were drawn toward
  // each new snapshot, and shells keep flying between snapshots.
  final List<_Pose> _posesFrom = [];
  final List<_Pose> _posesTo = [];
  List<Shell> _shellsAt = [];
  double _sinceSnapshot = 0;
  double _snapshotGap = 1 / 20;

  /// Shows a [toSnapshot] from the host. The guest's game never runs
  /// [update]; it only mirrors what the host sends, smoothed by
  /// [updateMirror].
  void applySnapshot(Map<String, Object?> snapshot) {
    double d(Object? v) => (v as num).toDouble();

    // Learn how often snapshots arrive, to pace the gliding.
    if (_posesTo.isNotEmpty) {
      _snapshotGap =
          _snapshotGap * 0.8 + _sinceSnapshot.clamp(0.01, 0.25) * 0.2;
    }
    final drawn = [for (final t in tanks) _Pose.of(t)];

    final tankData = snapshot['k'] as List;
    for (var i = 0; i < tanks.length; i++) {
      final v = tankData[i] as List;
      tanks[i]
        ..position = Offset(d(v[0]), d(v[1]))
        ..aim = d(v[2])
        ..hull = d(v[3])
        ..health = d(v[4])
        ..hitFlash = d(v[5]);
      final counting = Map.of(tanks[i].effects);
      tanks[i].effects.clear();
      if (v.length > 7) {
        for (final e in (v[6] as List).cast<List>()) {
          final kind = PowerUpKind.values[e[0] as int];
          // The host sends whole seconds rounded up. Keep the guest's own
          // smooth countdown while it agrees, so the warning flash is in
          // step with the host's.
          final sent = d(e[1]);
          final local = counting[kind];
          tanks[i].effects[kind] = local != null && local > sent - 1
              ? math.min(local, sent)
              : sent;
        }
        tanks[i].chilled = v[7] == 1 ? chillDuration : 0;
      }
    }

    final target = [for (final t in tanks) _Pose.of(t)];
    final first = _posesTo.isEmpty;
    _posesFrom
      ..clear()
      ..addAll([
        for (var i = 0; i < tanks.length; i++)
          // Jump straight there at the start, or after a respawn.
          first || (target[i].position - drawn[i].position).distance > 60
              ? target[i]
              : drawn[i],
      ]);
    _posesTo
      ..clear()
      ..addAll(target);
    for (var i = 0; i < tanks.length; i++) {
      _posesFrom[i].applyTo(tanks[i]);
    }

    shells
      ..clear()
      ..addAll([
        for (final v in (snapshot['s'] as List).cast<List>())
          Shell(
            Offset(d(v[0]), d(v[1])),
            Offset(d(v[2]), d(v[3])),
            Team.values[v[4] as int],
            bounces: v.length > 5 ? v[5] as int : 0,
            maxBounces: v.length > 6 ? v[6] as int : maxBounces,
            damage: v.length > 7 ? d(v[7]) : damage,
            icy: v.length > 8 && v[8] == 1,
          ),
      ]);

    blasts
      ..clear()
      ..addAll([
        for (final v in (snapshot['b'] as List).cast<List>())
          Blast(Offset(d(v[0]), d(v[1])), big: v[3] == 1)..age = d(v[2]),
      ]);

    _shellsAt = [for (final s in shells) s.copy()];
    _sinceSnapshot = 0;

    // Keep the local age of a power-up that's still there, so its pulse
    // stays smooth; the host only sends whole seconds.
    final u = snapshot['u'] as List?;
    if (u == null) {
      powerUp = null;
    } else {
      final position = Offset(d(u[0]), d(u[1]));
      final kind = PowerUpKind.values[u[2] as int];
      final current = powerUp;
      if (current == null ||
          current.kind != kind ||
          current.position != position) {
        powerUp = PowerUp(position, kind)..age = d(u[3]);
      } else if ((current.age - d(u[3])).abs() > 1.5) {
        current.age = d(u[3]);
      }
    }

    // The host picks the map (it may change each round).
    final mapIndex = snapshot['m'] as int?;
    if (mapIndex != null && mapIndex >= 0 && mapIndex < GameMap.all.length) {
      _map = GameMap.all[mapIndex];
    }

    final over = snapshot['o'] as List?;
    _over = over != null;
    _overTime = over == null ? 0 : d(over[0]);
    final winner = over?[1] as int?;
    _winner = winner == null ? null : Team.values[winner];
    notifyListeners();
  }

  /// Advances the guest's mirror between snapshots.
  void updateMirror(double dt) {
    if (_posesTo.isEmpty) return;
    _sinceSnapshot += dt;
    final t = (_sinceSnapshot / _snapshotGap).clamp(0.0, 1.0);
    for (var i = 0; i < tanks.length; i++) {
      _Pose.lerp(_posesFrom[i], _posesTo[i], t).applyTo(tanks[i]);
    }
    // Shells follow simple rules, so they can be moved ahead using the same
    // bouncing as the host. Stop after a short while in case a snapshot is
    // late and the shell has hit something.
    powerUp?.age += dt;
    for (final tank in tanks) {
      tank.effects.updateAll((_, left) => math.max(0, left - dt));
    }
    final ahead = math.min(_sinceSnapshot, 0.1);
    for (var i = 0; i < shells.length && i < _shellsAt.length; i++) {
      final base = _shellsAt[i];
      final shell = shells[i]
        ..position = base.position
        ..velocity = base.velocity
        ..bounces = base.bounces;
      _moveShell(shell, ahead);
    }
    notifyListeners();
  }

  void update(double dt) {
    if (_over) {
      _overTime += dt;
    } else {
      for (final tank in tanks) {
        _updateTank(tank, dt);
      }
      if (powerUps) _updatePowerUp(dt);
    }
    _updateShells(dt);
    for (final blast in blasts) {
      blast.age += dt;
    }
    blasts.removeWhere((b) => b.age >= blastDuration * (b.big ? 2 : 1));
    _checkGameOver();
    notifyListeners();
  }

  Tank _other(Tank tank) => identical(tank, red) ? blue : red;

  void _updateTank(Tank tank, double dt) {
    tank.cooldown = math.max(0, tank.cooldown - dt);
    tank.hitFlash = math.max(0, tank.hitFlash - dt);
    tank.chilled = math.max(0, tank.chilled - dt);
    tank.effects.updateAll((_, left) => left - dt);
    tank.effects.removeWhere((_, left) => left <= 0);
    if (!tank.alive) return;

    // Ice slows driving and turning; Speed boosts driving.
    final chill = tank.chilled > 0;
    final turnSpeed = rotateSpeed * (chill ? 0.6 : 1);
    final driveSpeed =
        moveSpeed * (tank.has(PowerUpKind.speed) ? 1.5 : 1) * (chill ? 0.5 : 1);

    final controls = tank.controls;

    final turn =
        ((controls.rotateRight ? 1 : 0) -
                (controls.rotateLeft ? 1 : 0) +
                controls.keyRotate)
            .clamp(-1, 1);
    final aimAt = controls.aimAt;
    var onTarget = false;
    if (turn != 0) {
      controls.aimAt = null;
      controls.fireAtAim = false;
      tank.aim = _wrapAngle(tank.aim + turn * turnSpeed * dt);
    } else if (aimAt != null && aimAt != tank.position) {
      final toAim = aimAt - tank.position;
      final diff = _wrapAngle(math.atan2(toAim.dy, toAim.dx) - tank.aim);
      final step = turnSpeed * dt;
      tank.aim = _wrapAngle(tank.aim + diff.clamp(-step, step));
      onTarget = diff.abs() <= step;
    }

    var input =
        (tank.flipped ? -controls.move : controls.move) + controls.keyMove;
    if (input.distance > 1) input = input / input.distance;
    final length = input.distance;
    if (length > 0.12) {
      // Ramp to full speed quickly so small thumb movements still feel snappy.
      final speed = driveSpeed * ((length - 0.12) / 0.5).clamp(0.0, 1.0);
      final velocity = input / length * speed;
      _moveTank(tank, velocity * dt);
      tank.hull = math.atan2(velocity.dy, velocity.dx);
    }

    final held = controls.fire || controls.mouseFire || controls.keyFire;
    final queued = controls.fireAtAim && onTarget;
    if ((held || queued) && tank.cooldown <= 0) {
      fire(tank);
      controls.fireAtAim = false;
    }
  }

  /// Moves one axis at a time so tanks slide along walls instead of sticking.
  void _moveTank(Tank tank, Offset delta) {
    final p = tank.position;
    final alongX = Offset(p.dx + delta.dx, p.dy);
    if (!_blocked(tank, alongX)) tank.position = alongX;
    final q = tank.position;
    final alongY = Offset(q.dx, q.dy + delta.dy);
    if (!_blocked(tank, alongY)) tank.position = alongY;
  }

  bool _blocked(Tank tank, Offset p) {
    if (!isOpen(p)) return true;
    final other = _other(tank);
    return (other.position - p).distance < tankRadius * 2;
  }

  /// Whether a tank could sit at [p] (with [margin] to spare) without touching
  /// a wall or the arena edge.
  bool isOpen(Offset p, {double margin = 0}) {
    final r = tankRadius + margin;
    if (p.dx < r ||
        p.dy < r ||
        p.dx > world.width - r ||
        p.dy > world.height - r) {
      return false;
    }
    for (final wall in walls) {
      if (_circleHitsRect(p, r, wall)) return false;
    }
    return true;
  }

  /// Whether a shell travelling from [from] to [to] would miss every wall.
  bool clearShot(Offset from, Offset to) {
    final delta = to - from;
    final steps = math.max(1, (delta.distance / 4).ceil());
    for (var i = 1; i <= steps; i++) {
      final p = from + delta * (i / steps);
      for (final wall in walls) {
        if (wall.inflate(shellRadius).contains(p)) return false;
      }
    }
    return true;
  }

  static bool _circleHitsRect(Offset c, double r, Rect rect) {
    final nearest = Offset(
      c.dx.clamp(rect.left, rect.right),
      c.dy.clamp(rect.top, rect.bottom),
    );
    return (c - nearest).distanceSquared < r * r;
  }

  void fire(Tank tank) {
    final dir = Offset(math.cos(tank.aim), math.sin(tank.aim));
    shells.add(
      Shell(
        tank.position + dir * (tankRadius + 8),
        dir * shellSpeed,
        tank.team,
        maxBounces: tank.has(PowerUpKind.ricochet) ? 2 : maxBounces,
        damage: tank.has(PowerUpKind.power) ? damage * 2 : damage,
        icy: tank.has(PowerUpKind.ice),
      ),
    );
    tank.cooldown = fireDelay * (tank.has(PowerUpKind.rapid) ? 0.5 : 1);
  }

  void _updatePowerUp(double dt) {
    final current = powerUp;
    if (current == null) {
      _powerUpWait -= dt;
      // After the wait, a random chance each moment.
      if (_powerUpWait <= 0 &&
          _random.nextDouble() < powerUpChancePerSecond * dt) {
        _spawnPowerUp();
      }
      return;
    }

    current.age += dt;
    for (final tank in tanks) {
      if (!tank.alive) continue;
      if ((tank.position - current.position).distance <
          tankRadius + powerUpRadius) {
        _collect(tank, current.kind);
        powerUp = null;
        // The wait starts once the effect is over (straight away for
        // Repair, which acts at once).
        _powerUpWait =
            (current.kind.timed ? effectDuration : 0) + powerUpWaitAfter;
        return;
      }
    }
    if (current.age >= powerUpLifetime) {
      powerUp = null;
      _powerUpWait = powerUpWaitAfter;
    }
  }

  /// Puts a random power-up on a random open spot that a tank can reach,
  /// not right next to either tank.
  void _spawnPowerUp() {
    for (var attempt = 0; attempt < 40; attempt++) {
      final spot = Offset(
        20 + _random.nextDouble() * (world.width - 40),
        20 + _random.nextDouble() * (world.height - 40),
      );
      if (!isOpen(spot, margin: 4)) continue;
      if (tanks.any((t) => (t.position - spot).distance < 70)) continue;
      final kind =
          PowerUpKind.values[_random.nextInt(PowerUpKind.values.length)];
      powerUp = PowerUp(spot, kind);
      return;
    }
  }

  void _collect(Tank tank, PowerUpKind kind) {
    if (kind == PowerUpKind.repair) {
      tank.health = math.min(maxHealth, tank.health + damage);
    } else {
      tank.effects[kind] = effectDuration;
    }
  }

  void _updateShells(double dt) {
    final ended = <Shell>{
      for (final shell in shells)
        if (!_moveShell(shell, dt)) shell,
    };
    for (final shell in ended) {
      blasts.add(Blast(shell.position));
    }
    shells.removeWhere(ended.contains);
    _collideShells(dt);

    shells.removeWhere((shell) {
      final p = shell.position;
      for (final tank in tanks) {
        if (tank.team == shell.owner || !tank.alive) continue;
        if ((tank.position - p).distance < tankRadius + shellRadius) {
          tank.health = math.max(0, tank.health - shell.damage);
          if (shell.icy) tank.chilled = chillDuration;
          tank.hitFlash = 0.15;
          blasts.add(Blast(p, big: !tank.alive));
          return true;
        }
      }
      return false;
    });
  }

  /// Bounces a shell normally gets before the next wall ends it (two with
  /// the Ricochet power-up).
  static const int maxBounces = 1;

  /// Every flat surface a shell can bounce off, as lines: the arena edges
  /// and each side of each wall block, pushed out by the shell's radius
  /// (where a shell's center turns around).
  List<({bool vertical, double at})> get bounceLines => [
    (vertical: true, at: shellRadius),
    (vertical: true, at: world.width - shellRadius),
    (vertical: false, at: shellRadius),
    (vertical: false, at: world.height - shellRadius),
    for (final wall in walls) ...[
      (vertical: true, at: wall.left - shellRadius),
      (vertical: true, at: wall.right + shellRadius),
      (vertical: false, at: wall.top - shellRadius),
      (vertical: false, at: wall.bottom + shellRadius),
    ],
  ];

  /// Traces a shell [tank] would fire at [angle], bouncing like a real one,
  /// and returns how long it takes to pass within reach of [target], or null
  /// if it ends first. Used by the computer player to plan bounce shots.
  double? previewShot(
    Tank tank,
    double angle,
    Offset target, {
    double maxTime = 1.6,
  }) {
    final direction = Offset(math.cos(angle), math.sin(angle));
    final shell = Shell(
      tank.position + direction * (tankRadius + 8),
      direction * shellSpeed,
      tank.team,
      maxBounces: tank.has(PowerUpKind.ricochet) ? 2 : maxBounces,
    );
    const step = 1 / 120;
    for (var t = step; t <= maxTime; t += step) {
      if (!_moveShell(shell, step)) return null;
      if ((shell.position - target).distance < tankRadius) return t;
    }
    return null;
  }

  /// Moves [shell] for [dt], bouncing off wall blocks and the arena edge.
  /// Returns false if it hit a wall with no bounces left; it is then left
  /// where it hit.
  ///
  /// Works along the shell's path rather than checking where it ends up, so
  /// a fast shell can't skip through a thin wall in one frame.
  bool _moveShell(Shell shell, double dt) {
    // A shell fired from inside a wall (a tank pressed against it) ends
    // straight away.
    for (final wall in walls) {
      if (wall.inflate(shellRadius).contains(shell.position)) return false;
    }
    var remaining = dt;
    // At most a couple of bounces fit in one frame (into a corner).
    for (var step = 0; step < 3 && remaining > 0; step++) {
      final from = shell.position;
      final move = shell.velocity * remaining;
      final hit = _firstHit(from, move);
      if (hit == null) {
        shell.position = from + move;
        return true;
      }
      // Stop just short of the surface so the next step starts outside.
      shell.position = from + move * math.max(0, hit.t - 1e-4);
      if (shell.bounces >= shell.maxBounces) return false;
      shell
        ..bounces += 1
        ..velocity = Offset(
          hit.flipX ? -shell.velocity.dx : shell.velocity.dx,
          hit.flipY ? -shell.velocity.dy : shell.velocity.dy,
        );
      remaining *= 1 - hit.t;
    }
    return true;
  }

  /// The first wall or arena edge a shell moving by [move] from [from]
  /// touches, as a fraction of the move, and which way it bounces.
  ({double t, bool flipX, bool flipY})? _firstHit(Offset from, Offset move) {
    var best = double.infinity;
    var flipX = false;
    var flipY = false;

    void consider(double t, {required bool x, required bool y}) {
      if (t < 0 || t > 1) return;
      if (t < best - 1e-9) {
        best = t;
        flipX = x;
        flipY = y;
      } else if ((t - best).abs() <= 1e-9) {
        // Exactly into a corner: bounce straight back.
        flipX |= x;
        flipY |= y;
      }
    }

    // Arena edges.
    const r = shellRadius;
    final to = from + move;
    if (move.dx > 0 && to.dx > world.width - r) {
      consider((world.width - r - from.dx) / move.dx, x: true, y: false);
    } else if (move.dx < 0 && to.dx < r) {
      consider((r - from.dx) / move.dx, x: true, y: false);
    }
    if (move.dy > 0 && to.dy > world.height - r) {
      consider((world.height - r - from.dy) / move.dy, x: false, y: true);
    } else if (move.dy < 0 && to.dy < r) {
      consider((r - from.dy) / move.dy, x: false, y: true);
    }

    // Wall blocks, grown by the shell's radius so a point can stand in for
    // the shell. The side it enters through decides the bounce.
    for (final wall in walls) {
      final box = wall.inflate(r);
      final (enterX, exitX) = _slab(from.dx, move.dx, box.left, box.right);
      final (enterY, exitY) = _slab(from.dy, move.dy, box.top, box.bottom);
      final enter = math.max(enterX, enterY);
      final exit = math.min(exitX, exitY);
      if (enter > exit || enter < 0) continue;
      consider(enter, x: enterX >= enterY, y: enterY >= enterX);
    }

    return best.isFinite ? (t: best, flipX: flipX, flipY: flipY) : null;
  }

  /// When a point moving by [d] from [p] is between [low] and [high] on one
  /// axis, as fractions of the move.
  static (double, double) _slab(double p, double d, double low, double high) {
    if (d == 0) {
      return p >= low && p <= high
          ? (double.negativeInfinity, double.infinity)
          : (double.infinity, double.negativeInfinity);
    }
    final a = (low - p) / d;
    final b = (high - p) / d;
    return a < b ? (a, b) : (b, a);
  }

  /// How close two shells must pass to knock each other out. A little more
  /// than touching, matching how big they look on screen.
  static const double shellHitDistance = shellRadius * 2 + 3;

  /// Destroys pairs of opposing shells that met during the last [dt] (a
  /// power shot survives meeting an ordinary one).
  ///
  /// Shells approaching head-on close in by over 10 units a frame, far more
  /// than their size, so checking only where they end up would let them pass
  /// through each other. Instead this finds how close each pair came at any
  /// moment during the frame, from where they started to where they are now.
  void _collideShells(double dt) {
    final hit = <Shell>{};
    for (var i = 0; i < shells.length; i++) {
      final a = shells[i];
      if (hit.contains(a)) continue;
      for (var j = i + 1; j < shells.length; j++) {
        final b = shells[j];
        if (b.owner == a.owner || hit.contains(b)) continue;

        // Separation at the start of the frame, and how it changed.
        final change = (a.velocity - b.velocity) * dt;
        final start = (a.position - b.position) - change;
        final lengthSquared = change.distanceSquared;
        final t = lengthSquared == 0
            ? 0.0
            : (-(start.dx * change.dx + start.dy * change.dy) / lengthSquared)
                  .clamp(0.0, 1.0);
        if ((start + change * t).distance > shellHitDistance) continue;

        // A power shot punches through an ordinary shell, but loses its extra
        // power doing so. Otherwise both are destroyed.
        final aPower = a.damage > damage;
        final bPower = b.damage > damage;
        if (aPower && !bPower) {
          hit.add(b);
          a.damage = damage;
        } else if (bPower && !aPower) {
          hit.add(a);
          b.damage = damage;
        } else {
          hit
            ..add(a)
            ..add(b);
        }
        // Blast where they met.
        final back = 1 - t;
        blasts.add(
          Blast(
            Offset.lerp(
              a.position - a.velocity * dt * back,
              b.position - b.velocity * dt * back,
              0.5,
            )!,
          ),
        );
        if (hit.contains(a)) break;
      }
    }
    shells.removeWhere(hit.contains);
  }

  void _checkGameOver() {
    if (_over) return;
    final redDead = !red.alive;
    final blueDead = !blue.alive;
    if (!redDead && !blueDead) return;
    _over = true;
    _winner = redDead && blueDead ? null : (redDead ? Team.blue : Team.red);
  }

  static double _wrapAngle(double a) {
    const tau = math.pi * 2;
    a %= tau;
    return a > math.pi ? a - tau : a;
  }
}

/// Where a tank is and which way it faces, for smoothing on the guest.
class _Pose {
  const _Pose(this.position, this.aim, this.hull);

  _Pose.of(Tank tank) : this(tank.position, tank.aim, tank.hull);

  final Offset position;
  final double aim;
  final double hull;

  void applyTo(Tank tank) {
    tank
      ..position = position
      ..aim = aim
      ..hull = hull;
  }

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
    Offset.lerp(a.position, b.position, t)!,
    a.aim + TankGame._wrapAngle(b.aim - a.aim) * t,
    a.hull + TankGame._wrapAngle(b.hull - a.hull) * t,
  );
}
