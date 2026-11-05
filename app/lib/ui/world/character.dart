import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/common.dart' show avatars;

enum CharacterPose { idle, walking, sitting }

/// Cosmetic shirt colours for the student's character (device-local preference,
/// kept separate from the academic profile).
const characterColors = <Color>[
  Color(0xFF5B6CFF),
  Color(0xFF3CC9A0),
  Color(0xFFFF8A65),
  Color(0xFFB079F2),
  Color(0xFFF5A524),
  Color(0xFF2BA8D8),
  Color(0xFFE5679A),
  Color(0xFF6B7280),
];

/// The student's character: a small drawn body with the chosen avatar as the
/// head. Animates while idle/walking unless [reduceMotion] is set.
class CampusCharacter extends StatefulWidget {
  final String avatar;
  final Color color;
  final CharacterPose pose;
  final double size; // overall height
  final bool reduceMotion;
  final bool focusing; // shows a small focus glow while a session runs
  const CampusCharacter({
    super.key,
    required this.avatar,
    required this.color,
    this.pose = CharacterPose.idle,
    this.size = 56,
    this.reduceMotion = false,
    this.focusing = false,
  });

  @override
  State<CampusCharacter> createState() => _CampusCharacterState();
}

class _CampusCharacterState extends State<CampusCharacter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CampusCharacter old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = !widget.reduceMotion && widget.pose != CharacterPose.sitting;
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      label: 'Your character, ${widget.pose == CharacterPose.sitting ? 'sitting' : widget.pose.name}',
      child: SizedBox(
        width: s * 0.8,
        height: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value;
            final bob = widget.pose == CharacterPose.walking
                ? -(math.sin(t * 2 * math.pi * 2).abs() * s * 0.05)
                : (widget.pose == CharacterPose.idle ? math.sin(t * 2 * math.pi) * s * 0.015 : 0.0);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (widget.focusing)
                  Positioned(
                    top: 0,
                    child: Container(
                      width: s * 0.8,
                      height: s * 0.8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFFFFE08A).withValues(alpha: 0.7), blurRadius: s * 0.35)],
                      ),
                    ),
                  ),
                Positioned.fill(
                  top: s * 0.36 + bob,
                  child: CustomPaint(painter: _BodyPainter(widget.color, widget.pose, t)),
                ),
                Positioned(
                  top: bob,
                  child: Container(
                    width: s * 0.48,
                    height: s * 0.48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color, width: s * 0.035),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    child: Text(avatars[widget.avatar] ?? '🦊', style: TextStyle(fontSize: s * 0.27)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BodyPainter extends CustomPainter {
  final Color color;
  final CharacterPose pose;
  final double t;
  _BodyPainter(this.color, this.pose, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final skin = Paint()..color = const Color(0xFFF2C5A0);
    final pants = Paint()
      ..color = const Color(0xFF34364F)
      ..strokeWidth = w * 0.13
      ..strokeCap = StrokeCap.round;
    final arm = Paint()
      ..color = color
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round;
    // Shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h * 0.97), width: w * 0.7, height: h * 0.1),
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );
    final swing = pose == CharacterPose.walking ? math.sin(t * 2 * math.pi * 2) * w * 0.12 : 0.0;
    if (pose == CharacterPose.sitting) {
      // Thighs forward, shins down.
      canvas.drawLine(Offset(cx - w * 0.1, h * 0.55), Offset(cx + w * 0.12, h * 0.6), pants);
      canvas.drawLine(Offset(cx + w * 0.12, h * 0.6), Offset(cx + w * 0.14, h * 0.9), pants);
    } else {
      canvas.drawLine(Offset(cx - w * 0.08, h * 0.55), Offset(cx - w * 0.1 + swing, h * 0.92), pants);
      canvas.drawLine(Offset(cx + w * 0.08, h * 0.55), Offset(cx + w * 0.1 - swing, h * 0.92), pants);
    }
    // Torso.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx - w * 0.2, h * 0.02, w * 0.4, h * 0.56), Radius.circular(w * 0.14)),
      Paint()..color = color,
    );
    // Arms (forward on the desk when sitting).
    if (pose == CharacterPose.sitting) {
      canvas.drawLine(Offset(cx - w * 0.2, h * 0.14), Offset(cx + w * 0.05, h * 0.36), arm);
      canvas.drawLine(Offset(cx + w * 0.2, h * 0.14), Offset(cx + w * 0.3, h * 0.36), arm);
    } else {
      canvas.drawLine(Offset(cx - w * 0.22, h * 0.12), Offset(cx - w * 0.28 - swing * 0.5, h * 0.45), arm);
      canvas.drawLine(Offset(cx + w * 0.22, h * 0.12), Offset(cx + w * 0.28 + swing * 0.5, h * 0.45), arm);
      canvas.drawCircle(Offset(cx - w * 0.28 - swing * 0.5, h * 0.47), w * 0.06, skin);
      canvas.drawCircle(Offset(cx + w * 0.28 + swing * 0.5, h * 0.47), w * 0.06, skin);
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.t != t || old.pose != pose || old.color != color;
}
