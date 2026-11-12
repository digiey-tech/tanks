import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'ai.dart';
import 'controls.dart';
import 'game.dart';
import 'lobby.dart';
import 'online.dart';

void main() {
  runApp(const TankApp());
}

const Color redColor = Color(0xFFE53935);

/// Whether this looks like a computer rather than a phone or tablet. Only used
/// to decide whether to show keyboard and mouse tips.
bool get onComputer => switch (defaultTargetPlatform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  _ => false,
};
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
      home: const MenuScreen(),
    );
  }
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Difficulty _difficulty = Difficulty.normal;

  void _start(Difficulty? difficulty) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(difficulty: difficulty),
      ),
    );
  }

  void _openLobby({required bool host}) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => LobbyScreen(host: host)));
  }

  @override
  Widget build(BuildContext context) {
    const buttonText = TextStyle(fontSize: 20, fontWeight: FontWeight.w800);
    final lobbyButton = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white38),
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF15181C),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'TAN',
                          style: TextStyle(color: redColor),
                        ),
                        TextSpan(
                          text: 'KS',
                          style: TextStyle(color: blueColor),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Single player',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<Difficulty>(
                    segments: [
                      for (final d in Difficulty.values)
                        ButtonSegment(value: d, label: Text(d.label)),
                    ],
                    selected: {_difficulty},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _difficulty = s.first),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _start(_difficulty),
                    style: FilledButton.styleFrom(
                      backgroundColor: redColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: buttonText,
                    ),
                    icon: const Icon(Icons.person),
                    label: const Text('1 Player vs CPU'),
                  ),
                  if (onComputer) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'WASD or arrows to move, mouse to aim, click to fire.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.white54),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const Text(
                    'Two players, one phone or computer',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _start(null),
                    style: FilledButton.styleFrom(
                      backgroundColor: blueColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: buttonText,
                    ),
                    icon: const Icon(Icons.people),
                    label: const Text('2 Players'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    onComputer
                        ? 'Red: WASD, Q/E to aim, Space to fire.\n'
                              'Blue: arrows, , and . to aim, / or Enter to fire.'
                        : 'Sit facing each other with the phone flat between '
                              'you, or share a keyboard on a computer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Two devices',
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openLobby(host: true),
                          style: lobbyButton,
                          icon: const Icon(Icons.wifi_tethering),
                          label: const Text('Host'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openLobby(host: false),
                          style: lobbyButton,
                          icon: const Icon(Icons.login),
                          label: const Text('Join'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'One player hosts and shares a code. Both need internet '
                    'to connect; it plays best on the same Wi-Fi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  /// With neither [difficulty] nor [online], two people share this device.
  const GameScreen({super.key, this.difficulty, this.online})
    : assert(difficulty == null || online == null);

  /// Single player against the computer.
  final Difficulty? difficulty;

  /// A battle against another device.
  final OnlineMatch? online;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final TankGame game = widget.online?.game ?? TankGame();
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// Drives the blue tank in single-player mode.
  TankAi? _ai;

  OnlineMatch? get _online => widget.online;

  /// Two people sharing this one device.
  bool get _sharedScreen => _ai == null && _online == null;

  /// The tank this device's player drives when only one person uses it.
  Tank get _me => _online?.me ?? game.red;
  Tank get _opponent => _online?.opponent ?? game.blue;

  /// The guest in online play sees the arena turned around, so their own tank
  /// is at the bottom like the host's is.
  bool get _viewFlipped => _online != null && !_online!.isHost;

  @override
  void initState() {
    super.initState();
    final difficulty = widget.difficulty;
    if (difficulty != null) {
      _ai = TankAi(game: game, tank: game.blue, difficulty: difficulty);
    }
    _ticker = createTicker(_onTick)..start();
  }

  void _rematch() {
    final online = _online;
    if (online != null) {
      online.rematch();
      return;
    }
    game.reset();
    _ai?.reset();
  }

  void _toMenu() => Navigator.of(context).pop();

  /// When one person uses this device, the mouse (or a tap in the arena) also
  /// aims their tank. It's off when two people share the device so neither
  /// gets an edge from it.
  TankControls get _mouse => _me.controls;

  final GlobalKey _arenaKey = GlobalKey();

  late final Map<Tank, KeyBindings> _keys = _sharedScreen
      ? {game.red: KeyBindings.red, game.blue: KeyBindings.blue}
      : {_me: KeyBindings.solo};

  /// Claims game keys so they don't also move focus or press the screen's
  /// buttons (Space and Enter would otherwise activate a focused button).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) =>
      _keys.values.any((k) => k.handles(event.logicalKey))
      ? KeyEventResult.handled
      : KeyEventResult.ignored;

  /// Turns the red tank's gun toward a point on screen.
  void _aimAt(PointerEvent event, {required bool marker}) {
    final box = _arenaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final scale = box.size.width / TankGame.world.width;
    _mouse
      ..aimAt = box.globalToLocal(event.position) / scale
      ..showAimMarker = marker;
  }

  /// The gun follows the mouse wherever it is on screen.
  void _onMouse(PointerEvent event) {
    if (_sharedScreen || event.kind != PointerDeviceKind.mouse) return;
    _aimAt(event, marker: false);
  }

  void _onArenaPointerDown(PointerDownEvent event) {
    if (_sharedScreen) return;
    if (event.kind == PointerDeviceKind.mouse) {
      _onMouse(event);
      if (event.buttons & kPrimaryMouseButton != 0) _mouse.mouseFire = true;
    } else {
      // Tap (or drag) in the arena to aim on a phone; double tap to shoot.
      _aimAt(event, marker: true);
      final last = _lastTap;
      if (last != null &&
          event.timeStamp - last.time <= kDoubleTapTimeout &&
          (event.position - last.position).distance <= _doubleTapSlop) {
        if (_online case final online?) {
          online.queueShot();
        } else {
          _mouse.fireAtAim = true;
        }
        // Start over, so each shot takes its own pair of taps.
        _lastTap = null;
      } else {
        _lastTap = (time: event.timeStamp, position: event.position);
      }
    }
  }

  /// How far apart, in screen points, two taps can be and still count as a
  /// double tap.
  static const double _doubleTapSlop = 40;

  ({Duration time, Offset position})? _lastTap;

  void _onArenaPointerMove(PointerMoveEvent event) {
    // Mouse moves are already handled by the screen-wide listener.
    if (_sharedScreen || event.kind == PointerDeviceKind.mouse) return;
    _aimAt(event, marker: true);
  }

  void _onArenaPointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) _mouse.mouseFire = false;
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    // Clamp so a dropped frame or a backgrounded tab can't teleport anything.
    final step = dt.clamp(0.0, 0.05);
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    _keys.forEach((tank, keys) => keys.apply(tank.controls, pressed));
    // Arrow keys follow the screen, which the guest sees upside down.
    if (_viewFlipped) _me.controls.keyMove = -_me.controls.keyMove;

    final online = _online;
    if (online != null) {
      online.tick(step);
    } else {
      _ai?.update(step);
      game.update(step);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    final online = _online;
    if (online != null) {
      online.dispose();
    } else {
      game.dispose();
    }
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
            child: Focus(
              autofocus: true,
              onKeyEvent: _onKey,
              child: Listener(
                onPointerHover: _onMouse,
                onPointerMove: _onMouse,
                child: _buildGame(),
              ),
            ),
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
            if (_sharedScreen)
              // Blue sits across from Red, so their controls face them.
              RotatedBox(
                quarterTurns: 2,
                child: ControlPanel(game: game, tank: game.blue),
              )
            else
              _OpponentBar(
                game: game,
                tank: _opponent,
                label: _ai != null ? 'CPU' : teamName(_opponent.team),
                detail:
                    widget.difficulty?.label ??
                    (_online!.link.relayed ? 'Online · relay' : 'Online'),
                onExit: _toMenu,
              ),
            Expanded(
              // Clicking anywhere in the arena area fires; clicks on the
              // on-screen buttons below still work as buttons.
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onArenaPointerDown,
                onPointerMove: _onArenaPointerMove,
                onPointerUp: _onArenaPointerUp,
                onPointerCancel: _onArenaPointerUp,
                child: MouseRegion(
                  cursor: _sharedScreen
                      ? MouseCursor.defer
                      : SystemMouseCursors.precise,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio:
                            TankGame.world.width / TankGame.world.height,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24, width: 2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: RotatedBox(
                              quarterTurns: _viewFlipped ? 2 : 0,
                              child: CustomPaint(
                                key: _arenaKey,
                                painter: ArenaPainter(game, me: _me),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ControlPanel(
              game: game,
              tank: _me,
              label: _sharedScreen ? null : 'YOU',
            ),
          ],
        ),
        ListenableBuilder(
          listenable: game,
          builder: (context, _) => game.showResult
              ? ResultOverlay(
                  game: game,
                  viewer: _sharedScreen ? null : _me.team,
                  opponentLabel: _ai != null ? 'CPU' : teamName(_opponent.team),
                  winSubtitle: switch (widget.difficulty) {
                    final d? => 'You beat the ${d.label} CPU',
                    null => 'You won the online battle',
                  },
                  onRematch: _rematch,
                  onMenu: _toMenu,
                )
              : const SizedBox.shrink(),
        ),
        if (_online case final online?)
          ValueListenableBuilder(
            valueListenable: online.lost,
            builder: (context, lost, _) => lost
                ? _ConnectionLost(onMenu: _toMenu)
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

/// Shown over the game when the other device leaves or the connection drops.
class _ConnectionLost extends StatelessWidget {
  const _ConnectionLost({required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.white70),
              const SizedBox(height: 12),
              const Text(
                'Connection lost',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text(
                'The other player left, or the connection dropped.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onMenu,
                icon: const Icon(Icons.home),
                label: const Text('Menu'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top strip when one person uses this device: the opponent's health and a
/// way back to the menu.
class _OpponentBar extends StatelessWidget {
  const _OpponentBar({
    required this.game,
    required this.tank,
    required this.label,
    required this.detail,
    required this.onExit,
  });

  final TankGame game;
  final Tank tank;
  final String label;

  /// Small text on the right, such as the difficulty.
  final String detail;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            teamColor(tank.team).withValues(alpha: 0.28),
            teamColor(tank.team).withValues(alpha: 0.08),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onExit,
            tooltip: 'Menu',
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: HealthBar(game: game, tank: tank, label: label),
          ),
          const SizedBox(width: 8),
          Text(
            detail,
            style: const TextStyle(fontSize: 13, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

/// One player's controls: health bar, movement stick, turret rotation, fire.
class ControlPanel extends StatelessWidget {
  const ControlPanel({
    super.key,
    required this.game,
    required this.tank,
    this.label,
  });

  final TankGame game;
  final Tank tank;

  /// Shown next to the health bar instead of the team name.
  final String? label;

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
          HealthBar(game: game, tank: tank, label: label),
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
  const HealthBar({
    super.key,
    required this.game,
    required this.tank,
    this.label,
  });

  final TankGame game;
  final Tank tank;
  final String? label;

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
                label ?? teamName(tank.team),
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
  ArenaPainter(this.game, {required this.me}) : super(repaint: game);

  final TankGame game;

  /// The tank this device controls, whose tap target is shown.
  final Tank me;

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

    final aim = me.controls;
    final aimAt = aim.aimAt;
    if (aim.showAimMarker && aimAt != null && me.alive) {
      _paintAimMarker(canvas, aimAt, shotQueued: aim.fireAtAim);
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

  /// A small target where the player tapped, so they can see what the gun is
  /// turning toward.
  void _paintAimMarker(Canvas canvas, Offset at, {required bool shotQueued}) {
    final paint = Paint()
      ..color = redColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(at, 7, paint);
    for (final d in const [
      Offset(1, 0),
      Offset(-1, 0),
      Offset(0, 1),
      Offset(0, -1),
    ]) {
      canvas.drawLine(at + d * 4, at + d * 10, paint);
    }
    if (shotQueued) {
      canvas.drawCircle(at, 3.5, Paint()..color = redColor);
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

/// Winner screen. When two people share the device it is split so each
/// player reads their half the right way up.
class ResultOverlay extends StatelessWidget {
  const ResultOverlay({
    super.key,
    required this.game,
    required this.viewer,
    required this.opponentLabel,
    required this.winSubtitle,
    required this.onRematch,
    required this.onMenu,
  });

  final TankGame game;

  /// The team of the one person using this device; null when two share it.
  final Team? viewer;

  /// Who "they" are, such as CPU.
  final String opponentLabel;
  final String winSubtitle;
  final VoidCallback onRematch;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final winner = game.winner;
    final viewer = this.viewer;
    final buttons = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: onRematch,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            icon: const Icon(Icons.replay),
            label: const Text('Rematch'),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onMenu,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: const Icon(Icons.home),
            label: const Text('Menu'),
          ),
        ],
      ),
    );

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: viewer != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ResultText(
                    title: winner == null
                        ? 'DRAW'
                        : winner == viewer
                        ? 'YOU WIN!'
                        : '$opponentLabel WINS',
                    subtitle: winner == null
                        ? 'Both tanks destroyed'
                        : winner == viewer
                        ? winSubtitle
                        : 'Try again?',
                    color: winner == null ? Colors.white : teamColor(winner),
                  ),
                  const SizedBox(height: 20),
                  buttons,
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 2,
                    child: _ResultHalf(winner: winner, viewer: Team.blue),
                  ),
                ),
                buttons,
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
      child: _ResultText(title: title, subtitle: subtitle, color: color),
    );
  }
}

class _ResultText extends StatelessWidget {
  const _ResultText({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, color: Colors.white70),
        ),
      ],
    );
  }
}
