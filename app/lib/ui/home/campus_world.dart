import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../world/character.dart';

/// A destination on the campus island, bound to an existing app screen.
class CampusDestination {
  final String id; // classrooms | timetable | exams | notices | calendar
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onOpen;
  final String? badge;
  const CampusDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.onOpen,
    this.badge,
  });
}

/// Isometric projection for a 10 x 10 grid island that scales with the widget.
class _Iso {
  final Size size;
  late final double tw = size.width * 0.092; // tile width
  late final double th = tw * 0.5; // tile height
  late final double cx = size.width / 2;
  late final double y0 = size.height * 0.36; // top corner of the island

  _Iso(this.size);

  Offset p(double x, double y, [double z = 0]) => Offset(cx + (x - y) * tw / 2, y0 + (x + y) * th / 2 - z * tw);
}

/// Footprint and height of a building, in grid units (height in tile widths).
class _Bldg {
  final String id;
  final double x0, y0, x1, y1, h, roof;
  const _Bldg(this.id, this.x0, this.y0, this.x1, this.y1, this.h, this.roof);

  double get depth => x1 + y1;

  Rect bounds(_Iso iso) {
    final pts = [
      for (final x in [x0, x1])
        for (final y in [y0, y1])
          for (final z in [0.0, h + roof]) iso.p(x, y, z),
    ];
    var r = Rect.fromPoints(pts.first, pts.first);
    for (final q in pts) {
      r = r.expandToInclude(Rect.fromPoints(q, q));
    }
    return r.inflate(4);
  }

  /// Front door: middle of the left (south-west) facade at ground level.
  Offset door(_Iso iso) => iso.p((x0 + x1) / 2, y1 + 0.35);

  /// Signpost anchor; the Exam Hall's sits over its front roof so it does not hide the clock tower.
  Offset top(_Iso iso) => id == 'exams' ? iso.p(x0 + 0.7, y1, h + roof * 0.5) : iso.p((x0 + x1) / 2, (y0 + y1) / 2, h + roof);
}

// Layout is an original illustration, not a survey of the real campus. The
// Academic Block shows ten storeys as a nod to LG, G and floors 1–8.
const _buildings = [
  _Bldg('classrooms', 3.0, 0.6, 5.8, 3.0, 2.55, 0.25),
  _Bldg('calendar', 7.0, 0.9, 9.0, 2.9, 0.55, 0.9),
  _Bldg('timetable', 0.9, 3.6, 2.0, 4.7, 2.0, 0.75),
  _Bldg('notices', 7.3, 5.6, 8.4, 6.5, 0.75, 0.15),
  _Bldg('exams', 1.6, 6.3, 4.0, 8.5, 1.05, 0.55),
];

const _trees = [
  (0.6, 1.2, 1.0),
  (1.7, 0.5, 0.8),
  (2.2, 2.3, 0.9),
  (6.4, 0.4, 0.8),
  (9.4, 3.9, 0.9),
  (6.3, 3.6, 0.7),
  (0.5, 6.0, 0.9),
  (0.7, 9.2, 0.8),
  (4.8, 8.9, 0.9),
  (9.3, 7.3, 1.0),
  (8.8, 9.2, 0.8),
  (5.6, 7.6, 0.7),
];
const _benches = [(4.3, 4.3), (6.6, 6.6), (6.7, 4.4)];
const _lamps = [(4.0, 5.4), (5.4, 4.0), (7.0, 7.0), (3.6, 3.6), (8.6, 4.8)];

// Walkways as polylines (grid coordinates) used for strolling students.
const _paths = [
  [(9.8, 9.8), (7.4, 7.4), (5.5, 5.5)],
  [(5.5, 5.5), (4.4, 3.4), (4.4, 3.0)],
  [(5.5, 5.5), (2.8, 5.6), (1.5, 4.9)],
  [(5.5, 5.5), (4.6, 7.4), (2.8, 8.5)],
  [(5.5, 5.5), (7.6, 4.8), (7.9, 5.6)],
  [(5.5, 5.5), (7.4, 3.6), (8.0, 2.9)],
];

class CampusWorld extends StatefulWidget {
  final List<CampusDestination> destinations;
  final bool reduceMotion;
  final bool night;
  final String? avatar;
  final Color characterColor;
  final bool focusing;
  const CampusWorld({
    super.key,
    this.destinations = const [],
    this.reduceMotion = false,
    this.night = false,
    this.avatar,
    this.characterColor = const Color(0xFF5B6CFF),
    this.focusing = false,
  });

  @override
  State<CampusWorld> createState() => _CampusWorldState();
}

class _CampusWorldState extends State<CampusWorld> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60));
  late final AnimationController _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  String? _active;
  bool _walking = false;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _clock.repeat();
  }

  @override
  void didUpdateWidget(CampusWorld old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion && _clock.isAnimating) _clock.stop();
    if (!widget.reduceMotion && !_clock.isAnimating) _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    _press.dispose();
    super.dispose();
  }

  Future<void> _visit(CampusDestination d) async {
    if (_walking) return;
    setState(() {
      _active = d.id;
      _walking = true;
    });
    _press.forward(from: 0);
    // Let the avatar reach the door before navigating; skipped with reduce motion.
    await Future<void>.delayed(Duration(milliseconds: widget.reduceMotion ? 120 : 620));
    if (!mounted) return;
    d.onOpen();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _press.reverse();
    setState(() {
      _active = null;
      _walking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final iso = _Iso(size);
        final byId = {for (final d in widget.destinations) d.id: d};
        final activeBuilding = _active == 'library' ? 'classrooms' : _active;
        final active = _buildings.where((b) => b.id == activeBuilding).firstOrNull;
        final academic = _buildings.firstWhere((b) => b.id == 'classrooms');
        // Floor 7 is the 9th of 10 storeys (LG, G, 1–8) on the right-hand facade.
        final librarySign = iso.p(academic.x1, (academic.y0 + academic.y1) / 2, 0.12 + academic.h * 0.85) + const Offset(48, 0);
        final home = iso.p(4.5, 6.7); // on the path left of the plaza, clear of signposts
        final target = active?.door(iso) ?? home;
        const avatarSize = 46.0;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: CustomPaint(painter: _SkyPainter(widget.night))),
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: _AmbientPainter(_clock, iso, widget.night, back: true))),
            ),
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _press,
                  builder: (_, _) => CustomPaint(painter: _WorldPainter(iso, widget.night, activeBuilding, _press.value)),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: CustomPaint(painter: _AmbientPainter(_clock, iso, widget.night, back: false))),
              ),
            ),
            // Tap targets over each building.
            for (final b in _buildings)
              if (byId[b.id] != null)
                Positioned.fromRect(
                  rect: b.bounds(iso),
                  child: Semantics(
                    button: true,
                    label: 'Open ${byId[b.id]!.label}',
                    child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _visit(byId[b.id]!)),
                  ),
                ),
            // Avatar walks to the chosen building.
            if (widget.avatar != null)
              AnimatedPositioned(
                duration: Duration(milliseconds: widget.reduceMotion ? 1 : 560),
                curve: Curves.easeInOutCubic,
                left: target.dx - avatarSize * 0.4,
                top: target.dy - avatarSize,
                child: IgnorePointer(
                  child: CampusCharacter(
                    avatar: widget.avatar!,
                    color: widget.characterColor,
                    pose: _walking ? CharacterPose.walking : CharacterPose.idle,
                    size: avatarSize,
                    reduceMotion: widget.reduceMotion,
                    focusing: widget.focusing,
                  ),
                ),
              ),
            // Signposts above buildings.
            for (final b in _buildings)
              if (byId[b.id] != null)
                _Signpost(dest: byId[b.id]!, anchor: b.top(iso), active: _active == b.id, onTap: () => _visit(byId[b.id]!)),
            if (byId['library'] != null)
              _Signpost(dest: byId['library']!, anchor: librarySign, active: _active == 'library', onTap: () => _visit(byId['library']!)),
          ],
        );
      },
    );
  }
}

class _Signpost extends StatelessWidget {
  final CampusDestination dest;
  final Offset anchor;
  final bool active;
  final VoidCallback onTap;
  const _Signpost({required this.dest, required this.anchor, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const w = 132.0;
    return Positioned(
      left: anchor.dx - w / 2,
      top: math.max(4, anchor.dy - 40),
      width: w,
      child: Center(
        child: AnimatedScale(
          scale: active ? 1.12 : 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: GestureDetector(
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                  decoration: BoxDecoration(
                    color: active ? dest.color : Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: dest.color.withValues(alpha: 0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: dest.color.withValues(alpha: 0.35), blurRadius: active ? 14 : 6, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: active ? Colors.white : dest.color, shape: BoxShape.circle),
                        child: Icon(dest.icon, size: 12, color: active ? dest.color : Colors.white),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          dest.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: active ? Colors.white : const Color(0xFF2A2A40),
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (dest.badge != null)
                  Positioned(
                    right: -6,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: CsColors.coral,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        dest.badge!,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- painters --
class _Palette {
  final bool night;
  const _Palette(this.night);
  Color get grassA => night ? const Color(0xFF3E7D67) : const Color(0xFF9EE2A9);
  Color get grassB => night ? const Color(0xFF39735F) : const Color(0xFF93D99F);
  Color get soilL => night ? const Color(0xFF6E4E3D) : const Color(0xFFD39367);
  Color get soilR => night ? const Color(0xFF5A3F31) : const Color(0xFFB87A4F);
  Color get path => night ? const Color(0xFFA9A3C2) : const Color(0xFFF7E7C6);
  Color get pathEdge => night ? const Color(0xFF8F89AC) : const Color(0xFFE8D2A8);
  Color get window => night ? const Color(0xFFFFE08A) : const Color(0xFFE3EEFF);
  Color get windowDark => night ? const Color(0xFF4D4F86) : const Color(0xFFBFD3F5);
  Color shade(Color c, double f) => Color.lerp(c, night ? const Color(0xFF1B1C3D) : Colors.black, f)!;
}

class _SkyPainter extends CustomPainter {
  final bool night;
  _SkyPainter(this.night);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: night
              ? const [Color(0xFF1F2156), Color(0xFF3D3F8F), Color(0xFF6A5FA8)]
              : const [Color(0xFF9CC2FF), Color(0xFFCFE0FF), Color(0xFFFFF1E2)],
        ).createShader(rect),
    );
    final sun = Offset(s.width * 0.84, s.height * 0.2);
    final p = Paint();
    if (night) {
      p.color = Colors.white;
      final rnd = math.Random(7);
      for (var i = 0; i < 40; i++) {
        canvas.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * 0.45), rnd.nextDouble() * 1.2 + 0.3, p);
      }
      canvas.drawCircle(sun, 18, Paint()..color = const Color(0xFFF7F3D6));
      canvas.drawCircle(sun + const Offset(7, -4), 15, Paint()..color = const Color(0xFF2E3070));
    } else {
      for (final (r, a) in [(64.0, 0.10), (44.0, 0.18), (30.0, 1.0)]) {
        p.color = CsColors.sun.withValues(alpha: a);
        canvas.drawCircle(sun, r, p);
      }
    }
    // Distant skyline silhouette for a city-campus feel (decorative).
    final base = s.height * 0.42;
    final sky = Path()..moveTo(0, base);
    final rnd = math.Random(3);
    var x = 0.0;
    while (x < s.width) {
      final w = 14 + rnd.nextDouble() * 22;
      final h = 10 + rnd.nextDouble() * 34;
      sky
        ..lineTo(x, base - h)
        ..lineTo(x + w, base - h);
      x += w;
    }
    sky
      ..lineTo(s.width, base)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(sky, Paint()..color = night ? const Color(0xFF34366F) : const Color(0xFFBCD0F2).withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.night != night;
}

class _WorldPainter extends CustomPainter {
  final _Iso iso;
  final bool night;
  final String? active;
  final double press;
  final _Palette pal;
  _WorldPainter(this.iso, this.night, this.active, this.press) : pal = _Palette(night);

  Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  void _fill(Canvas c, List<Offset> pts, Color color) => c.drawPath(_poly(pts), Paint()..color = color);

  @override
  void paint(Canvas canvas, Size size) {
    _island(canvas);
    _walkways(canvas);
    final items = <(double, void Function())>[
      for (final b in _buildings) (b.depth, () => _building(canvas, b)),
      for (final t in _trees) (t.$1 + t.$2 + 0.3, () => _tree(canvas, t.$1, t.$2, t.$3)),
      for (final b in _benches) (b.$1 + b.$2, () => _bench(canvas, b.$1, b.$2)),
      for (final l in _lamps) (l.$1 + l.$2, () => _lamp(canvas, l.$1, l.$2)),
      (11.0, () => _fountainBase(canvas)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final i in items) {
      i.$2();
    }
  }

  void _island(Canvas c) {
    final t = iso.tw * 0.55; // island thickness
    final l = iso.p(0, 10), r = iso.p(10, 0), b = iso.p(10, 10), top = iso.p(0, 0);
    // Soft shadow below the island.
    c.drawOval(
      Rect.fromCenter(center: b + Offset(0, t + 6), width: (r.dx - l.dx) * 0.9, height: iso.th * 2.2),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    _fill(c, [l, b, b + Offset(0, t), l + Offset(0, t)], pal.soilL);
    _fill(c, [b, r, r + Offset(0, t), b + Offset(0, t)], pal.soilR);
    // Grass lip.
    _fill(c, [l, b, b + Offset(0, t * 0.25), l + Offset(0, t * 0.25)], pal.shade(pal.grassA, 0.15));
    _fill(c, [b, r, r + Offset(0, t * 0.25), b + Offset(0, t * 0.25)], pal.shade(pal.grassA, 0.25));
    _fill(c, [top, r, b, l], pal.grassA);
    // Checkered turf tiles.
    for (var i = 0; i < 10; i++) {
      for (var j = 0; j < 10; j++) {
        if ((i + j).isOdd) {
          _fill(c, [iso.p(i + 0.0, j + 0.0), iso.p(i + 1.0, j + 0.0), iso.p(i + 1.0, j + 1.0), iso.p(i + 0.0, j + 1.0)], pal.grassB);
        }
      }
    }
    // Hedge along the back edges.
    final hedge = Paint()..color = pal.shade(const Color(0xFF5CBF85), night ? 0.3 : 0);
    for (var i = 0.3; i < 10; i += 0.55) {
      for (final o in [iso.p(i, 0.15), iso.p(0.15, i)]) {
        c.drawCircle(o - Offset(0, iso.tw * 0.12), iso.tw * 0.16, hedge);
      }
    }
  }

  void _walkways(Canvas c) {
    final w = iso.tw * 0.22;
    for (final path in _paths) {
      final pts = [for (final (x, y) in path) iso.p(x, y)];
      final edge = Paint()
        ..color = pal.pathEdge
        ..strokeWidth = w * 2 + 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final fill = Paint()
        ..color = pal.path
        ..strokeWidth = w * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final p = Path()..addPolygon(pts, false);
      c.drawPath(p, edge);
      c.drawPath(p, fill);
    }
    // Plaza: a paved diamond around the fountain.
    const cx = 5.5, cy = 5.5, rr = 1.25;
    _fill(c, [iso.p(cx - rr, cy - rr), iso.p(cx + rr, cy - rr), iso.p(cx + rr, cy + rr), iso.p(cx - rr, cy + rr)], pal.pathEdge);
    const r2 = 1.1;
    _fill(c, [iso.p(cx - r2, cy - r2), iso.p(cx + r2, cy - r2), iso.p(cx + r2, cy + r2), iso.p(cx - r2, cy + r2)], pal.path);
    final grid = Paint()
      ..color = pal.pathEdge
      ..strokeWidth = 0.8;
    for (var k = -0.55; k <= 0.56; k += 0.55) {
      c.drawLine(iso.p(cx - r2, cy + k), iso.p(cx + r2, cy + k), grid);
      c.drawLine(iso.p(cx + k, cy - r2), iso.p(cx + k, cy + r2), grid);
    }
  }

  /// Draws an axis-aligned box; returns nothing. Faces: top, left (y=y1), right (x=x1).
  void _box(Canvas c, double x0, double y0, double x1, double y1, double z0, double h, Color left, Color right, Color top) {
    _fill(c, [iso.p(x0, y1, z0), iso.p(x1, y1, z0), iso.p(x1, y1, z0 + h), iso.p(x0, y1, z0 + h)], left);
    _fill(c, [iso.p(x1, y0, z0), iso.p(x1, y1, z0), iso.p(x1, y1, z0 + h), iso.p(x1, y0, z0 + h)], right);
    _fill(c, [iso.p(x0, y0, z0 + h), iso.p(x1, y0, z0 + h), iso.p(x1, y1, z0 + h), iso.p(x0, y1, z0 + h)], top);
  }

  /// Windows on the left (y = y1) and right (x = x1) facades.
  void _windows(Canvas c, _Bldg b, double z0, int rows, int colsL, int colsR, {double inset = 0.12}) {
    final h = b.h;
    final rowH = (h - 0.25) / rows;
    for (var r = 0; r < rows; r++) {
      final za = z0 + 0.12 + r * rowH + rowH * 0.22;
      final zb = za + rowH * 0.55;
      for (var i = 0; i < colsL; i++) {
        final u0 = b.x0 + inset + (b.x1 - b.x0 - inset * 2) * (i + 0.18) / colsL;
        final u1 = b.x0 + inset + (b.x1 - b.x0 - inset * 2) * (i + 0.82) / colsL;
        final lit = night ? (r * 3 + i * 5) % 7 != 0 : (r + i) % 4 == 0;
        _fill(c, [iso.p(u0, b.y1, za), iso.p(u1, b.y1, za), iso.p(u1, b.y1, zb), iso.p(u0, b.y1, zb)], lit ? pal.window : pal.windowDark);
      }
      for (var i = 0; i < colsR; i++) {
        final v0 = b.y0 + inset + (b.y1 - b.y0 - inset * 2) * (i + 0.18) / colsR;
        final v1 = b.y0 + inset + (b.y1 - b.y0 - inset * 2) * (i + 0.82) / colsR;
        final lit = night ? (r * 5 + i * 3) % 6 != 0 : (r + i) % 5 == 1;
        _fill(c, [
          iso.p(b.x1, v0, za),
          iso.p(b.x1, v1, za),
          iso.p(b.x1, v1, zb),
          iso.p(b.x1, v0, zb),
        ], lit ? pal.window : pal.shade(pal.windowDark, 0.12));
      }
    }
  }

  void _shadow(Canvas c, _Bldg b) {
    final o = iso.tw * 0.35;
    c.drawPath(
      _poly(
        [iso.p(b.x0, b.y1), iso.p(b.x1, b.y1), iso.p(b.x1, b.y0)].map((p) => p + Offset(-o * 0.3, o * 0.25)).toList()
          ..addAll([iso.p(b.x1 + 0.4, b.y0 + 0.2), iso.p(b.x1 + 0.4, b.y1 + 0.4), iso.p(b.x0 + 0.2, b.y1 + 0.4)]),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _building(Canvas c, _Bldg b) {
    final isActive = active == b.id;
    final lift = isActive ? press * iso.tw * 0.18 : 0.0;
    _shadow(c, b);
    c.save();
    c.translate(0, -lift);
    switch (b.id) {
      case 'classrooms':
        _academicBlock(c, b);
      case 'timetable':
        _clockTower(c, b);
      case 'exams':
        _examHall(c, b);
      case 'notices':
        _kiosk(c, b);
      case 'calendar':
        _pavilion(c, b);
    }
    c.restore();
    if (isActive) {
      final r = b.bounds(iso).shift(Offset(0, -lift));
      c.drawRRect(
        RRect.fromRectAndRadius(r.deflate(2), const Radius.circular(12)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55 * press)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _academicBlock(Canvas c, _Bldg b) {
    const wall = Color(0xFFF4A47E);
    // Plinth / entrance podium.
    _box(
      c,
      b.x0 - 0.15,
      b.y0 - 0.15,
      b.x1 + 0.15,
      b.y1 + 0.15,
      0,
      0.12,
      pal.shade(const Color(0xFFE9D8C4), 0.05),
      pal.shade(const Color(0xFFE9D8C4), 0.18),
      const Color(0xFFF3E6D6),
    );
    _box(c, b.x0, b.y0, b.x1, b.y1, 0.12, b.h, pal.shade(wall, 0.0), pal.shade(wall, 0.18), pal.shade(wall, -0.1));
    _windows(c, b, 0.12, 10, 6, 5);
    // Vertical accent fins.
    for (final u in [0.33, 0.66]) {
      final x = b.x0 + (b.x1 - b.x0) * u;
      _fill(c, [
        iso.p(x - 0.05, b.y1 + 0.01, 0.12),
        iso.p(x + 0.05, b.y1 + 0.01, 0.12),
        iso.p(x + 0.05, b.y1 + 0.01, b.h + 0.12),
        iso.p(x - 0.05, b.y1 + 0.01, b.h + 0.12),
      ], pal.shade(wall, -0.25));
    }
    // Roof parapet and rooftop unit.
    final rz = b.h + 0.12;
    _box(
      c,
      b.x0,
      b.y0,
      b.x1,
      b.y1,
      rz,
      0.1,
      pal.shade(const Color(0xFF7C6FD6), 0),
      pal.shade(const Color(0xFF7C6FD6), 0.2),
      pal.shade(const Color(0xFFD9D4F7), 0),
    );
    _box(
      c,
      b.x0 + 0.6,
      b.y0 + 0.5,
      b.x0 + 1.3,
      b.y0 + 1.1,
      rz + 0.1,
      0.28,
      const Color(0xFFCFC8EE),
      const Color(0xFFB4ABE0),
      const Color(0xFFE6E1FA),
    );
    // Entrance canopy and door.
    final mx = (b.x0 + b.x1) / 2;
    _box(c, mx - 0.45, b.y1, mx + 0.45, b.y1 + 0.35, 0.62, 0.07, const Color(0xFF6B5CC9), const Color(0xFF5649AD), const Color(0xFF8E80E8));
    _fill(c, [
      iso.p(mx - 0.25, b.y1 + 0.005, 0.12),
      iso.p(mx + 0.25, b.y1 + 0.005, 0.12),
      iso.p(mx + 0.25, b.y1 + 0.005, 0.6),
      iso.p(mx - 0.25, b.y1 + 0.005, 0.6),
    ], const Color(0xFF4A3F8C));
  }

  void _clockTower(Canvas c, _Bldg b) {
    const wall = Color(0xFFB8A1FF);
    _box(c, b.x0, b.y0, b.x1, b.y1, 0, b.h, wall, pal.shade(wall, 0.2), pal.shade(wall, -0.1));
    _windows(c, b, 0, 4, 1, 1, inset: 0.25);
    // Belfry band.
    _box(
      c,
      b.x0 - 0.08,
      b.y0 - 0.08,
      b.x1 + 0.08,
      b.y1 + 0.08,
      b.h - 0.55,
      0.12,
      const Color(0xFF8E73F0),
      const Color(0xFF765BD9),
      const Color(0xFFA58FF7),
    );
    // Spire (pyramid).
    final apex = iso.p((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, b.h + b.roof);
    _fill(c, [iso.p(b.x0 - 0.08, b.y1 + 0.08, b.h), iso.p(b.x1 + 0.08, b.y1 + 0.08, b.h), apex], const Color(0xFF7B61E0));
    _fill(c, [iso.p(b.x1 + 0.08, b.y0 - 0.08, b.h), iso.p(b.x1 + 0.08, b.y1 + 0.08, b.h), apex], const Color(0xFF634AC4));
    // Clock face on the front facade.
    final face = iso.p((b.x0 + b.x1) / 2, b.y1 + 0.01, b.h - 0.95);
    final rw = iso.tw * 0.34;
    c.save();
    c.translate(face.dx, face.dy);
    c.transform(Matrix4.skewY(-0.46).storage);
    c.drawCircle(Offset.zero, rw, Paint()..color = Colors.white);
    c.drawCircle(
      Offset.zero,
      rw,
      Paint()
        ..color = const Color(0xFF634AC4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final now = DateTime.now();
    final hand = Paint()
      ..color = const Color(0xFF2A2A40)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final ha = (now.hour % 12 + now.minute / 60) / 12 * 2 * math.pi - math.pi / 2;
    final ma = now.minute / 60 * 2 * math.pi - math.pi / 2;
    c.drawLine(Offset.zero, Offset(math.cos(ha), math.sin(ha)) * rw * 0.5, hand);
    c.drawLine(Offset.zero, Offset(math.cos(ma), math.sin(ma)) * rw * 0.78, hand);
    c.restore();
  }

  void _examHall(Canvas c, _Bldg b) {
    const wall = Color(0xFFAED9F5);
    _box(
      c,
      b.x0 - 0.1,
      b.y0 - 0.1,
      b.x1 + 0.1,
      b.y1 + 0.1,
      0,
      0.1,
      const Color(0xFFE6E9F2),
      const Color(0xFFCDD3E3),
      const Color(0xFFF2F4FA),
    );
    _box(c, b.x0, b.y0, b.x1, b.y1, 0.1, b.h - 0.1, wall, pal.shade(wall, 0.18), wall);
    _windows(c, b, 0.1, 2, 0, 3, inset: 0.2);
    // Colonnade on the front facade.
    for (var i = 0; i < 5; i++) {
      final x = b.x0 + 0.25 + (b.x1 - b.x0 - 0.5) * i / 4;
      _fill(c, [
        iso.p(x - 0.07, b.y1 + 0.18, 0.1),
        iso.p(x + 0.07, b.y1 + 0.18, 0.1),
        iso.p(x + 0.07, b.y1 + 0.18, b.h),
        iso.p(x - 0.07, b.y1 + 0.18, b.h),
      ], Colors.white.withValues(alpha: night ? 0.7 : 0.95));
    }
    // Gable roof, ridge along x.
    final ym = (b.y0 + b.y1) / 2;
    final h = b.h, rz = b.h + b.roof;
    const roof = Color(0xFF5B9BD5);
    _fill(c, [
      iso.p(b.x0, b.y0 - 0.1, h),
      iso.p(b.x1 + 0.1, b.y0 - 0.1, h),
      iso.p(b.x1 + 0.1, ym, rz),
      iso.p(b.x0, ym, rz),
    ], pal.shade(roof, 0.25));
    _fill(c, [iso.p(b.x0, b.y1 + 0.25, h), iso.p(b.x1 + 0.1, b.y1 + 0.25, h), iso.p(b.x1 + 0.1, ym, rz), iso.p(b.x0, ym, rz)], roof);
    _fill(c, [iso.p(b.x1 + 0.1, b.y0 - 0.1, h), iso.p(b.x1 + 0.1, b.y1 + 0.25, h), iso.p(b.x1 + 0.1, ym, rz)], const Color(0xFFE8F3FC));
  }

  void _kiosk(Canvas c, _Bldg b) {
    const wood = Color(0xFFC98A5C);
    for (final x in [b.x0 + 0.1, b.x1 - 0.1]) {
      _box(c, x - 0.05, b.y1 - 0.15, x + 0.05, b.y1 - 0.05, 0, b.h + 0.1, wood, pal.shade(wood, 0.2), wood);
    }
    // Board facing south-west.
    _fill(c, [
      iso.p(b.x0, b.y1 - 0.1, 0.25),
      iso.p(b.x1, b.y1 - 0.1, 0.25),
      iso.p(b.x1, b.y1 - 0.1, b.h),
      iso.p(b.x0, b.y1 - 0.1, b.h),
    ], const Color(0xFFE2B07F));
    final notes = [CsColors.sun, Colors.white, CsColors.mint, const Color(0xFFFFB3C7)];
    for (var i = 0; i < 4; i++) {
      final u0 = b.x0 + 0.08 + i * 0.25, u1 = u0 + 0.19;
      final za = 0.33 + (i.isEven ? 0.0 : 0.06), zb = za + 0.3;
      _fill(c, [iso.p(u0, b.y1 - 0.09, za), iso.p(u1, b.y1 - 0.09, za), iso.p(u1, b.y1 - 0.09, zb), iso.p(u0, b.y1 - 0.09, zb)], notes[i]);
    }
    // Little roof.
    _box(
      c,
      b.x0 - 0.1,
      b.y1 - 0.4,
      b.x1 + 0.1,
      b.y1 + 0.05,
      b.h,
      b.roof,
      const Color(0xFFD97B5A),
      const Color(0xFFB8613F),
      const Color(0xFFF09A78),
    );
  }

  void _pavilion(Canvas c, _Bldg b) {
    // Low stage.
    _box(c, b.x0, b.y0, b.x1, b.y1, 0, 0.12, const Color(0xFFEBD3B6), const Color(0xFFD5B994), const Color(0xFFF6E6D0));
    // Poles.
    for (final (x, y) in [(b.x0 + 0.1, b.y1 - 0.1), (b.x1 - 0.1, b.y1 - 0.1), (b.x1 - 0.1, b.y0 + 0.1)]) {
      c.drawLine(
        iso.p(x, y, 0.12),
        iso.p(x, y, b.h),
        Paint()
          ..color = const Color(0xFF8C5E3C)
          ..strokeWidth = 2,
      );
    }
    // Striped tent roof (pyramid).
    final apex = iso.p((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, b.h + b.roof);
    const stripes = 6;
    for (var i = 0; i < stripes; i++) {
      final a0 = b.x0 + (b.x1 - b.x0) * i / stripes, a1 = b.x0 + (b.x1 - b.x0) * (i + 1) / stripes;
      _fill(c, [iso.p(a0, b.y1, b.h), iso.p(a1, b.y1, b.h), apex], i.isEven ? CsColors.coral : const Color(0xFFFFF1E6));
      final v0 = b.y0 + (b.y1 - b.y0) * i / stripes, v1 = b.y0 + (b.y1 - b.y0) * (i + 1) / stripes;
      _fill(c, [iso.p(b.x1, v0, b.h), iso.p(b.x1, v1, b.h), apex], pal.shade(i.isEven ? CsColors.coral : const Color(0xFFFFF1E6), 0.15));
    }
  }

  void _tree(Canvas c, double x, double y, double s) {
    final base = iso.p(x, y);
    final r = iso.tw * 0.32 * s;
    c.drawOval(
      Rect.fromCenter(center: base + const Offset(2, 1), width: r * 2.2, height: r * 0.9),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );
    c.drawLine(
      base,
      base - Offset(0, r * 1.1),
      Paint()
        ..color = const Color(0xFF8C5E3C)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    final leaf = night ? const Color(0xFF2F7D5B) : CsColors.grassDeep;
    c.drawCircle(base - Offset(0, r * 1.6), r, Paint()..color = leaf);
    c.drawCircle(base - Offset(r * 0.5, r * 1.25), r * 0.7, Paint()..color = pal.shade(leaf, 0.12));
    c.drawCircle(base - Offset(-r * 0.3, r * 1.95), r * 0.45, Paint()..color = Color.lerp(leaf, Colors.white, night ? 0.05 : 0.25)!);
  }

  void _bench(Canvas c, double x, double y) {
    const wood = Color(0xFFB9784D);
    _box(c, x - 0.25, y - 0.08, x + 0.25, y + 0.08, 0.1, 0.05, wood, pal.shade(wood, 0.2), const Color(0xFFD39367));
    _box(c, x - 0.25, y - 0.1, x + 0.25, y - 0.06, 0.15, 0.14, wood, pal.shade(wood, 0.2), const Color(0xFFD39367));
  }

  void _lamp(Canvas c, double x, double y) {
    final base = iso.p(x, y), top = iso.p(x, y, 0.75);
    c.drawLine(
      base,
      top,
      Paint()
        ..color = const Color(0xFF4A4A68)
        ..strokeWidth = 2,
    );
    if (night) {
      c.drawCircle(
        top,
        iso.tw * 0.5,
        Paint()
          ..color = const Color(0xFFFFE08A).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    c.drawCircle(top, 3, Paint()..color = night ? const Color(0xFFFFE08A) : Colors.white);
  }

  void _fountainBase(Canvas c) {
    final ctr = iso.p(5.5, 5.5);
    final w = iso.tw * 1.3;
    c.drawOval(Rect.fromCenter(center: ctr, width: w, height: w * 0.5), Paint()..color = const Color(0xFFCFC6E8));
    c.drawOval(
      Rect.fromCenter(center: ctr - const Offset(0, 2), width: w * 0.86, height: w * 0.42),
      Paint()..color = night ? const Color(0xFF4F7FC0) : const Color(0xFF7CC4F2),
    );
    c.drawRect(
      Rect.fromCenter(center: ctr - Offset(0, iso.tw * 0.2), width: 5, height: iso.tw * 0.4),
      Paint()..color = const Color(0xFFCFC6E8),
    );
  }

  @override
  bool shouldRepaint(_WorldPainter old) => old.iso.size != iso.size || old.night != night || old.active != active || old.press != press;
}

/// Animated layers: clouds/birds behind the island, people/water/bunting in front.
class _AmbientPainter extends CustomPainter {
  final Animation<double> t;
  final _Iso iso;
  final bool night;
  final bool back;
  _AmbientPainter(this.t, this.iso, this.night, {required this.back}) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size s) => back ? _sky(canvas, s) : _front(canvas);

  void _sky(Canvas c, Size s) {
    final v = t.value;
    final p = Paint()..color = Colors.white.withValues(alpha: night ? 0.18 : 0.92);
    for (final (base, y, k) in [(0.05, 0.10, 1.0), (0.45, 0.22, 0.75), (0.8, 0.06, 0.6)]) {
      final x = ((base + v * k) % 1.35 - 0.2) * s.width;
      final r = 13.0 * k + 6;
      final cy = s.height * y;
      c.drawCircle(Offset(x, cy), r, p);
      c.drawCircle(Offset(x + r, cy - r * 0.5), r * 1.2, p);
      c.drawCircle(Offset(x + r * 2.2, cy), r, p);
      c.drawRRect(RRect.fromLTRBR(x - r, cy - 2, x + r * 3.2, cy + r, Radius.circular(r)), p);
    }
    if (!night) {
      final bird = Paint()
        ..color = const Color(0xFF5A5F7A)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < 3; i++) {
        final x = ((v * 2.2 + i * 0.07) % 1.2 - 0.1) * s.width;
        final y = s.height * (0.16 + i * 0.03) + math.sin(v * 80 + i) * 3;
        final flap = math.sin(v * 400 + i * 2) * 3;
        c.drawPath(
          Path()
            ..moveTo(x - 5, y - flap)
            ..quadraticBezierTo(x - 2, y - 2, x, y)
            ..quadraticBezierTo(x + 2, y - 2, x + 5, y - flap),
          bird,
        );
      }
    }
  }

  void _front(Canvas c) {
    final v = t.value;
    // Fountain spray.
    final ctr = iso.p(5.5, 5.5) - Offset(0, iso.tw * 0.4);
    final water = Paint()
      ..color = (night ? const Color(0xFFB9D6FF) : Colors.white).withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final a = i / 6 * 2 * math.pi + v * 20;
      final dx = math.cos(a) * iso.tw * 0.45;
      final dy = math.sin(a) * iso.tw * 0.18;
      c.drawPath(
        Path()
          ..moveTo(ctr.dx, ctr.dy)
          ..quadraticBezierTo(ctr.dx + dx * 0.4, ctr.dy - iso.tw * 0.45, ctr.dx + dx, ctr.dy + iso.tw * 0.32 + dy),
        water,
      );
    }
    // Ripples.
    final ripple = (v * 30) % 1;
    c.drawOval(
      Rect.fromCenter(center: iso.p(5.5, 5.5) - const Offset(0, 2), width: iso.tw * 0.9 * ripple, height: iso.tw * 0.42 * ripple),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6 * (1 - ripple))
        ..style = PaintingStyle.stroke,
    );
    // Bunting on the pavilion.
    final colors = [CsColors.sun, CsColors.mint, CsColors.seed, CsColors.coral];
    for (var i = 0; i < 7; i++) {
      final a = iso.p(7.0 + i * 0.29, 2.95, 0.62);
      final sway = math.sin(v * 120 + i) * 1.4;
      c.drawPath(
        Path()
          ..moveTo(a.dx - 4, a.dy)
          ..lineTo(a.dx + 4, a.dy)
          ..lineTo(a.dx + sway, a.dy + 8)
          ..close(),
        Paint()..color = colors[i % 4],
      );
    }
    // Strolling students along walkways.
    final shirts = [CsColors.seed, CsColors.coral, CsColors.mint, const Color(0xFFB079F2), CsColors.sun];
    for (var i = 0; i < 5; i++) {
      final path = _paths[i % _paths.length];
      final phase = (v * (3 + i) + i * 0.27) % 2;
      final f = phase > 1 ? 2 - phase : phase; // back and forth
      final pos = _along(path, f);
      final o = iso.p(pos.$1, pos.$2);
      final bob = math.sin(v * 600 + i) * 0.8;
      c.drawOval(Rect.fromCenter(center: o, width: 8, height: 3), Paint()..color = Colors.black.withValues(alpha: 0.15));
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: o - Offset(0, 6 + bob), width: 6, height: 9), const Radius.circular(3)),
        Paint()..color = shirts[i],
      );
      c.drawCircle(o - Offset(0, 13 + bob), 3.2, Paint()..color = const Color(0xFFF2C5A0));
    }
  }

  static (double, double) _along(List<(double, double)> pts, double f) {
    final lens = <double>[];
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final d = math.sqrt(math.pow(pts[i].$1 - pts[i - 1].$1, 2) + math.pow(pts[i].$2 - pts[i - 1].$2, 2));
      lens.add(d);
      total += d;
    }
    var target = f * total;
    for (var i = 0; i < lens.length; i++) {
      if (target <= lens[i] || i == lens.length - 1) {
        final k = lens[i] == 0 ? 0.0 : (target / lens[i]).clamp(0.0, 1.0);
        return (pts[i].$1 + (pts[i + 1].$1 - pts[i].$1) * k, pts[i].$2 + (pts[i + 1].$2 - pts[i].$2) * k);
      }
      target -= lens[i];
    }
    return pts.last;
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.night != night || old.iso.size != iso.size;
}
