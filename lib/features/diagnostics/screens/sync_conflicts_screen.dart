// Gene - Nov, 28, 2026: Needs Review screen surfacing 409 REASSIGNED/CANCELLED sync conflicts without stalling queued orders.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/database/models/sync_conflict.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../signals/sync_conflicts_signals.dart';

class SyncConflictsScreen extends StatelessWidget {
  final SyncConflictsSignals signals;

  const SyncConflictsScreen({super.key, required this.signals});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Needs Review'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(CupertinoIcons.refresh, size: 22),
            onPressed: signals.refresh,
          ),
        ],
      ),
      body: SignalBuilder(
        builder: (context) {
          final conflicts = signals.unresolvedConflicts.value;
          if (conflicts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_shield,
                      size: 48,
                      color: AppTheme.successInkOf(context),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'All Clear',
                      style: context.text.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No conflicted or reassigned orders need your review.',
                      style: context.text.bodyMedium!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: conflicts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _ConflictCard(
              conflict: conflicts[index],
              onDismiss: () => signals.dismissConflict(conflicts[index].id),
            ),
          );
        },
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final SyncConflict conflict;
  final VoidCallback onDismiss;

  const _ConflictCard({
    required this.conflict,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = conflict.decodedServerSnapshot;
    final assignedEmail =
        snapshot['assigned_email'] ?? snapshot['assignedEmail'];
    final serverStatus = snapshot['status'] ?? snapshot['support_status'];
    final warnColor = AppTheme.warningInkOf(context);
    final dangerColor = AppTheme.dangerInkOf(context);
    final badgeColor = conflict.reason == 'CANCELLED' ? dangerColor : warnColor;

    return Card(
      key: ValueKey('sync_conflict_card_${conflict.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text(
                  conflict.referenceLabel,
                  style: context.text.titleMedium,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusStamp),
                    border: Border.all(color: badgeColor, width: 1.5),
                  ),
                  child: Text(
                    conflict.reason,
                    style: context.text.labelMedium!.copyWith(
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              conflict.message.trim().isNotEmpty
                  ? conflict.message
                  : 'Server rejected this offline update (${conflict.reason}).',
              style: context.text.bodyMedium,
            ),
            if (assignedEmail != null &&
                assignedEmail.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.person_crop_circle,
                    size: 20,
                    color: AppTheme.secondaryInkOf(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Assigned on server: $assignedEmail',
                      style: context.text.bodySmall!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (serverStatus != null &&
                serverStatus.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.info_circle,
                    size: 20,
                    color: AppTheme.secondaryInkOf(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Server status: $serverStatus',
                      style: context.text.bodySmall!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (conflict.decodedLocalPayload.isNotEmpty) ...[
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'View queued changes',
                  style: context.text.labelLarge,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      conflict.decodedLocalPayload.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n'),
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.minTarget),
              child: OutlinedButton.icon(
                key: ValueKey('dismiss_conflict_${conflict.id}'),
                onPressed: onDismiss,
                icon: const Icon(CupertinoIcons.checkmark_alt, size: 20),
                label: const Text('Dismiss'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
