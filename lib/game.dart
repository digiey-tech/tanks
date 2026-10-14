import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum Team { red, blue }

/// Live input for one tank, written by the touch controls.
class TankControls {
  /// Joystick vector in the player's own frame (up = away from the player).
  /// Length is between 0 and 1.
  Offset move = Offset.zero;
  bool rotateLeft = false;
  bool rotateRight = false;
  bool fire = false;
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

  bool get alive => health > 0;

  void reset() {
    position = spawn;
    aim = spawnAim;
    hull = spawnAim;
    health = TankGame.maxHealth;
    cooldown = 0;
    hitFlash = 0;
  }
}

class Shell {
  Shell(this.position, this.velocity, this.owner);

  Offset position;
  final Offset velocity;
  final Team owner;
}

class Blast {
  Blast(this.position, {this.big = false});

  final Offset position;
  final bool big;
  double age = 0;
}

class TankGame extends ChangeNotifier {
  TankGame() {
    reset();
  }

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
  static const double resultDelay = 0.9;

  /// Cover blocks, symmetric under a 180° rotation so neither side is favored.
  static final List<Rect> walls = [
    const Rect.fromLTWH(40, 128, 72, 16),
    const Rect.fromLTWH(188, 128, 72, 16),
    const Rect.fromLTWH(40, 276, 72, 16),
    const Rect.fromLTWH(188, 276, 72, 16),
    Rect.fromCenter(center: const Offset(150, 210), width: 32, height: 32),
  ];

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

  void reset() {
    for (final tank in tanks) {
      tank.reset();
    }
    shells.clear();
    blasts.clear();
    _over = false;
    _overTime = 0;
    _winner = null;
    notifyListeners();
  }

  void update(double dt) {
    if (_over) {
      _overTime += dt;
    } else {
      for (final tank in tanks) {
        _updateTank(tank, dt);
      }
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
    if (!tank.alive) return;

    final controls = tank.controls;

    final turn = (controls.rotateRight ? 1 : 0) - (controls.rotateLeft ? 1 : 0);
    tank.aim = _wrapAngle(tank.aim + turn * rotateSpeed * dt);

    var input = controls.move;
    if (tank.flipped) input = -input;
    final length = input.distance;
    if (length > 0.12) {
      // Ramp to full speed quickly so small thumb movements still feel snappy.
      final speed = moveSpeed * ((length - 0.12) / 0.5).clamp(0.0, 1.0);
      final velocity = input / length * speed;
      _moveTank(tank, velocity * dt);
      tank.hull = math.atan2(velocity.dy, velocity.dx);
    }

    if (controls.fire && tank.cooldown <= 0) {
      fire(tank);
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
    const r = tankRadius;
    if (p.dx < r ||
        p.dy < r ||
        p.dx > world.width - r ||
        p.dy > world.height - r) {
      return true;
    }
    for (final wall in walls) {
      if (_circleHitsRect(p, r, wall)) return true;
    }
    final other = _other(tank);
    return (other.position - p).distance < r * 2;
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
      ),
    );
    tank.cooldown = fireDelay;
  }

  void _updateShells(double dt) {
    shells.removeWhere((shell) {
      shell.position += shell.velocity * dt;
      final p = shell.position;

      if (!(Offset.zero & world).contains(p)) return true;

      for (final wall in walls) {
        if (wall.inflate(shellRadius).contains(p)) {
          blasts.add(Blast(p));
          return true;
        }
      }

      for (final tank in tanks) {
        if (tank.team == shell.owner || !tank.alive) continue;
        if ((tank.position - p).distance < tankRadius + shellRadius) {
          tank.health = math.max(0, tank.health - damage);
          tank.hitFlash = 0.15;
          blasts.add(Blast(p, big: !tank.alive));
          return true;
        }
      }
      return false;
    });
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
