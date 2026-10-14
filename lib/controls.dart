import 'package:flutter/material.dart';

/// A virtual thumbstick. Reports a vector of length 0–1 in its own local frame
/// while touched, and [Offset.zero] on release.
///
/// Uses a raw [Listener] instead of gesture detectors so it never waits on the
/// gesture arena and works alongside other fingers on other controls.
class Joystick extends StatefulWidget {
  const Joystick({
    super.key,
    required this.size,
    required this.color,
    required this.onChanged,
  });

  final double size;
  final Color color;
  final ValueChanged<Offset> onChanged;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  int? _pointer;
  Offset _knob = Offset.zero;

  double get _radius => widget.size / 2;

  void _update(Offset local) {
    final center = Offset(_radius, _radius);
    var delta = local - center;
    final max = _radius * 0.7;
    if (delta.distance > max) delta = delta / delta.distance * max;
    setState(() => _knob = delta);
    widget.onChanged(delta / max);
  }

  void _release() {
    _pointer = null;
    setState(() => _knob = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return;
        _pointer = e.pointer;
        _update(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) _update(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _release();
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _release();
      },
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _JoystickPainter(
          knob: _knob,
          color: widget.color,
          active: _pointer != null,
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knob,
    required this.color,
    required this.active,
  });

  final Offset knob;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      center,
      r - 1,
      Paint()..color = color.withValues(alpha: active ? 0.22 : 0.14),
    );
    canvas.drawCircle(
      center,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.6),
    );
    // Direction ticks.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final d in const [
      Offset(0, -1),
      Offset(0, 1),
      Offset(-1, 0),
      Offset(1, 0),
    ]) {
      canvas.drawLine(center + d * (r * 0.78), center + d * (r * 0.88), tick);
    }
    canvas.drawCircle(
      center + knob,
      r * 0.38,
      Paint()..color = active ? color : color.withValues(alpha: 0.85),
    );
    canvas.drawCircle(
      center + knob,
      r * 0.38,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.knob != knob || old.color != color || old.active != active;
}

/// A button that reports `true` while any finger is on it.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.size,
    required this.color,
    required this.onChanged,
    this.icon,
    this.label,
  });

  final double size;
  final Color color;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? label;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  final Set<int> _pointers = {};

  bool get _pressed => _pointers.isNotEmpty;

  void _down(PointerEvent e) {
    final was = _pressed;
    setState(() => _pointers.add(e.pointer));
    if (!was) widget.onChanged(true);
  }

  void _up(PointerEvent e) {
    if (!_pointers.contains(e.pointer)) return;
    setState(() => _pointers.remove(e.pointer));
    if (!_pressed) widget.onChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = _pressed;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedScale(
        scale: pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 60),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pressed
                ? widget.color
                : widget.color.withValues(alpha: 0.75),
            border: Border.all(
              color: Colors.white.withValues(alpha: pressed ? 0.9 : 0.4),
              width: 2,
            ),
            boxShadow: pressed
                ? null
                : const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: widget.label != null
              ? Text(
                  widget.label!,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    fontSize: widget.size * 0.22,
                  ),
                )
              : Icon(widget.icon, color: Colors.white, size: widget.size * 0.5),
        ),
      ),
    );
  }
}
