import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'controls.dart';
import 'game.dart';

void main() {
  runApp(const TankApp());
}

const Color redColor = Color(0xFFE53935);
const Color blueColor = Color(0xFF1E88E5);

Color teamColor(Team team) => team == Team.red ? redColor : blueColor;
String teamName(Team team) => team == Team.red ? 'RED' : 'BLUE';

class TankApp extends StatelessWidget {
  const TankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tanks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueGrey,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final TankGame game = TankGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    // Clamp so a dropped frame or a backgrounded tab can't teleport anything.
    game.update(dt.clamp(0.0, 0.05));
  }

  @override
  void dispose() {
    _ticker.dispose();
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF15181C),
      body: SafeArea(
        // Keep a phone-sized layout when opened in a wide desktop browser.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _buildGame(),
          ),
        ),
      ),
    );
  }

  Widget _buildGame() {
    return Stack(
      children: [
        Column(
          children: [
            // Blue sits across from Red, so their controls face them.
            RotatedBox(
              quarterTurns: 2,
              child: ControlPanel(game: game, tank: game.blue),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: TankGame.world.width / TankGame.world.height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CustomPaint(
                          painter: ArenaPainter(game),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ControlPanel(game: game, tank: game.red),
          ],
        ),
        ListenableBuilder(
          listenable: game,
          builder: (context, _) => game.showResult
              ? ResultOverlay(game: game)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// One player's controls: health bar, movement stick, turret rotation, fire.
class ControlPanel extends StatelessWidget {
  const ControlPanel({super.key, required this.game, required this.tank});

  final TankGame game;
  final Tank tank;

  @override
  Widget build(BuildContext context) {
    final color = teamColor(tank.team);
    final controls = tank.controls;
    // Leave the arena as much room as possible on short Safari viewports.
    final height = (MediaQuery.sizeOf(context).height * 0.22).clamp(
      130.0,
      170.0,
    );
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.08),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        children: [
          HealthBar(game: game, tank: tank),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stick = math.min(
                  constraints.maxHeight,
                  constraints.maxWidth * 0.34,
                );
                final rotate = stick * 0.58;
                final fire = stick * 0.92;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Joystick(
                      size: stick,
                      color: color,
                      onChanged: (v) => controls.move = v,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HoldButton(
                          size: rotate,
                          color: Colors.blueGrey.shade600,
                          icon: Icons.rotate_left,
                          onChanged: (p) => controls.rotateLeft = p,
                        ),
                        SizedBox(width: rotate * 0.15),
                        HoldButton(
                          size: rotate,
                          color: Colors.blueGrey.shade600,
                          icon: Icons.rotate_right,
                          onChanged: (p) => controls.rotateRight = p,
                        ),
                      ],
                    ),
                    HoldButton(
                      size: fire,
                      color: color,
                      label: 'FIRE',
                      onChanged: (p) => controls.fire = p,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HealthBar extends StatelessWidget {
  const HealthBar({super.key, required this.game, required this.tank});

  final TankGame game;
  final Tank tank;

  @override
  Widget build(BuildContext context) {
    final color = teamColor(tank.team);
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final fraction = tank.health / TankGame.maxHealth;
        return Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                teamName(tank.team),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 200),
                      widthFactor: fraction,
                      heightFactor: 1,
                      child: ColoredBox(
                        color: tank.hitFlash > 0 ? Colors.white : color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                tank.health.round().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class ArenaPainter extends CustomPainter {
  ArenaPainter(this.game) : super(repaint: game);

  final TankGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / TankGame.world.width;
    canvas.scale(scale);
    final world = Offset.zero & TankGame.world;

    canvas.drawRect(world, Paint()..color = const Color(0xFF3B4A36));

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double x = 30; x < world.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, world.height), grid);
    }
    for (double y = 30; y < world.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(world.width, y), grid);
    }
    canvas.drawLine(
      Offset(0, world.height / 2),
      Offset(world.width, world.height / 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..strokeWidth = 1.5,
    );

    final wallFill = Paint()..color = const Color(0xFF6D6A63);
    final wallEdge = Paint()
      ..color = const Color(0xFF4A4843)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final wall in TankGame.walls) {
      final r = RRect.fromRectAndRadius(wall, const Radius.circular(3));
      canvas.drawRRect(r, wallFill);
      canvas.drawRRect(r.deflate(1), wallEdge);
    }

    for (final tank in game.tanks) {
      _paintTank(canvas, tank);
    }

    for (final shell in game.shells) {
      canvas.drawCircle(
        shell.position,
        TankGame.shellRadius + 1.5,
        Paint()..color = teamColor(shell.owner),
      );
      canvas.drawCircle(
        shell.position,
        TankGame.shellRadius - 0.5,
        Paint()..color = Colors.white,
      );
    }

    for (final blast in game.blasts) {
      final duration = TankGame.blastDuration * (blast.big ? 2 : 1);
      final t = (blast.age / duration).clamp(0.0, 1.0);
      final radius = (blast.big ? 10 : 4) + t * (blast.big ? 34 : 14);
      canvas.drawCircle(
        blast.position,
        radius,
        Paint()..color = Colors.orange.withValues(alpha: (1 - t) * 0.8),
      );
      canvas.drawCircle(
        blast.position,
        radius * 0.5,
        Paint()..color = Colors.yellow.withValues(alpha: (1 - t) * 0.9),
      );
    }
  }

  void _paintTank(Canvas canvas, Tank tank) {
    final base = teamColor(tank.team);
    final color = tank.alive ? base : Color.lerp(base, Colors.black, 0.65)!;
    final dark = Color.lerp(color, Colors.black, 0.45)!;
    final light = Color.lerp(color, Colors.white, 0.25)!;

    canvas.save();
    canvas.translate(tank.position.dx, tank.position.dy);

    if (tank.alive) {
      // Faint aim guide so players can line up shots.
      final dir = Offset(math.cos(tank.aim), math.sin(tank.aim));
      final guide = Paint()
        ..color = base.withValues(alpha: 0.45)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      for (double d = 26; d < 80; d += 9) {
        canvas.drawLine(dir * d, dir * (d + 4), guide);
      }
    }

    // Hull and tracks, facing the last direction of travel.
    canvas.save();
    canvas.rotate(tank.hull);
    final track = Paint()..color = const Color(0xFF222222);
    canvas.drawRRect(
      RRect.fromLTRBR(-14, -14, 14, -7, const Radius.circular(2)),
      track,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(-14, 7, 14, 14, const Radius.circular(2)),
      track,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(-12, -9, 12, 9, const Radius.circular(3)),
      Paint()..color = color,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(-12, -9, 12, 9, const Radius.circular(3)),
      Paint()
        ..color = dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();

    // Turret and barrel, pointing where the tank will shoot.
    canvas.save();
    canvas.rotate(tank.aim);
    canvas.drawRRect(
      RRect.fromLTRBR(2, -2.6, 22, 2.6, const Radius.circular(1.5)),
      Paint()..color = dark,
    );
    canvas.restore();
    canvas.drawCircle(Offset.zero, 7.5, Paint()..color = light);
    canvas.drawCircle(
      Offset.zero,
      7.5,
      Paint()
        ..color = dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    if (tank.hitFlash > 0) {
      canvas.drawCircle(
        Offset.zero,
        TankGame.tankRadius + 2,
        Paint()
          ..color = Colors.white.withValues(alpha: tank.hitFlash / 0.15 * 0.7),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(ArenaPainter oldDelegate) => oldDelegate.game != game;
}

/// Winner screen, split so each player reads their half the right way up.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({super.key, required this.game});

  final TankGame game;

  @override
  Widget build(BuildContext context) {
    final winner = game.winner;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Column(
        children: [
          Expanded(
            child: RotatedBox(
              quarterTurns: 2,
              child: _ResultHalf(winner: winner, viewer: Team.blue),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: FilledButton.icon(
              onPressed: game.reset,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 18,
                ),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.replay),
              label: const Text('Rematch'),
            ),
          ),
          Expanded(
            child: _ResultHalf(winner: winner, viewer: Team.red),
          ),
        ],
      ),
    );
  }
}

class _ResultHalf extends StatelessWidget {
  const _ResultHalf({required this.winner, required this.viewer});

  final Team? winner;
  final Team viewer;

  @override
  Widget build(BuildContext context) {
    final w = winner;
    final title = w == null ? 'DRAW' : '${teamName(w)} WINS!';
    final subtitle = w == null
        ? 'Both tanks destroyed'
        : (w == viewer ? 'Victory' : 'Defeat');
    final color = w == null ? Colors.white : teamColor(w);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: const [Shadow(blurRadius: 12, color: Colors.black)],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 20, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
