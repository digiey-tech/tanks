import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'game.dart';

enum Difficulty {
  easy(
    'Easy',
    aimError: 0.2,
    lead: 0,
    reaction: 0.7,
    shotGap: 0.55,
    dodge: 0,
    speed: 0.55,
    bankShots: false,
    powerUpRange: 0,
  ),
  normal(
    'Normal',
    aimError: 0.09,
    lead: 0.6,
    reaction: 0.4,
    shotGap: 0.2,
    dodge: 0.45,
    speed: 0.8,
    bankShots: false,
    powerUpRange: 120,
  ),
  hard(
    'Hard',
    aimError: 0.03,
    lead: 1,
    reaction: 0.15,
    shotGap: 0,
    dodge: 0.85,
    speed: 1,
    bankShots: true,
    powerUpRange: 180,
  );

  const Difficulty(
    this.label, {
    required this.aimError,
    required this.lead,
    required this.reaction,
    required this.shotGap,
    required this.dodge,
    required this.speed,
    required this.bankShots,
    required this.powerUpRange,
  });

  final String label;

  /// Typical aiming mistake, in radians.
  final double aimError;

  /// How far ahead of a moving target it aims: 0 aims where the target is,
  /// 1 aims where the target will be when the shell arrives.
  final double lead;

  /// Seconds the target must be in view before it starts shooting.
  final double reaction;

  /// Extra pause between shots, on top of the normal reload time.
  final double shotGap;

  /// Chance of trying to dodge each incoming shell.
  final double dodge;

  /// Fraction of full driving speed.
  final double speed;

  /// Whether it bounces shots off walls to reach a target it can't see.
  final bool bankShots;

  /// How far it will go out of its way for a power-up. Zero means it never
  /// goes for them on purpose (though it may drive over one by chance).
  final double powerUpRange;
}

/// Drives one tank by writing to its [TankControls], exactly like a player's
/// thumbstick and buttons would. It turns, reloads and moves under the same
/// limits as a human.
class TankAi {
  TankAi({
    required this.game,
    required this.tank,
    required this.difficulty,
    math.Random? random,
  }) : _random = random ?? math.Random() {
    reset();
  }

  final TankGame game;
  final Tank tank;
  final Difficulty difficulty;
  final math.Random _random;

  Tank get _target => identical(tank, game.red) ? game.blue : game.red;

  Offset? _destination;
  double _replanIn = 0;
  double _stuckTime = 0;
  late Offset _lastPosition;

  double _aimOffset = 0;
  double _aimOffsetIn = 0;
  double _sightTime = 0;
  double _shotWait = 0;

  late Offset _lastTargetPosition;
  Offset _targetVelocity = Offset.zero;

  /// Whether it decided to dodge each shell, so it only rolls once per shell.
  final Map<Shell, bool> _dodgeDecisions = {};

  void reset() {
    _destination = null;
    _replanIn = 0;
    _stuckTime = 0;
    _lastPosition = tank.position;
    _aimOffset = 0;
    _aimOffsetIn = 0;
    _sightTime = 0;
    _shotWait = 0;
    _lastTargetPosition = _target.position;
    _targetVelocity = Offset.zero;
    _dodgeDecisions.clear();
    _bankShot = null;
    _bankSearchIn = 0;
    _bankTime = 0;
    _release();
  }

  void update(double dt) {
    if (game.isOver || !tank.alive || dt <= 0) {
      _release();
      return;
    }
    final target = _target;

    // Estimate the target's velocity so shots can lead it.
    final velocity = (target.position - _lastTargetPosition) / dt;
    _lastTargetPosition = target.position;
    if (velocity.distance <= TankGame.moveSpeed * 1.5) {
      _targetVelocity = Offset.lerp(_targetVelocity, velocity, 0.15)!;
    }

    final inSight = game.clearShot(tank.position, target.position);
    _sightTime = inSight ? _sightTime + dt : 0;

    // With no direct line, look for a bounce shot now and then (tracing
    // shots takes a little work, and the best one changes slowly).
    if (inSight || !difficulty.bankShots) {
      _bankShot = null;
      _bankTime = 0;
    } else {
      _bankSearchIn -= dt;
      if (_bankSearchIn <= 0) {
        _bankSearchIn = 0.2;
        _bankShot = _findBankShot(target);
      }
      _bankTime = _bankShot == null ? 0 : _bankTime + dt;
    }

    _aim(dt, target, inSight);
    _drive(dt, target);
  }

  void _release() {
    final c = tank.controls;
    c.move = Offset.zero;
    c.rotateLeft = false;
    c.rotateRight = false;
    c.fire = false;
  }

  /// Hard only: a bounce shot to take while there's no direct line, as the
  /// angle to fire at and the shell's flight time.
  ({double angle, double time})? _bankShot;
  double _bankSearchIn = 0;

  /// How long the current bounce shot has been available, standing in for
  /// [_sightTime] before firing.
  double _bankTime = 0;

  /// Finds the quickest shot that reaches [target] after bouncing once.
  ///
  /// Mirroring the target across a surface gives the direction that bounces
  /// off it toward the target. Each candidate is traced with the same
  /// physics as real shells, so shots that would clip a block or miss the
  /// surface are thrown out. A second pass leads a moving target by the
  /// shell's actual flight time.
  ({double angle, double time})? _findBankShot(Tank target) {
    ({double angle, double time})? best;
    for (final line in game.bounceLines) {
      var aimAt = target.position;
      ({double angle, double time})? shot;
      for (var pass = 0; pass < 2; pass++) {
        final mirrored = line.vertical
            ? Offset(2 * line.at - aimAt.dx, aimAt.dy)
            : Offset(aimAt.dx, 2 * line.at - aimAt.dy);
        final toMirror = mirrored - tank.position;
        final angle = math.atan2(toMirror.dy, toMirror.dx);
        final time = game.previewShot(tank, angle, aimAt);
        if (time == null) {
          shot = null;
          break;
        }
        shot = (angle: angle, time: time);
        aimAt = target.position + _targetVelocity * (time * difficulty.lead);
      }
      if (shot != null && (best == null || shot.time < best.time)) {
        best = shot;
      }
    }
    return best;
  }

  void _aim(double dt, Tank target, bool inSight) {
    final c = tank.controls;

    // Hold each aiming mistake for a moment instead of jittering every frame.
    _aimOffsetIn -= dt;
    if (_aimOffsetIn <= 0) {
      _aimOffsetIn = 0.5 + _random.nextDouble() * 0.6;
      _aimOffset = (_random.nextDouble() * 2 - 1) * difficulty.aimError;
    }

    final distance = (target.position - tank.position).distance;
    final bank = _bankShot;
    final double desired;
    final double tolerance;
    final bool ready;
    if (!inSight && bank != null) {
      // A bounce shot. Its longer path magnifies aiming mistakes, so be
      // more careful with it.
      desired = bank.angle + _aimOffset * 0.5;
      tolerance = math.atan2(
        TankGame.tankRadius * 0.6,
        bank.time * TankGame.shellSpeed,
      );
      ready = _bankTime >= difficulty.reaction;
    } else {
      final travelTime = distance / TankGame.shellSpeed;
      final aimPoint =
          target.position + _targetVelocity * (travelTime * difficulty.lead);
      final toAim = aimPoint - tank.position;
      desired = math.atan2(toAim.dy, toAim.dx) + _aimOffset;
      tolerance = math.atan2(TankGame.tankRadius, distance);
      ready = inSight && _sightTime >= difficulty.reaction;
    }
    final diff = _wrap(desired - tank.aim);

    // Stop turning once within one frame's turn, so it doesn't wobble.
    final deadband = TankGame.rotateSpeed * dt * 0.6;
    c.rotateRight = diff > deadband;
    c.rotateLeft = diff < -deadband;

    _shotWait = math.max(0, _shotWait - dt);
    final shoot =
        ready && diff.abs() < tolerance && _shotWait <= 0 && tank.cooldown <= 0;
    c.fire = shoot;
    if (shoot) _shotWait = TankGame.fireDelay + difficulty.shotGap;
  }

  /// The destination it's driving to, for tests.
  @visibleForTesting
  Offset? get destination => _destination;

  /// The power-up it's currently chasing, and for how long.
  PowerUp? _chasing;
  double _chaseTime = 0;

  /// One it gave up on, so it doesn't keep trying to reach it.
  PowerUp? _gaveUpOn;

  /// Where to go for a power-up worth a detour, or null.
  Offset? _wantedPowerUp(Tank target, double dt) {
    final powerUp = game.powerUp;
    if (powerUp == null ||
        difficulty.powerUpRange <= 0 ||
        identical(powerUp, _gaveUpOn)) {
      return null;
    }
    // Repair is no use at full health.
    if (powerUp.kind == PowerUpKind.repair &&
        tank.health >= TankGame.maxHealth) {
      return null;
    }
    final mine = (powerUp.position - tank.position).distance;
    if (mine > difficulty.powerUpRange) return null;
    // Not worth racing an opponent who's much closer to it.
    final theirs = (powerUp.position - target.position).distance;
    if (theirs < mine * 0.6) return null;

    if (!identical(powerUp, _chasing)) {
      _chasing = powerUp;
      _chaseTime = 0;
    }
    _chaseTime += dt;
    // Probably stuck behind a wall; leave it.
    if (_chaseTime > 4) {
      _gaveUpOn = powerUp;
      return null;
    }
    return powerUp.position;
  }

  void _drive(double dt, Tank target) {
    final dodge = _dodgeDirection();
    if (dodge != null) {
      _setMove(dodge * math.max(difficulty.speed, 0.85));
      _lastPosition = tank.position;
      return;
    }

    // Replan if it hasn't moved while trying to (pushing into a wall or tank).
    final moved = (tank.position - _lastPosition).distance;
    _lastPosition = tank.position;
    if (tank.controls.move != Offset.zero &&
        moved < TankGame.moveSpeed * difficulty.speed * dt * 0.3) {
      _stuckTime += dt;
    } else {
      _stuckTime = 0;
    }

    // Detour for a handy power-up.
    final wanted = _wantedPowerUp(target, dt);
    if (wanted != null) {
      _destination = wanted;
      _replanIn = math.max(_replanIn, 0.3);
    }

    _replanIn -= dt;
    final destination = _destination;
    if (destination == null ||
        _replanIn <= 0 ||
        _stuckTime > 0.25 ||
        (destination - tank.position).distance < 6) {
      _plan(target);
    }

    final toGo = _destination! - tank.position;
    _setMove(
      toGo.distance < 6 ? Offset.zero : toGo / toGo.distance * difficulty.speed,
    );
  }

  /// Picks a spot to drive to: one with a clear shot at the target, at a
  /// comfortable range, and not too far away. Choosing nearby spots most of the
  /// time makes it strafe back and forth instead of sitting still.
  void _plan(Tank target) {
    _replanIn = 0.7 + _random.nextDouble() * 0.9;
    _stuckTime = 0;

    const margin = 4.0;
    const r = TankGame.tankRadius + margin;
    final world = TankGame.world;

    Offset? best;
    var bestScore = double.negativeInfinity;
    for (var i = 0; i < 24; i++) {
      final Offset p;
      if (i.isEven) {
        final angle = _random.nextDouble() * math.pi * 2;
        final dist = 30 + _random.nextDouble() * 70;
        p = tank.position + Offset(math.cos(angle), math.sin(angle)) * dist;
      } else {
        p = Offset(
          r + _random.nextDouble() * (world.width - r * 2),
          r + _random.nextDouble() * (world.height - r * 2),
        );
      }
      if (!game.isOpen(p, margin: margin)) continue;

      final range = (target.position - p).distance;
      var score = 0.0;
      if (game.clearShot(p, target.position)) score += 120;
      score -= (range - 170).abs() * 0.4;
      if (range < 80) score -= 100;
      score -= (p - tank.position).distance * 0.35;
      score += _random.nextDouble() * 20;
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    _destination = best ?? tank.position;
  }

  /// A direction to swerve if an enemy shell is about to hit, or null.
  Offset? _dodgeDirection() {
    _dodgeDecisions.removeWhere((shell, _) => !game.shells.contains(shell));

    for (final shell in game.shells) {
      if (shell.owner == tank.team) continue;
      final dir = shell.velocity / shell.velocity.distance;
      final rel = tank.position - shell.position;
      final ahead = rel.dx * dir.dx + rel.dy * dir.dy;
      if (ahead <= 0 || ahead > 150) continue;
      // Signed sideways distance between the shell's path and the tank.
      final side = rel.dx * dir.dy - rel.dy * dir.dx;
      if (side.abs() > TankGame.tankRadius + TankGame.shellRadius + 4) {
        continue;
      }

      final dodging = _dodgeDecisions.putIfAbsent(
        shell,
        () => _random.nextDouble() < difficulty.dodge,
      );
      if (!dodging) continue;

      // Step out of the shell's path on whichever side the tank already
      // leans toward; switch sides if that way is blocked.
      final perpendicular = Offset(dir.dy, -dir.dx) * (side >= 0 ? 1 : -1);
      final probe = tank.position + perpendicular * (TankGame.tankRadius + 6);
      return game.isOpen(probe) ? perpendicular : -perpendicular;
    }
    return null;
  }

  /// [TankControls.move] is in the player's own frame, so flip it for a tank
  /// whose controls face the other way.
  void _setMove(Offset world) {
    tank.controls.move = tank.flipped ? -world : world;
  }

  static double _wrap(double a) {
    const tau = math.pi * 2;
    a %= tau;
    return a > math.pi ? a - tau : a;
  }
}
