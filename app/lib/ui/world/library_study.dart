import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../domain/focus.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'character.dart';

String formatRemaining(Duration d) {
  final total = d.inSeconds.clamp(0, 1 << 30);
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Library study hall (Floor 7). The location is verified; the desk layout is
/// an illustration. Students pick a desk, their character sits there, and a
/// focus session can be run, paused, resumed and ended.
class LibraryStudyScreen extends StatefulWidget {
  const LibraryStudyScreen({super.key});
  @override
  State<LibraryStudyScreen> createState() => _LibraryStudyScreenState();
}

class _LibraryStudyScreenState extends State<LibraryStudyScreen> with WidgetsBindingObserver {
  static const _entrance = Offset(0.5, 0.95);
  final _space = libraryStudySpace;
  String? _spotId;
  bool _walking = false;
  bool _seated = false;
  int _minutes = 25;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = context.read<AppState>();
    // Return to the desk of the running (or just-finished) session.
    final session = s.activeFocus ?? s.lastFinishedFocus;
    if (session != null && session.spaceId == _space.id) {
      _spotId = session.spotId;
      _seated = true;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick(); // recompute from the wall clock
  }

  void _tick() {
    if (!mounted) return;
    final s = context.read<AppState>();
    if (s.activeFocus != null) {
      s.settleFocus();
      setState(() {});
    }
  }

  Future<void> _chooseSpot(StudySpot spot) async {
    final s = context.read<AppState>();
    if (s.activeFocus != null) {
      showMessage(context, 'End your current session before moving to another desk.', error: true);
      return;
    }
    setState(() {
      _spotId = spot.id;
      _walking = true;
      _seated = false;
    });
    await Future<void>.delayed(Duration(milliseconds: s.prefs.reduceMotion ? 50 : 750));
    if (!mounted) return;
    setState(() {
      _walking = false;
      _seated = true;
    });
  }

  Future<void> _start() async {
    final s = context.read<AppState>();
    final spot = _space.spots.firstWhere((x) => x.id == _spotId);
    try {
      await s.startFocus(space: _space, spot: spot, minutes: _minutes);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    }
  }

  Future<void> _end() async {
    final s = context.read<AppState>();
    final ok = await confirmAction(
      context,
      title: 'End session early?',
      message: 'Your focused time so far is saved to your history.',
      confirm: 'End session',
      destructive: true,
    );
    if (ok) await s.endFocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final active = s.activeFocus;
    final spot = _space.spots.where((x) => x.id == _spotId).firstOrNull;
    // Seated: stand the character just behind the desk so the desk hides the legs.
    final pos = spot == null ? _entrance : Offset(spot.x, _seated ? spot.y + 0.01 : spot.y + 0.08);
    final color = characterColors[s.prefs.characterColor % characterColors.length];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Leave library', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_space.name),
            Text('Study hall', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Back to campus',
            icon: const Icon(Icons.park_rounded),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.s),
                  padding: const EdgeInsets.all(Gap.s),
                  decoration: BoxDecoration(color: CsColors.partial.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: CsColors.partial),
                      const SizedBox(width: Gap.s),
                      Expanded(child: Text(_space.layoutNote, style: t.textTheme.bodySmall)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.l),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: AspectRatio(
                      aspectRatio: 1.15,
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final charSize = c.maxWidth * 0.13;
                          final character = AnimatedPositioned(
                            duration: Duration(milliseconds: s.prefs.reduceMotion ? 1 : 700),
                            curve: Curves.easeInOutCubic,
                            left: pos.dx * c.maxWidth - charSize * 0.4,
                            top: pos.dy * c.maxHeight - charSize * 0.95,
                            child: IgnorePointer(
                              child: CampusCharacter(
                                avatar: s.profile?.avatar ?? 'fox',
                                color: color,
                                size: charSize,
                                pose: _walking ? CharacterPose.walking : (_seated ? CharacterPose.sitting : CharacterPose.idle),
                                reduceMotion: s.prefs.reduceMotion,
                                focusing: active?.status == FocusStatus.running,
                              ),
                            ),
                          );
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(painter: _HallPainter(lit: active?.status == FocusStatus.running)),
                              ),
                              if (_seated) character,
                              for (final d in _space.spots)
                                _Desk(
                                  spot: d,
                                  box: c.biggest,
                                  selected: d.id == _spotId,
                                  locked: active != null && d.id != _spotId,
                                  onTap: () => _chooseSpot(d),
                                ),
                              if (!_seated) character,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(Gap.l),
                  child: _FocusPanel(
                    spot: spot,
                    seated: _seated,
                    minutes: _minutes,
                    onMinutes: (m) => setState(() => _minutes = m),
                    onStart: _start,
                    onEnd: _end,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.xl),
                  child: _History(state: s),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Desk extends StatelessWidget {
  final StudySpot spot;
  final Size box;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  const _Desk({required this.spot, required this.box, required this.selected, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final w = box.width * 0.17, h = box.height * 0.12;
    return Positioned(
      left: spot.x * box.width - w / 2,
      top: spot.y * box.height - h / 2,
      width: w,
      height: h,
      child: Semantics(
        button: true,
        enabled: !locked,
        selected: selected,
        label: '${spot.label}${selected ? ', your desk' : ''}',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: const Color(0xFFC98A5C).withValues(alpha: locked ? 0.45 : 1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: selected ? t.colorScheme.primary : const Color(0xFF8C5E3C), width: selected ? 3 : 1.2),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 3, offset: const Offset(0, 2))],
            ),
            alignment: Alignment.bottomCenter,
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(
                  spot.label.replaceAll('Desk ', ''),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusPanel extends StatelessWidget {
  final StudySpot? spot;
  final bool seated;
  final int minutes;
  final ValueChanged<int> onMinutes;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  const _FocusPanel({
    required this.spot,
    required this.seated,
    required this.minutes,
    required this.onMinutes,
    required this.onStart,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final active = s.activeFocus;
    final done = s.lastFinishedFocus;
    final now = s.clock();

    if (active != null) {
      final remaining = active.remainingAt(now);
      final progress = 1 - remaining.inSeconds / active.planned.inSeconds;
      final paused = active.status == FocusStatus.paused;
      return SectionCard(
        child: Column(
          children: [
            Text(
              paused ? 'PAUSED' : 'FOCUSING',
              style: t.textTheme.labelLarge?.copyWith(
                color: paused ? CsColors.partial : t.colorScheme.primary,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: Gap.s),
            SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      strokeWidth: 10,
                      backgroundColor: t.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  Semantics(
                    label: 'Time remaining ${formatRemaining(remaining)}',
                    child: Text(
                      formatRemaining(remaining),
                      style: t.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.s),
            Text('${active.plannedMinutes}-minute session · ${_deskLabel(active.spotId)}', style: t.textTheme.bodySmall),
            const SizedBox(height: Gap.m),
            Row(
              children: [
                Expanded(
                  child: paused
                      ? FilledButton.icon(icon: const Icon(Icons.play_arrow_rounded), label: const Text('Resume'), onPressed: s.resumeFocus)
                      : FilledButton.tonalIcon(icon: const Icon(Icons.pause_rounded), label: const Text('Pause'), onPressed: s.pauseFocus),
                ),
                const SizedBox(width: Gap.s),
                Expanded(
                  child: OutlinedButton.icon(icon: const Icon(Icons.stop_rounded), label: const Text('End'), onPressed: onEnd),
                ),
              ],
            ),
            const SizedBox(height: Gap.s),
            Text(
              'The timer keeps time even if you leave the app. A reminder is scheduled for the end of the session if notifications are allowed.',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (done != null) {
      final focused = done.focusedAt(now);
      final completed = done.status == FocusStatus.completed;
      return SectionCard(
        color: (completed ? CsColors.mint : CsColors.partial).withValues(alpha: 0.12),
        child: Column(
          children: [
            Icon(completed ? Icons.celebration_rounded : Icons.flag_rounded, size: 40, color: completed ? CsColors.mint : CsColors.partial),
            const SizedBox(height: Gap.s),
            Text(completed ? 'Session complete' : 'Session ended early', style: t.textTheme.titleLarge),
            Text(
              '${focused.inMinutes} min ${focused.inSeconds % 60} s of ${done.plannedMinutes} min recorded',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.m),
            FilledButton(onPressed: s.dismissFocusResult, child: const Text('Done')),
          ],
        ),
      );
    }

    if (spot == null || !seated) {
      return SectionCard(
        child: Row(
          children: [
            Icon(Icons.chair_alt_rounded, color: t.colorScheme.primary),
            const SizedBox(width: Gap.m),
            Expanded(child: Text(spot == null ? 'Tap a desk to sit down.' : 'Walking to ${spot!.label}…', style: t.textTheme.bodyMedium)),
          ],
        ),
      );
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seated at ${spot!.label}', style: t.textTheme.titleMedium),
          const SizedBox(height: Gap.s),
          Text('Focus duration', style: t.textTheme.labelLarge),
          const SizedBox(height: Gap.xs),
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.s,
            children: [
              for (final m in FocusSession.allowedMinutes)
                ChoiceChip(label: Text('$m min'), selected: minutes == m, onSelected: (_) => onMinutes(m)),
            ],
          ),
          const SizedBox(height: Gap.m),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(icon: const Icon(Icons.timer_rounded), label: Text('Start $minutes-minute focus'), onPressed: onStart),
          ),
        ],
      ),
    );
  }

  static String _deskLabel(String id) => libraryStudySpace.spots.where((x) => x.id == id).firstOrNull?.label ?? id;
}

class _History extends StatelessWidget {
  final AppState state;
  const _History({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final now = state.clock();
    final history = state.focusHistory;
    final today = history.where((h) => DateUtils.isSameDay(h.startedAt, now));
    final stats = FocusStats.of(today, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Your sessions', style: t.textTheme.titleMedium)),
            Text('Today: ${stats.sessions} · ${stats.total.inMinutes} min', style: t.textTheme.labelLarge),
          ],
        ),
        Text(state.focusRepo.storageLabel, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: Gap.s),
        if (history.isEmpty)
          Text('No sessions yet.', style: t.textTheme.bodyMedium)
        else
          for (final h in history.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                h.status == FocusStatus.completed ? Icons.check_circle_rounded : Icons.flag_rounded,
                color: h.status == FocusStatus.completed ? CsColors.mint : CsColors.partial,
              ),
              title: Text(
                '${h.focusedAt(now).inMinutes} of ${h.plannedMinutes} min · ${h.status == FocusStatus.completed ? 'completed' : 'ended early'}',
              ),
              subtitle: Text('${DateFormat('EEE d MMM, h:mm a').format(h.startedAt)} · ${_FocusPanel._deskLabel(h.spotId)}'),
            ),
      ],
    );
  }
}

/// Illustrated study hall: wooden floor, bookshelves, windows and lamps.
class _HallPainter extends CustomPainter {
  final bool lit;
  _HallPainter({required this.lit});

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFF3E3CC));
    // Floor planks.
    final plank = Paint()..color = const Color(0xFFE6CFAE);
    for (var y = h * 0.16; y < h; y += h * 0.07) {
      canvas.drawLine(Offset(0, y), Offset(w, y), plank..strokeWidth = 1);
    }
    // Back wall with windows and shelves.
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.16), Paint()..color = const Color(0xFFB9A2D9));
    for (var i = 0; i < 3; i++) {
      final x = w * (0.08 + i * 0.32);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, h * 0.025, w * 0.2, h * 0.1), const Radius.circular(4)),
        Paint()..color = const Color(0xFFDDEBFF),
      );
    }
    final colors = [
      const Color(0xFF5B6CFF),
      const Color(0xFFFF8A65),
      const Color(0xFF3CC9A0),
      const Color(0xFFF5A524),
      const Color(0xFFB079F2),
    ];
    final rnd = math.Random(4);
    for (final sx in [0.0, w * 0.93]) {
      canvas.drawRect(Rect.fromLTWH(sx, h * 0.16, w * 0.07, h * 0.7), Paint()..color = const Color(0xFF8C5E3C));
      for (var y = h * 0.18; y < h * 0.84; y += h * 0.06) {
        var bx = sx + w * 0.006;
        while (bx < sx + w * 0.064) {
          final bw = w * (0.008 + rnd.nextDouble() * 0.006);
          canvas.drawRect(Rect.fromLTWH(bx, y, bw, h * 0.045), Paint()..color = colors[rnd.nextInt(colors.length)]);
          bx += bw + 1;
        }
      }
    }
    // Rug and entrance.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.38, h * 0.88, w * 0.24, h * 0.12), const Radius.circular(6)),
      Paint()..color = const Color(0xFF7C6FD6).withValues(alpha: 0.5),
    );
    // Warm glow while a session runs.
    if (lit) {
      canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFFE08A).withValues(alpha: 0.12));
    }
  }

  @override
  bool shouldRepaint(_HallPainter old) => old.lit != lit;
}
