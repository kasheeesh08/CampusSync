import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AnnouncementDetail extends StatelessWidget {
  final Announcement announcement;
  const AnnouncementDetail({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context);
    final a = announcement;
    final fmt = DateFormat('EEE d MMM yyyy');
    final timing = a.timing(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: s.isSaved(a.id) ? 'Remove from saved' : 'Save for offline',
            icon: Icon(s.isSaved(a.id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
            onPressed: () => s.toggleSaved(a),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        children: [
          if (a.imageUrl != null && a.imageUrl!.startsWith('https://'))
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.l),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(a.imageUrl!, height: 180, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          Wrap(
            spacing: 6,
            children: [
              Pill(a.category, color: t.colorScheme.primary),
              if (timing != 'undated') Pill(timing, color: timing == 'expired' ? CsColors.unavailable : CsColors.mint),
            ],
          ),
          const SizedBox(height: Gap.m),
          Text(a.title, style: t.textTheme.headlineSmall),
          const SizedBox(height: Gap.l),
          if (a.startDate != null) InfoRow(Icons.event_rounded, 'Starts', fmt.format(a.startDate!)),
          if (a.endDate != null) InfoRow(Icons.event_busy_rounded, 'Ends / deadline', fmt.format(a.endDate!)),
          if (a.source != null) InfoRow(Icons.source_outlined, 'Source', a.source!),
          const SizedBox(height: Gap.l),
          Text(a.description ?? a.summary ?? 'No further details were provided.', style: t.textTheme.bodyLarge),
          const SizedBox(height: Gap.xl),
          // The link may be a registration form or, once registration has
          // closed, the official event page, so the label must not promise
          // that registration is open; the description states the status.
          if (a.registrationUrl != null)
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open official link'),
              onPressed: timing == 'expired' ? null : () => openExternalLink(context, a.registrationUrl),
            ),
          if (a.registrationUrl != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.s),
              child: Text(
                timing == 'expired'
                    ? 'This announcement has ended.'
                    : 'Opens ${Uri.tryParse(a.registrationUrl!)?.host ?? 'the link'} in your browser.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
