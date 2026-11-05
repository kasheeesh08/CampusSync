import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../theme.dart';

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(Gap.l), this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    clipBehavior: Clip.antiAlias,
    // Tappable cards are announced as buttons to screen readers.
    child: Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const Pill(this.label, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Gap.l),
              decoration: BoxDecoration(color: t.colorScheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: t.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: Gap.l),
            Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Gap.s),
            Text(
              message,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: Gap.l), action!],
          ],
        ),
      ),
    );
  }
}

/// Shows demo / offline / error state above content.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    Widget banner(IconData icon, String text, Color c, {VoidCallback? retry}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Gap.l, 0, Gap.l, Gap.s),
      padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: Gap.s),
          Expanded(
            child: Text(text, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface)),
          ),
          if (retry != null) TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );
    if (s.offline && s.error != null) {
      return banner(Icons.cloud_off_rounded, s.error!, CsColors.partial, retry: s.refreshing ? null : s.refresh);
    }
    if (s.environmentNote != null) return banner(Icons.science_outlined, s.environmentNote!, CsColors.partial);
    if (s.isDemo) {
      return banner(
        Icons.science_outlined,
        'Demo mode: showing the bundled reference data; nothing is saved to a server.',
        t.colorScheme.primary,
      );
    }
    return const SizedBox.shrink();
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const InfoRow(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.colorScheme.primary),
          const SizedBox(width: Gap.m),
          SizedBox(
            width: 92,
            child: Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
}

/// Opens only well-formed http(s) links, in the external browser.
Future<void> openExternalLink(BuildContext context, String? url) async {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
    showMessage(context, 'This link is not a valid web address.', error: true);
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showMessage(context, 'Could not open the link.', error: true);
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirm',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

const avatars = {'fox': '🦊', 'panda': '🐼', 'owl': '🦉', 'koala': '🐨', 'tiger': '🐯', 'penguin': '🐧', 'cat': '🐱', 'frog': '🐸'};

class AvatarBubble extends StatelessWidget {
  final String avatar;
  final double size;
  final bool selected;
  const AvatarBubble(this.avatar, {super.key, this.size = 48, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHighest,
        border: Border.all(color: selected ? t.colorScheme.primary : Colors.transparent, width: 3),
      ),
      child: Text(avatars[avatar] ?? '🦊', style: TextStyle(fontSize: size * 0.5)),
    );
  }
}
