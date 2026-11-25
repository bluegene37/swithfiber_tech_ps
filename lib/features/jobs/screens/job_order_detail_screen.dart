// Gene - Oct 13, 2026: Commented out unused dart:convert import since radius username decoding is handled in JobOrderDto
// import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
/*
import '../../../core/widgets/action_pair.dart';
*/
// Gene - Oct 13, 2026: Commented out unused action_pair import as Navigate and Call buttons were removed from details per user request.
import '../../../core/widgets/adaptive_dialogs.dart';
import '../../../core/widgets/status_stamp.dart';
import '../../../core/widgets/sticky_action_bar.dart';
// Gene - Nov, 25, 2026: Added WorkTimingLockBanner to show Start/Finish lock state on Job Order details.
import '../../../core/widgets/work_timing_bar.dart';
// Gene - Nov, 26, 2026: Added WorkTimingEntry and OrderTimingHistoryCard for Job Order session history.
import '../../../core/database/models/work_timing_entry.dart';
import '../../diagnostics/screens/work_timing_history_screen.dart';
import '../widgets/job_contact.dart';
import '../widgets/job_navigation.dart';
import '../../diagnostics/widgets/radius_connection_card.dart';
/*
import '../../lcp_nap/models/lcp_nap_model.dart';
*/
// Gene - Oct 13, 2026: Commented out unused lcp_nap_model import as nearest NAP details were decoupled from location card.
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../models/job_order_model.dart';
import '../signals/jobs_signals.dart';
/*
import '../widgets/job_photo_gallery.dart';
*/
// Gene - Oct 13, 2026: Commented out unused job_photo_gallery import as on-site records verification was removed from details per user request.
import '../widgets/status_badge.dart';
import '../widgets/status_change_sheet.dart';
// Gene - Nov 5, 2026: Imported JobSitePhotosCard for remote photo proofs gallery and full-screen lightbox preview.
import '../widgets/job_site_photos_card.dart';
import '../../reports/screens/create_report_screen.dart';
import '../../reports/signals/report_signals.dart';
import '../../../core/services/map_navigation_service.dart';
// Gene - Oct 12, 2026: Added imports for landmark photo preview and full-screen viewer.
import '../../../core/services/photo_storage_service.dart';
import '../../../core/utils/data_url.dart';
import '../../reports/widgets/photo_capture_tile.dart' show showPhotoViewer;
// Gene - Oct 13, 2026: Added flutter_map and MapTiles imports to render map location in Job Order details.
import 'package:flutter_map/flutter_map.dart';
import '../../lcp_nap/screens/lcp_nap_detail_screen.dart';
import '../../lcp_nap/services/map_tiles.dart';
import '../../lcp_nap/services/nap_port_occupancy.dart';

/// Comprehensive details screen for a Job Order with full Dark Mode support
/// and responsive flex layouts.
///
/// With [readOnly] set (the job history) every action that changes the record
/// is hidden: no activation, no completion report. Navigation, calling and
/// copying stay available since they do not touch the job.
class JobOrderDetailScreen extends StatelessWidget {
  final int jobId;
  final JobsSignals jobsSignals;
  final LcpNapSignals? lcpNapSignals;
  final void Function(JobOrderDto job)? onOpenReport;
  final bool readOnly;
  final bool automaticallyImplyLeading;

  const JobOrderDetailScreen({
    super.key,
    required this.jobId,
    required this.jobsSignals,
    this.lcpNapSignals,
    this.onOpenReport,
    this.readOnly = false,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Gene - Nov, 20, 2026: Ensure opening JobOrderDetailScreen directly marks the job as read safely after the current frame.
    if (!readOnly && !jobsSignals.isJobReadPeek(jobId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        jobsSignals.markJobAsRead(jobId);
      });
    }

    return SignalBuilder(
      builder: (context) {
        final allJobs = jobsSignals.allJobs.value;
        final job = allJobs.where((j) => j.id == jobId).firstOrNull;

        if (job == null) {
          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: automaticallyImplyLeading,
              title: const Text('Work Order Details'),
            ),
            body: Center(
              child: Text(
                'Job Order not found or removed.',
                style: TextStyle(color: AppTheme.secondaryInkOf(context)),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: automaticallyImplyLeading,
            // Ticket number only; the plan is in the subscriber card. Keeps
            // the bar to one line at 200% text.
            title: Text(
              job.ticketNumber,
              style:
                  context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              Tooltip(
                message: job.isSynced
                    ? 'Synced with the server'
                    : 'Saved on phone, not yet synced',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    job.isSynced
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    size: 22,
                    color: job.isSynced
                        ? AppTheme.successInkOf(context)
                        : AppTheme.warningInkOf(context),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: StatusStamp(
                    label: job.status,
                    color: job.isHistory
                        ? AppTheme.successInkOf(context)
                        : AppTheme.infoInkOf(context),
                  ),
                ),
              ),
              // Gene - Nov, 23, 2026: Allow re-opening a filed completion report from AppBar before finalizing.
              // Gene - Nov, 25, 2026: Require active Start/Finish work timing unlock before allowing report edits.
              /*
              if (!readOnly &&
                  job.hasCompletedReport &&
                  job.canActivate &&
                  !job.isRescheduled &&
                  job.siteException != SiteException.reschedule)
              */
              if (!readOnly &&
                  job.hasCompletedReport &&
                  job.isWorkUnlocked &&
                  job.siteException != SiteException.reschedule)
                IconButton(
                  key: const ValueKey('appbar_edit_report_button'),
                  icon: const Icon(Icons.edit_note_rounded, size: 24),
                  tooltip: 'Edit Completion Report',
                  onPressed: () => _handleOpenReport(context, job),
                ),
              // Copy Ticket Summary Button
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 24),
                tooltip: 'Copy Ticket Summary',
                onPressed: () => _copyJobSummary(context, job, isDark),
              ),
            ],
          ),
          // The screen's one red verb (DESIGN.md): fill the report, then
          // complete the job. The line above it says which step this is.
          /*
          bottomNavigationBar: readOnly || !job.canActivate
              ? null
              : StickyActionBar(
                  label: job.hasCompletedReport
                      ? 'Complete job'
                      : 'Fill completion report',
                  icon: job.hasCompletedReport
                      ? Icons.check_circle_rounded
                      : Icons.assignment_turned_in_rounded,
                  why: job.hasCompletedReport
                      ? 'Report filed · ready to complete'
                      : 'Step 1 of 2 · a completion report is required',
                  onPressed: job.hasCompletedReport
                      ? () => _handleComplete(context, job, isDark)
                      : () => _handleOpenReport(context, job),
                ),
          */
          /*
          bottomNavigationBar: readOnly || !job.canActivate || job.isRescheduled
          */
          // Gene - Oct 13, 2026: Hide action bar if job is rescheduled or has reschedule site exception so completion reports cannot be filed.
          // Gene - Nov, 25, 2026: Also hide completion/report CTA until technician taps Start (and re-lock after Finish).
          /*
          bottomNavigationBar: readOnly ||
                  !job.canActivate ||
                  job.isRescheduled ||
                  job.siteException == SiteException.reschedule
              ? null
              : StickyActionBar(
          */
          bottomNavigationBar: readOnly ||
                  !job.isWorkUnlocked ||
                  job.siteException == SiteException.reschedule
              ? null
              : StickyActionBar(
                  label: job.hasCompletedReport
                      ? 'Complete job'
                      : 'Fill completion report',
                  icon: job.hasCompletedReport
                      ? Icons.check_circle_rounded
                      : Icons.assignment_turned_in_rounded,
                  why: job.hasCompletedReport
                      ? 'Report filed · ready to complete'
                      : 'Step 1 of 2 · a completion report is required',
                  onPressed: job.hasCompletedReport
                      ? () => _handleComplete(context, job, isDark)
                      : () => _handleOpenReport(context, job),
                ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
            children: [
              // Gene - Nov, 25, 2026: Show Start/Finish lock banner when Job Order editing/reporting is locked.
              if (!readOnly &&
                  job.canActivate &&
                  job.siteException != SiteException.reschedule &&
                  !job.isTimingInProgress)
                WorkTimingLockBanner(
                  key: const ValueKey('job_timing_lock_banner'),
                  status: job.workTimingStatus,
                  startTime: job.startTimeStamp,
                  endTime: job.endTimeStamp,
                ),
              // Read first: who and where, then the two actions the thumb
              // needs on arrival.
              _buildHeader(context, job, isDark),
              const SizedBox(height: 14),

              // What the technician reads on the ladder.
              _buildPlantLine(context, job),
              const SizedBox(height: 14),

/*
              if (job.siteException != null || job.isRescheduled) ...[
                _buildExceptionBanner(context, job, isDark),
                const SizedBox(height: 14),
              ],
*/
              if (job.siteException != null || job.isRescheduled) ...[
                _buildExceptionBanner(context, job, isDark),
                const SizedBox(height: 14),
              ],

              if (job.opticalPower != null) ...[
                _buildOpticalPowerCard(context, job, isDark),
                const SizedBox(height: 14),
              ],

              /*
              _buildOnsiteRecordsCard(context, job, isDark),
              const SizedBox(height: 14),
              */
              // Gene - Oct 13, 2026: Removed on-site records & verification card from details per user request.

              _buildCustomerCard(context, job, isDark),
              const SizedBox(height: 14),

              _buildLocationAndGpsCard(context, job, isDark),
              const SizedBox(height: 14),

              _buildPlantAndHardwareCard(context, job, isDark),
              const SizedBox(height: 14),

              // Gene - Nov 5, 2026: Rendered Site Photo Proofs card fetching from GET /api/JobOrders/{id}/GetJobOrderImage with refresh and zoom.
              JobSitePhotosCard(
                job: job,
                jobsSignals: jobsSignals,
              ),
              const SizedBox(height: 14),

              /*
              // Gene - Oct 12, 2026: Placed answering flow card after plant & hardware card so optical power card stays at original scroll offset.
              _buildAnsweringFlowCard(context, job, isDark),
              const SizedBox(height: 14),
              */
              // Gene - Oct 13, 2026: Removed answering flow card in details per user request.

              if (job.materialsUsed.isNotEmpty) ...[
                _buildMaterialsUsedCard(context, job, isDark),
                const SizedBox(height: 14),
              ],

              RadiusConnectionCard(
                accountName: _radiusAccountOf(job),
                subscriberName: job.customerName,
              ),
              const SizedBox(height: 14),

              // History and workflow notes last.
              _buildWorkflowCard(context, job, isDark),
              if (jobsSignals.timingHistory != null) ...[
                const SizedBox(height: 14),
                OrderTimingHistoryCard(
                  dao: jobsSignals.timingHistory,
                  orderType: WorkTimingEntry.orderTypeJobOrder,
                  orderId: job.id,
                  finishLabel: 'Finish',
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Name, where, how far, and the Navigate | Call pair (DESIGN.md, job
  /// detail). Navigate is ink so the sticky verb stays the screen's one red.
  Widget _buildHeader(BuildContext context, JobOrderDto job, bool isDark) {
    final place = [
      if (job.barangay?.isNotEmpty == true) job.barangay!,
      if (job.city?.isNotEmpty == true) job.city!,
    ].join(', ');
    final address = place.isEmpty ? job.address : '${job.address}, $place';
    final distance = distanceLabelFor(job);
    /*
    final hasPhone = job.contactNumber?.isNotEmpty == true;
    */
    // Gene - Oct 13, 2026: Commented out unused hasPhone variable since Call button in header was removed.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(job.customerName, style: context.text.headlineMedium),
        const SizedBox(height: 4),
        Text(
          address,
          style: context.text.bodyMedium!
              .copyWith(color: AppTheme.secondaryInkOf(context)),
        ),
        if (distance != null) ...[
          const SizedBox(height: 4),
          Text(
            distance,
            style: context.text.bodyLarge!
                .copyWith(color: AppTheme.secondaryInkOf(context)),
          ),
        ],
        /*
        const SizedBox(height: 14),
        ActionPair(
          primary: SizedBox(
            height: AppTheme.primaryButtonHeight,
            child: FilledButton.icon(
              onPressed: () => _openNavigation(job),
              icon: const Icon(Icons.navigation_rounded, size: 22),
              label: const Text('Navigate'),
            ),
          ),
          secondary: hasPhone
              ? SizedBox(
                  height: AppTheme.primaryButtonHeight,
                  child: OutlinedButton.icon(
                    onPressed: () => _promptContact(context, job.contactNumber!,
                        isCall: true, isDark: isDark),
                    icon: const Icon(Icons.call_rounded, size: 22),
                    label: const Text('Call'),
                  ),
                )
              : null,
        ),
        */
        // Gene - Oct 13, 2026: Removed Navigate and Call action buttons from Job Order details per user request.
      ],
    );
  }

  /// One mono line of plant ids: `LCP 173 · NAP 008 · PORT 05 · VLAN 0`.
  /// A zero or blank id reads "Unassigned"; it is never shown as "0".
  Widget _buildPlantLine(BuildContext context, JobOrderDto job) {
    // The server writes "0" for an id that is not assigned yet.
    String? clean(String? raw, String prefix) {
      final v = raw
          ?.trim()
          .replaceFirst(RegExp('^$prefix[- ]?', caseSensitive: false), '')
          .trim();
      if (v == null || v.isEmpty || v == '0') return null;
      return v;
    }

    final napValue = clean(job.nap, 'NAP') ??
        (job.napId != null && job.napId! > 0 ? '${job.napId}' : null);
/*
    final entries = <(String, String?)>[
      ('LCP', job.lcpId != null && job.lcpId! > 0 ? '${job.lcpId}' : null),
      ('NAP', napValue),
      ('PORT', clean(job.portId, 'PORT')),
      ('VLAN', job.vlanId != null && job.vlanId! > 0 ? '${job.vlanId}' : null),
    ];
*/
/*
    // Gene - Oct 13, 2026: Included CONNECTION in plant entries for job order details.
    final entries = <(String, String?)>[
      ('LCP', job.lcpId != null && job.lcpId! > 0 ? '${job.lcpId}' : null),
      ('NAP', napValue),
      ('PORT', clean(job.portId, 'PORT')),
      ('VLAN', job.vlanId != null && job.vlanId! > 0 ? '${job.vlanId}' : null),
      ('CONNECTION', job.connectionType.isNotEmpty ? job.connectionType : null),
    ];
*/
    // Gene - Oct 13, 2026: Included CONNECTION, VISIT BY, and VISIT WITH in plant entries for job order details.
    final entries = <(String, String?)>[
      ('LCP', job.lcpId != null && job.lcpId! > 0 ? '${job.lcpId}' : null),
      ('NAP', napValue),
      ('PORT', clean(job.portId, 'PORT')),
      ('VLAN', job.vlanId != null && job.vlanId! > 0 ? '${job.vlanId}' : null),
      ('CONNECTION', job.connectionType.isNotEmpty ? job.connectionType : null),
      (
        'VISIT BY',
        job.visitBy != 'None' && job.visitBy.isNotEmpty ? job.visitBy : null
      ),
      (
        'VISIT WITH',
        job.visitWith != 'None' && job.visitWith.isNotEmpty
            ? job.visitWith
            : null
      ),
    ];
    final secondary = AppTheme.secondaryInkOf(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PLANT',
                style: context.text.labelMedium!.copyWith(color: secondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final (key, value) in entries)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$key ',
                          style: context.text.labelMedium!
                              .copyWith(color: secondary),
                        ),
                        TextSpan(
                          text: value ?? 'Unassigned',
                          style: context.text.bodyLarge!.copyWith(
                            fontWeight: FontWeight.w500,
                            color: value == null ? secondary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            // Gene - Nov, 23, 2026: One-tap deep link from assigned NAP to its Plant pole details.
            if (lcpNapSignals != null)
              Builder(
                builder: (context) {
                  final matched = findMatchingNapLocation(
                    lcpNapSignals!.allLocations.value,
                    napId: job.napId,
                    napName: job.nap,
                    lcpId: job.lcpId,
                  );
                  if (matched == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('open_nap_pole_button'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LcpNapDetailScreen(
                                locationId: matched.id,
                                signals: lcpNapSignals!,
                                jobsSignals: jobsSignals,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.hub_outlined, size: 20),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Open ${matched.lcpNap} pole',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /*
  // Gene - Oct 12, 2026: Visual flow card showing the top-to-bottom installation answering sequence matching AppSheet.
  Widget _buildAnsweringFlowCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    const steps = [
      ('1', 'Optical Reading', 'Validate power level (-19.5 dBm target)'),
      ('2', 'Hardware & Port', 'LCP cabinet → NAP box → port → serial → ONT model'),
      ('3', 'Materials (BOM)', 'Drop cable length & connector counts'),
      ('4', 'Photo Proofs', '7 standard photo attachments'),
      ('5', 'Status Remarks', 'Office & field dispatch notes'),
      ('6', 'Sign-Off', 'Customer electronic signature'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.checklist_rtl_rounded,
                        size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Answering Flow',
                      style: context.text.titleMedium,
                    ),
                  ],
                ),
                // Gene - Oct 12, 2026: Changed action icon to standard 20px size floor.
                // Gene - Nov, 25, 2026: Gate Fill Report shortcut until Start is clicked and before Finish.
                if (!readOnly &&
                    job.isWorkUnlocked &&
                    job.siteException != SiteException.reschedule)
                  TextButton.icon(
                    onPressed: () => _handleOpenReport(context, job),
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                    label: const Text('Fill Report'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sequential steps to answer and complete this dispatch:',
              style: context.text.bodySmall!
                  .copyWith(color: AppTheme.secondaryInkOf(context)),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.primarySubtleBgOf(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary, width: 1.5),
                      ),
                      child: Center(
                        // Gene - Oct 12, 2026: Used theme labelSmall token without fontSize literal.
                        child: Text(
                          steps[i].$1,
                          style: context.text.labelSmall!.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            steps[i].$2,
                            style: context.text.titleSmall!.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // Gene - Oct 12, 2026: Used bodySmall token without fontSize literal.
                          Text(
                            steps[i].$3,
                            style: context.text.bodySmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Container(
                    width: 1.5,
                    height: 8,
                    color: AppTheme.hairlineOf(context),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
  */
  // Gene - Oct 13, 2026: Commented out _buildAnsweringFlowCard declaration since answering flow is removed from details per user request.

  /// Interactive Workflow Card showing stages and stage advancement
  Widget _buildWorkflowCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    final currentStatus = job.jobStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A Wrap, not a Row: at 200% text the label and the badge no
            // longer fit on one line, so the badge flows to its own line
            // instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Workflow Stage',
                  style: context.text.labelMedium!
                      .copyWith(color: AppTheme.secondaryInkOf(context)),
                ),
                StatusBadge(
                  status: currentStatus,
                  rawStatus: job.status,
                  siteException: job.siteException,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stepper Visualizer
            _buildStepper(context, job, isDark),
            const SizedBox(height: 16),

            // Who Dispatch assigned this job to
            _buildAssignmentRow(context, job, isDark),
            const SizedBox(height: 12),

            /*
            // Scheduled or Rescheduled, changed from a sheet. Finished jobs
            // and the history never offer it.
            if (!readOnly && job.canActivate) ...[
              _buildStatusRow(context, job),
              const SizedBox(height: 12),
            ],

            // The one field action: Scheduled -> Completed.
            if (readOnly)
              _buildViewOnlyNote(context, isDark)
            else if (job.canActivate) ...[
              if (!job.hasCompletedReport)
                _buildReportRequiredNote(context, isDark)
              else
                _buildReportReadyNote(context, isDark),
            ] else
              _buildActivatedNote(context, job, isDark),
            */
            // Gene - Oct 6, 2026: Keep status row visible for rescheduled jobs and show view-only note without offering reporting.
            if (!readOnly && (job.canActivate || job.isRescheduled)) ...[
              _buildStatusRow(context, job),
              const SizedBox(height: 12),
            ],

            if (job.isRescheduled)
              _buildRescheduledNote(context, isDark)
            else if (readOnly)
              _buildViewOnlyNote(context, isDark)
            else if (job.canActivate) ...[
              if (!job.hasCompletedReport)
                _buildReportRequiredNote(context, isDark)
              else
                _buildReportReadyNote(context, job, isDark),
            ] else
              _buildActivatedNote(context, job, isDark),
          ],
        ),
      ),
    );
  }

  /// The job's current stage with one visible Change button (DESIGN.md: no
  /// hidden gestures). The sheet it opens is the only place the technician
  /// can mark a job Rescheduled.
  Widget _buildStatusRow(BuildContext context, JobOrderDto job) {
/*
    final status =
        job.isRescheduled ? JobStatus.rescheduled : JobStatus.scheduled;
*/
    // Gene - Oct 12, 2026: Resolve current job status including In Progress.
    final status = job.isRescheduled
        ? JobStatus.rescheduled
        : (job.jobStatus ?? JobStatus.scheduled);
    final reason = job.isRescheduled ? job.statusRemarks?.trim() : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.event_repeat_rounded,
            size: 20, color: AppTheme.secondaryInkOf(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status', style: context.text.bodySmall),
              Text(
                reason == null || reason.isEmpty
                    ? status.label
                    : '${status.label} · $reason',
                style: context.text.titleSmall,
              ),
            ],
          ),
        ),
        /*
        TextButton.icon(
          key: const ValueKey('job_status_change'),
          onPressed: () => _handleChangeStatus(context, job),
          icon: const Icon(Icons.edit_calendar_rounded, size: 20),
          label: const Text('Change'),
        ),
        */
        // Gene - Oct 6, 2026: Lock status editing on rescheduled jobs by hiding the Change button.
        // Gene - Nov, 25, 2026: Also require active Start/Finish work unlock to change status.
        if (!readOnly && job.isWorkUnlocked)
          TextButton.icon(
            key: const ValueKey('job_status_change'),
            onPressed: () => _handleChangeStatus(context, job),
            icon: const Icon(Icons.edit_calendar_rounded, size: 20),
            label: const Text('Change'),
          ),
      ],
    );
  }

  Future<void> _handleChangeStatus(
      BuildContext context, JobOrderDto job) async {
    final messenger = ScaffoldMessenger.of(context);
    final change = await StatusChangeSheet.show(
      context,
      current: job.jobStatus ?? JobStatus.scheduled,
      currentRemarks: job.statusRemarks,
    );
    if (change == null) return;
    final unchanged = change.status == (job.jobStatus ?? JobStatus.scheduled) &&
        (change.statusRemarks ?? '') == (job.statusRemarks?.trim() ?? '');
    if (unchanged) return;

    await jobsSignals.repository.changeStatus(
      job.id,
      status: change.status,
      statusRemarks: change.statusRemarks,
    );
/*
    messenger.showSnackBar(SnackBar(
      content: Text(change.status == JobStatus.rescheduled
          ? 'Marked Rescheduled · ${change.statusRemarks}'
          : 'Back to Scheduled'),
    ));
*/
    // Gene - Oct 12, 2026: Added feedback message for In Progress status.
    messenger.showSnackBar(SnackBar(
      content: Text(change.status == JobStatus.rescheduled
          ? 'Marked Rescheduled · ${change.statusRemarks}'
          : (change.status == JobStatus.inProgress
              ? 'Marked In Progress'
              : 'Back to Scheduled')),
    ));
  }

  /// The technician email Dispatch assigned this job to. Emails run long, so
  /// unlike [_buildSpecRow] the value wraps rather than overflowing.
  Widget _buildAssignmentRow(
      BuildContext context, JobOrderDto job, bool isDark) {
    final email = job.assignedEmail?.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.person_pin_rounded,
            size: 20, color: AppTheme.secondaryInkOf(context)),
        const SizedBox(width: 8),
        Text('Assigned To', style: context.text.bodySmall),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            email.isEmpty ? 'Unassigned' : email,
            textAlign: TextAlign.right,
            style: context.text.titleSmall!.copyWith(
              color: email.isEmpty ? AppTheme.secondaryInkOf(context) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepper(BuildContext context, JobOrderDto job, bool isDark) {
    final status = job.jobStatus;
    final isFinished =
        status == JobStatus.activated || status == JobStatus.completed;
    final terminalLabel =
        status == JobStatus.activated ? 'Activated' : 'Completed';
    /*
    final steps = [
      {'label': 'Scheduled', 'active': true},
      {'label': terminalLabel, 'active': isFinished},
    ];
    */
    // Gene - Oct 3, 2026: Dynamic step 1 label based on job status so In Progress or Rescheduled jobs do not display hardcoded 'Scheduled'.
    final initialLabel = status == JobStatus.inProgress
        ? 'In Progress'
        : (status == JobStatus.rescheduled ? 'Rescheduled' : 'Scheduled');
    final steps = [
      {'label': initialLabel, 'active': true},
      {'label': terminalLabel, 'active': isFinished},
    ];

    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          final stepIndex = (index ~/ 2) + 1;
          final isPrevActive = steps[stepIndex - 1]['active'] as bool;
          final isNextActive = steps[stepIndex]['active'] as bool;
          return Expanded(
            child: Container(
              height: 3,
              color: isPrevActive && isNextActive
                  ? AppTheme.primary
                  : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
            ),
          );
        }

        final stepIndex = index ~/ 2;
        final step = steps[stepIndex];
        final isActive = step['active'] as bool;

        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary
                      : (isDark ? AppTheme.darkInput : AppTheme.lightBg),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primary
                        : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isActive
                      ? const Icon(Icons.check, size: 20, color: Colors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: context.text.labelMedium!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step['label'] as String,
                textAlign: TextAlign.center,
                style: isActive
                    ? context.text.labelMedium
                    : context.text.bodySmall,
              ),
            ],
          ),
        );
      }),
    );
  }

  /// A visit that did not go ahead: the job marked Rescheduled (with the
  /// reason from status remarks), or an on-site Failed / Reschedule outcome
  /// (with the technician's notes). Stays visible until the job is done.
  Widget _buildExceptionBanner(
      BuildContext context, JobOrderDto job, bool isDark) {
    final exception = job.siteException;
    final isReschedule =
        job.isRescheduled || exception == SiteException.reschedule;
    final title = job.isRescheduled
        ? 'Rescheduled'
        : 'Site Exception: ${exception!.label}';
    final detail = job.isRescheduled
        ? (job.statusRemarks?.trim().isNotEmpty == true
            ? job.statusRemarks!.trim()
            : null)
        : (job.onsiteRemarks?.trim().isNotEmpty == true
            ? job.onsiteRemarks!.trim()
            : null);
    final ink = isReschedule
        ? AppTheme.warningInkOf(context)
        : AppTheme.dangerInkOf(context);

    return Container(
      key: const ValueKey('job_exception_banner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? (isReschedule ? const Color(0xFF3B2506) : const Color(0xFF3B1215))
            : (isReschedule ? AppTheme.warningSubtle : AppTheme.dangerSubtle),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? (isReschedule
                  ? const Color(0xFF78350F)
                  : const Color(0xFF7F1D1D))
              : (isReschedule
                  ? const Color(0xFFFDE68A)
                  : const Color(0xFFFECACA)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isReschedule
                ? Icons.event_repeat_rounded
                : Icons.warning_amber_rounded,
            color: isReschedule ? AppTheme.warning : AppTheme.danger,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.titleSmall!.copyWith(color: ink),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: context.text.bodySmall!.copyWith(color: ink),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin_rounded,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Subscriber & Location',
                    style: context.text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Customer Name & Plan
            Text(
              job.customerName,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              job.planName ?? 'Fiber Plan',
              style: context.text.labelMedium!
                  .copyWith(color: AppTheme.brandInkOf(context)),
            ),
            const SizedBox(height: 12),

            // Address Detail
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${job.address}${job.barangay != null ? ', ${job.barangay}' : ''}${job.city != null ? ', ${job.city}' : ''}',
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
            // Phone and email in the open so the technician can read them
            // back to the subscriber or the office without opening a sheet.
            if (job.contactNumber?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.call_rounded,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        job.contactNumber!.trim(),
                        if (job.secondContactNumber != null)
                          job.secondContactNumber!,
                      ].join(' · '),
                      style: context.text.bodyLarge,
                    ),
                  ),
                ],
              ),
            ],
            if (job.subscriberEmail != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.alternate_email_rounded,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(job.subscriberEmail!,
                        style: context.text.bodyMedium),
                  ),
                ],
              ),
            ],
            // Gene - Oct 12, 2026: Added Landmark Notes and Installation Landmark preview matching AppSheet Job Order screenshots.
            if (job.landmarkRemarks != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.assistant_direction_rounded,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Landmark: ${job.landmarkRemarks}',
                      style: context.text.bodyMedium!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            /*
            if (job.installationLandmark != null &&
                job.installationLandmark!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildLandmarkPhotoPreview(
                  context, job.installationLandmark!, isDark),
            ],
            */
            // Gene - Oct 13, 2026: Display Front House Image in Job Order details.
            if (job.houseFront != null &&
                job.houseFront!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildLandmarkPhotoPreview(
                context,
                job.houseFront!,
                isDark,
                title: 'Front House Image',
                icon: CupertinoIcons.house_fill,
              ),
            ],
            // Gene - Oct 13, 2026: Display Installation Landmark photo if present and distinct from houseFront.
            if (job.installationLandmark != null &&
                job.installationLandmark!.trim().isNotEmpty &&
                job.installationLandmark != job.houseFront) ...[
              const SizedBox(height: 10),
              _buildLandmarkPhotoPreview(
                context,
                job.installationLandmark!,
                isDark,
                title: 'Installation Landmark',
                icon: Icons.photo_camera_outlined,
              ),
            ],
            const SizedBox(height: 14),
            Divider(
                height: 1,
                color: isDark ? AppTheme.borderDark : AppTheme.borderLight),
            const SizedBox(height: 12),

            // Contact Action Buttons (Call, SMS, Copy Address). Navigation
            // lives in the Service Location card below, so it is not repeated
            // here.
            Row(
              children: [
                // Call lives in the header pair; SMS and copy stay here.
                if (job.contactNumber != null &&
                    job.contactNumber!.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _promptContact(
                          context, job.contactNumber!,
                          isCall: false, job: job, isDark: isDark),
                      icon: const Icon(Icons.sms_outlined, size: 24),
                      label: const Text('SMS'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  tooltip: 'Copy Address',
                  icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 24),
                  onPressed: () => _copyAddress(context, job, isDark),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Gene - Oct 12, 2026: Added landmark photo preview matching AppSheet Job Order Installation Landmark per screenshot page 1 & 2.
  /*
  Widget _buildLandmarkPhotoPreview(
      BuildContext context, String landmark, bool isDark) {
  */
  // Gene - Oct 13, 2026: Added title and icon parameters to display Front House Image or Installation Landmark in details.
  Widget _buildLandmarkPhotoPreview(
      BuildContext context, String landmark, bool isDark,
      {String title = 'Installation Landmark',
      IconData icon = Icons.photo_camera_outlined}) {
    final clean = landmark.trim();
    final bytes = PhotoStorageService.instance.resolveBytes(clean) ??
        DataUrl.decode(clean);
    final isHttp = clean.startsWith('http://') || clean.startsWith('https://');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                /*
                const Icon(Icons.photo_camera_outlined,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Installation Landmark',
                  style: context.text.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                */
                // Gene - Oct 13, 2026: Render dynamic icon and title (e.g. Front House Image or Installation Landmark).
                Icon(icon, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: context.text.labelMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              if (bytes != null) {
                /*
                showPhotoViewer(context, bytes, title: 'Installation Landmark');
                */
                // Gene - Oct 13, 2026: Pass preview title to full-screen photo viewer.
                showPhotoViewer(context, bytes, title: title);
              } else if (isHttp) {
                launchUrl(Uri.parse(clean),
                    mode: LaunchMode.externalApplication);
              }
            },
            child: SizedBox(
              /*
              height: 160,
              */
              // Gene - Oct 13, 2026: Enlarged photo preview height from 160 to 240 for clearer inspection.
              height: 240,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bytes != null)
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                    )
                  else if (isHttp)
                    Image.network(
                      clean,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(CupertinoIcons.link,
                                size: 28, color: AppTheme.primary),
                            const SizedBox(height: 6),
                            Text(
                              'Tap to view cloud image',
                              style: context.text.labelSmall!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Text(
                        clean,
                        style: context.text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.zoom_in,
                              size: 20, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Pinch / Zoom',
                            style: context.text.labelSmall!.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /*
  // Gene - Oct 13, 2026: Resolves Job Order coordinates falling back to assigned NAP site or service center so map pin is always shown.
  LatLng _resolveCoordinates(JobOrderDto job) {
    if (job.latLng != null) return job.latLng!;
    if (lcpNapSignals != null) {
      final naps = lcpNapSignals!.allLocations.value;
      if (job.napId != null) {
        for (final n in naps) {
          if (n.id == job.napId && n.latLng != null) {
            return n.latLng!;
          }
        }
      }
      final rawNap = job.nap?.trim();
      if (rawNap != null && rawNap.isNotEmpty && rawNap != '0') {
        for (final n in naps) {
          if (n.lcpNap.trim().toLowerCase() == rawNap.toLowerCase() &&
              n.latLng != null) {
            return n.latLng!;
          }
        }
      }
    }
    return const LatLng(14.5862, 121.0618);
  }
  // Gene - Oct 13, 2026: Strict Job Order coordinate resolution returning only the actual job latLng without NAP or service area fallbacks.
  LatLng? _resolveCoordinates(JobOrderDto job) => job.latLng;
  */

  /*
  Widget _buildLocationAndGpsCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    final latLng = job.latLng;
    final dms = latLng != null
        ? LocationService.instance.formatDms(latLng.latitude, latLng.longitude)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.location_circle_fill,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Service Location & GPS Coordinates',
                    style: context.text.titleMedium,
                  ),
                ),
                if (latLng != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'GPS Fixed',
                      style: context.text.labelMedium!
                          .copyWith(color: AppTheme.successInkOf(context)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Gene - Oct 13, 2026: Show interactive map location preview of the Job Order based on lat/lng coordinates.
            if (latLng != null) ...[
              _JobMapLocationPreview(
                latLng: latLng,
                label: job.customerName,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
            ],
            _buildSpecRow(
              context,
              'Coordinates',
              dms ?? 'Derived from service area',
              CupertinoIcons.location_solid,
              isDark,
            ),
            if (latLng != null)
              _buildSpecRow(
                context,
                'Decimal Lat/Lng',
                '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}',
                CupertinoIcons.map_pin_ellipse,
                isDark,
              ),
            // The GPS fix is owned by a widget that asks for it once. Building
            // the future inline here restarted a 4-second high-accuracy fix on
            // every rebuild of this screen, and there is nothing to measure
            // against when the job carries no coordinates.
            if (latLng != null)
              _DistanceFromTechnicianRow(target: latLng, isDark: isDark),
  */
  /*
  // Gene - Oct 13, 2026: Guaranteed map and location pin rendering for Job Order using resolved lat/long coordinates.
  Widget _buildLocationAndGpsCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    final latLng = _resolveCoordinates(job);
    final hasRealGps = job.latLng != null;
    final dms =
        LocationService.instance.formatDms(latLng.latitude, latLng.longitude);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.location_circle_fill,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Service Location & GPS Coordinates',
                    style: context.text.titleMedium,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (hasRealGps ? AppTheme.success : AppTheme.primary)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    hasRealGps ? 'GPS Fixed' : 'Service Area',
                    style: context.text.labelMedium!.copyWith(
                      color: hasRealGps
                          ? AppTheme.successInkOf(context)
                          : AppTheme.brandInkOf(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _JobMapLocationPreview(
              latLng: latLng,
              label: job.customerName,
              isDark: isDark,
            ),
            const SizedBox(height: 14),
            _buildSpecRow(
              context,
              'Coordinates',
              dms,
              CupertinoIcons.location_solid,
              isDark,
            ),
            _buildSpecRow(
              context,
              'Decimal Lat/Lng',
              '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}',
              CupertinoIcons.map_pin_ellipse,
              isDark,
            ),
            _DistanceFromTechnicianRow(target: latLng, isDark: isDark),
            // Navigation itself lives in the header pair; this card keeps
            // the coordinates and the nearest NAP pole.
            // Nearest LCP NAP Pole Details & Navigation
            () {
              final nearestNapInfo = _findNearestNap(job);
              if (nearestNapInfo == null) return const SizedBox.shrink();

              return Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF064E3B).withValues(alpha: 0.35)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : const Color(0xFFA7F3D0),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.hub_rounded,
                                size: 20, color: Color(0xFF10B981)),
                            const SizedBox(width: 6),
                            Text(
                              'Nearest LCP NAP Pole',
                              style: context.text.labelMedium!.copyWith(
                                color: isDark
                                    ? const Color(0xFF6EE7B7)
                                    : const Color(0xFF047857),
                              ),
                            ),
                            const Spacer(),
                            if (nearestNapInfo.distanceMeters > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${LocationService.instance.formatDistance(nearestNapInfo.distanceMeters)} away',
                                  style: context.text.labelMedium!
                                      .copyWith(color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          nearestNapInfo.nap.lcpNap,
                          style: context.text.titleSmall,
                        ),
                        if (nearestNapInfo.nap.street?.isNotEmpty == true ||
                            nearestNapInfo.nap.barangay?.isNotEmpty ==
                                true) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (nearestNapInfo.nap.street?.isNotEmpty == true)
                                nearestNapInfo.nap.street,
                              if (nearestNapInfo.nap.barangay?.isNotEmpty ==
                                  true)
                                nearestNapInfo.nap.barangay,
                            ].join(', '),
                            style: context.text.bodySmall,
                          ),
                        ],
                        if (nearestNapInfo.nap.latLng != null) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                    color: Color(0xFF10B981), width: 1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                              icon: const Icon(
                                  CupertinoIcons.arrow_turn_up_right,
                                  size: 24,
                                  color: Color(0xFF10B981)),
                              label: Text(
                                'Directions to NAP Pole',
                                style: context.text.labelLarge!
                                    .copyWith(color: const Color(0xFF10B981)),
                              ),
                              onPressed: () {
                                final p = nearestNapInfo.nap.latLng!;
                                MapNavigationService.navigateToCoordinates(
                                  latitude: p.latitude,
                                  longitude: p.longitude,
                                  destinationLabel: 'NAP pole',
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }(),
          ],
        ),
      ),
    );
  }
  */
  // Gene - Oct 13, 2026: Only show the location of the Job Order lat long on the map. If coordinates are missing, omit map preview and display clean No GPS indicator without NAP or Manila fallback.
  Widget _buildLocationAndGpsCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    final latLng = job.latLng;
    final dms = latLng != null
        ? LocationService.instance.formatDms(latLng.latitude, latLng.longitude)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.location_circle_fill,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Service Location & GPS Coordinates',
                    style: context.text.titleMedium,
                  ),
                ),
                if (latLng != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'GPS Fixed',
                      style: context.text.labelMedium!.copyWith(
                        color: AppTheme.successInkOf(context),
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'No GPS',
                      style: context.text.labelMedium!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (latLng != null) ...[
              _JobMapLocationPreview(
                latLng: latLng,
                label: job.customerName,
                isDark: isDark,
              ),
              const SizedBox(height: 14),
              _buildSpecRow(
                context,
                'Coordinates',
                dms!,
                CupertinoIcons.location_solid,
                isDark,
              ),
              _buildSpecRow(
                context,
                'Decimal Lat/Lng',
                '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}',
                CupertinoIcons.map_pin_ellipse,
                isDark,
              ),
              _DistanceFromTechnicianRow(target: latLng, isDark: isDark),
            ] else ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(CupertinoIcons.location_slash,
                        size: 32, color: AppTheme.secondaryInkOf(context)),
                    const SizedBox(height: 8),
                    Text(
                      'No GPS location recorded for this job order',
                      style: context.text.bodyMedium!.copyWith(
                        color: AppTheme.secondaryInkOf(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSpecRow(
                context,
                'Coordinates',
                'Not recorded',
                CupertinoIcons.location_solid,
                isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /*
  // Gene - Oct 13, 2026: Commented out unused _findNearestNap as NAP details were decoupled from the Job Order location card.
  ({LcpNapDto nap, double distanceMeters})? _findNearestNap(JobOrderDto job) {
    if (lcpNapSignals == null) return null;
    final naps = lcpNapSignals!.allLocations.value;
    if (naps.isEmpty) return null;

    final targetPos = job.latLng;
    if (targetPos != null) {
      double minD = double.infinity;
      LcpNapDto? nearest;
      for (final n in naps) {
        if (n.latLng == null) continue;
        final d = LocationService.instance.distanceBetween(
          startLat: targetPos.latitude,
          startLng: targetPos.longitude,
          endLat: n.latLng!.latitude,
          endLng: n.latLng!.longitude,
        );
        if (d < minD) {
          minD = d;
          nearest = n;
        }
      }
      if (nearest != null && minD.isFinite) {
        return (nap: nearest, distanceMeters: minD);
      }
    }

    if (job.napId != null) {
      for (final n in naps) {
        if (n.id == job.napId) {
          return (nap: n, distanceMeters: 0.0);
        }
      }
    }

    return null;
  }
  */

  Future<void> _openNavigation(JobOrderDto job) async {
    final latLng = job.latLng;
    if (latLng != null) {
      await MapNavigationService.navigateToCoordinates(
        latitude: latLng.latitude,
        longitude: latLng.longitude,
        destinationLabel: job.customerName,
      );
      return;
    }
    final fullAddr =
        '${job.address}${job.barangay != null ? ", ${job.barangay}" : ""}${job.city != null ? ", ${job.city}" : ""}, Philippines';
    await MapNavigationService.navigateToAddress(fullAddr);
  }

  Widget _buildPlantAndHardwareCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final muted = AppTheme.secondaryInkOf(context);
    // A zero id is the server's "not assigned yet", never a cabinet.
    final lcpText =
        job.lcpId != null && job.lcpId! > 0 ? 'LCP-${job.lcpId}' : 'Unassigned';
    // The server also writes the string "0" for an unassigned NAP or port.
    final rawNap = job.nap?.trim() ?? '';
    final napText = rawNap.isNotEmpty && rawNap != '0'
        ? rawNap
        : (job.napId != null && job.napId! > 0
            ? 'NAP-${job.napId}'
            : 'Unassigned');
    final rawPort = job.portId?.trim() ?? '';
    final portText =
        rawPort.isNotEmpty && rawPort != '0' ? rawPort : 'Unassigned';
    final ontText = job.routerModel?.isNotEmpty == true
        ? job.routerModel!
        : (job.modemRouterSN?.isNotEmpty == true
            ? job.modemRouterSN!
            : 'Pending Installation');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Plant & Hardware Allocation',
                    style: context.text.titleMedium,
                  ),
                ),
                if (job.vlanId != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.5),
                    ),
                    child: Text(
                      'VLAN ${job.vlanId}',
                      style: context.text.labelMedium!.copyWith(
                        fontFamily: 'JetBrains Mono',
                        color: AppTheme.infoInkOf(context),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Modern 2x2 Instrument Grid Partitioned by Hairlines
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.5),
                color:
                    isDark ? const Color(0xFF14171F) : const Color(0xFFF8FAFC),
              ),
              child: Column(
                children: [
                  // Row 1: LCP & NAP
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.storage_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'LCP CABINET',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          letterSpacing: 0.5,
                                          fontWeight: FontWeight.w600,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lcpText,
                                  style: context.text.titleSmall!.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(
                          width: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.hub_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'NAP BOX',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          letterSpacing: 0.5,
                                          fontWeight: FontWeight.w600,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  napText,
                                  style: context.text.titleSmall!.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 0.5, thickness: 0.5, color: borderColor),

                  // Row 2: Port Assignment & ONT Model/SN
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.electrical_services_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'PORT',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          letterSpacing: 0.5,
                                          fontWeight: FontWeight.w600,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  portText,
                                  style: context.text.titleSmall!.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(
                          width: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.devices_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'ONT / MODEM',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          letterSpacing: 0.5,
                                          fontWeight: FontWeight.w600,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ontText,
                                  style: context.text.titleSmall!.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (job.modemRouterSN?.isNotEmpty == true &&
                                    job.modemRouterSN != ontText) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'SN: ${job.modemRouterSN!}',
                                    style: context.text.bodySmall!.copyWith(
                                      fontFamily: 'JetBrains Mono',
                                      color: muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialsUsedCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Materials Used (BOM)',
                      style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...job.materialsUsed.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key, style: context.text.bodyMedium),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${e.value}',
                        style: context.text.labelMedium!.copyWith(
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildOpticalPowerCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    final dbm = job.opticalPower!;
    final isOptimal = dbm >= AppConstants.opticalMinOptimal &&
        dbm <= AppConstants.opticalMaxOptimal;
    final isMarginal = dbm >= AppConstants.opticalMarginalFloor &&
        dbm < AppConstants.opticalMinOptimal;

    final badgeColor = isOptimal
        ? AppTheme.success
        : isMarginal
            ? AppTheme.warning
            : AppTheme.danger;

    // The reading's own colour, but pulled from the ink palette since it
    // sits on Text rather than a fill.
    final badgeColorInk = isOptimal
        ? AppTheme.successInkOf(context)
        : isMarginal
            ? AppTheme.warningInkOf(context)
            : AppTheme.dangerInkOf(context);

    final badgeSubtle = isDark
        ? badgeColor.withValues(alpha: 0.2)
        : (isOptimal
            ? AppTheme.successSubtle
            : isMarginal
                ? AppTheme.warningSubtle
                : AppTheme.dangerSubtle);

    final badgeLabel = isOptimal
        ? 'Optimal (Pass)'
        : isMarginal
            ? 'Marginal (Acceptable)'
            : 'Out of Spec (Faulty)';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Optical Power Measurement',
                    style: context.text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: badgeSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  // The reading and its standard line take the width the
                  // verdict badge leaves; with no flex factor the row
                  // overflowed by 37px on a phone.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${dbm.toStringAsFixed(1)} dBm',
                          style: context.text.headlineSmall!.copyWith(
                            fontFamily: 'JetBrains Mono',
                            fontWeight: FontWeight.bold,
                            color: badgeColorInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Standard: -12.0 dBm to -24.0 dBm',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeLabel,
                      style: context.text.labelMedium!
                          .copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /*
  Widget _buildOnsiteRecordsCard(
      BuildContext context, JobOrderDto job, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_turned_in_outlined,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'On-Site Records & Verification',
                    style: context.text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (job.onsiteRemarks != null && job.onsiteRemarks!.isNotEmpty) ...[
              Text(
                'Technician Notes:',
                style: context.text.labelMedium!
                    .copyWith(color: AppTheme.secondaryInkOf(context)),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  job.onsiteRemarks!,
                  style: context.text.bodyMedium,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Photo proofs and signature, tap to zoom
            Text(
              'Photo Proofs:',
              style: context.text.labelMedium!
                  .copyWith(color: AppTheme.secondaryInkOf(context)),
            ),
            const SizedBox(height: 6),
            JobPhotoGallery(job: job),
            // The report is opened from the sticky verb below, and only
            // from there: one action, one place.
          ],
        ),
      ),
    );
  }
  */
  // Gene - Oct 13, 2026: Commented out _buildOnsiteRecordsCard as on-site records verification was removed from details per user request.

  static Widget _buildSpecRow(BuildContext context, String label, String value,
      IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.secondaryInkOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: context.text.bodySmall,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: context.text.titleSmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the report on top of this screen.
  ///
  /// This used to pop the detail screen first, which left the report sitting
  /// directly on the job list: backing out of it landed the technician on the
  /// main screen instead of the job they were working.
  /*
  void _handleOpenReport(BuildContext context, JobOrderDto job) {
    if (onOpenReport != null) {
      onOpenReport!(job);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: ReportSignals()..setJobOrder(job),
          onReportSubmitted: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
  */
  // Gene - Oct 13, 2026: Guarded _handleOpenReport so rescheduled jobs cannot open report screen or modify records.
  // Gene - Nov, 26, 2026: Also require job.isWorkUnlocked (started and not finished) before opening report.
  void _handleOpenReport(BuildContext context, JobOrderDto job) {
    // Gene - Nov 07, 2026: Wrapped single-line if statement in curly braces for linter compliance (curly_braces_in_flow_control_structures).
    // if (job.isRescheduled || job.siteException == SiteException.reschedule)
    //   return;
    /*
    if (job.isRescheduled || job.siteException == SiteException.reschedule) {
      return;
    }
    */
    if (!job.isWorkUnlocked ||
        job.isRescheduled ||
        job.siteException == SiteException.reschedule) {
      return;
    }
    if (onOpenReport != null) {
      onOpenReport!(job);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          jobsSignals: jobsSignals,
          reportSignals: ReportSignals()..setJobOrder(job),
          onReportSubmitted: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  /// Informs the technician that a completion report is needed before finalizing.
  Widget _buildReportRequiredNote(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: AppTheme.info),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Step 1 of 2: Completion report required. Tap "Fill Completion '
              'Report" below to record modem serial and subscriber signature.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /*
  /// Informs the technician that the report is complete and ready to finalize.
  Widget _buildReportReadyNote(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.success.withValues(alpha: 0.15)
            : AppTheme.successSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppTheme.success.withValues(alpha: 0.3)
              : const Color(0xFFBBF7D0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 20, color: AppTheme.successInkOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Step 2 of 2: Completion report filed. Tap "Mark as Completed" '
              'below to finalize and sync order.',
              style: context.text.bodySmall!.copyWith(
                color: AppTheme.successInkOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
  */
  // Gene - Nov, 23, 2026: Aligned CTA label copy ("Complete job") and added Edit completion report button when report is already filed.
  Widget _buildReportReadyNote(
      BuildContext context, JobOrderDto job, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.success.withValues(alpha: 0.15)
            : AppTheme.successSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? AppTheme.success.withValues(alpha: 0.3)
              : const Color(0xFFBBF7D0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 20, color: AppTheme.successInkOf(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Step 2 of 2: Completion report filed. Tap "Complete job" '
                  'below to finalize and sync order.',
                  style: context.text.bodySmall!.copyWith(
                    color: AppTheme.successInkOf(context),
                  ),
                ),
              ),
            ],
          ),
          // Gene - Nov, 25, 2026: Require active Start/Finish work unlock to edit a filed completion report.
          if (!readOnly &&
              job.isWorkUnlocked &&
              job.siteException != SiteException.reschedule) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('edit_completion_report_button'),
                onPressed: () => _handleOpenReport(context, job),
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: const Text('Edit completion report'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A read-only banner for the history: the record can be inspected but not
  /// changed from here.
  Widget _buildViewOnlyNote(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 20, color: AppTheme.secondaryInkOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'View only. This job is in your history and cannot be changed.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  // Gene - Oct 6, 2026: Notice explaining that a rescheduled job is view-only and cannot be reported on or completed.
  Widget _buildRescheduledNote(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3B2506) : AppTheme.warningSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.event_repeat_rounded,
              size: 20, color: AppTheme.warningInkOf(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'View only. This job order is rescheduled and cannot be completed or reported on.',
              style: context.text.bodySmall!.copyWith(
                color: AppTheme.warningInkOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivatedNote(
      BuildContext context, JobOrderDto job, bool isDark) {
    final when = job.dateInstalled;
    final prefix = job.isCompleted ? 'Completed' : 'Activated';
    final label = when == null
        ? prefix
        : '$prefix on ${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF059669).withValues(alpha: 0.2)
            : AppTheme.successSubtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? const Color(0xFF059669).withValues(alpha: 0.4)
              : const Color(0xFFBBF7D0),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded,
              size: 20,
              color: isDark ? const Color(0xFF4ADE80) : AppTheme.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: context.text.labelMedium!
                  .copyWith(color: AppTheme.successInkOf(context)),
            ),
          ),
        ],
      ),
    );
  }

  /// Confirm, then complete. Completion is terminal and moves the job into
  /// history, so it deserves a second look.
  Future<void> _handleComplete(
      BuildContext context, JobOrderDto job, bool isDark) async {
    // Gene - Nov, 26, 2026: Prevent completing a job order unless it is actively started (unlocked).
    if (!job.isWorkUnlocked) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Mark as Completed?',
      message: '${job.ticketNumber} for ${job.customerName} will be marked '
          'Completed and moved to your job history. This cannot be undone '
          'from the app.',
      confirmLabel: 'Complete',
    );
    if (confirmed != true) return;

    final result = await jobsSignals.completeJob(job);
    if (!context.mounted) return;

    // The completion is written locally first and only then pushed. Reporting
    // success off the local write alone told technicians the office had the
    // job when the server had refused it, and the job sat on "needs to sync"
    // with nothing anywhere saying why.
    final reachedServer = result == null || result.success;
    final detail = result?.failures.isNotEmpty == true
        ? result!.failures.first
        : result?.message;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reachedServer
            ? '${job.ticketNumber} marked as completed. It now appears in History.'
            : '${job.ticketNumber} is saved on this phone but the office has '
                'not accepted it yet. It will retry.'
                '${detail == null ? '' : '\n$detail'}'),
        backgroundColor: reachedServer
            ? (isDark ? AppTheme.darkCard : AppTheme.darkSlate)
            : AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: reachedServer ? 4 : 10),
      ),
    );
  }

  void _copyJobSummary(BuildContext context, JobOrderDto job, bool isDark) {
    final text = 'Switch Fiber JO: ${job.ticketNumber}\n'
        'Customer: ${job.customerName}\n'
        'Plan: ${job.planName ?? "Fiber"}\n'
        'Address: ${job.address}, ${job.barangay ?? ""}\n'
        'Contact: ${job.contactNumber ?? "N/A"}\n'
        'Status: ${job.status}';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ticket summary copied to clipboard!'),
        backgroundColor: isDark ? AppTheme.darkCard : AppTheme.darkSlate,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyAddress(BuildContext context, JobOrderDto job, bool isDark) {
    final addr =
        '${job.address}${job.barangay != null ? ', ${job.barangay}' : ''}${job.city != null ? ', ${job.city}' : ''}';

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        // Clear the system navigation bar, which otherwise covers the last
        // row of the sheet.
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: AppTheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Customer Location & Navigation',
                      style: ctx.text.titleMedium,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 24),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              addr,
              style: ctx.text.titleSmall,
            ),
            const SizedBox(height: 16),

            // Start Navigation
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A73E8).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded,
                    color: Color(0xFF1A73E8), size: 24),
              ),
              title: Text('Start Navigation', style: ctx.text.titleSmall),
              subtitle: Text(
                'Driving directions in Google Maps or your map app',
                style: ctx.text.bodySmall,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onTap: () async {
                Navigator.pop(ctx);
                await _openNavigation(job);
              },
            ),
            const SizedBox(height: 6),

            // Copy Address
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primarySubtleBgOf(ctx),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.copy_rounded,
                    color: AppTheme.primary, size: 24),
              ),
              title:
                  Text('Copy Address to Clipboard', style: ctx.text.titleSmall),
              subtitle: Text(
                'Copy complete subscriber address text',
                style: ctx.text.bodySmall,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: addr));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Address copied: $addr'),
                    backgroundColor:
                        isDark ? AppTheme.darkCard : AppTheme.darkSlate,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _promptContact(
    BuildContext context,
    String phone, {
    required bool isCall,
    JobOrderDto? job,
    required bool isDark,
  }) {
    // SMS opens its own sheet so the technician can edit the message before
    // it reaches the phone's messaging app. The suggested wording is a
    // starting point, not a script: a subscriber who is already waiting, or
    // a job running late, needs different words.
    if (!isCall && job != null) {
      _composeSms(context, phone, job, isDark);
      return;
    }

    showAdaptiveActionSheet(
      context,
      title: 'Call Subscriber',
      message: phone,
      actions: [
        AdaptiveSheetAction(
          label: 'Dial Now',
          icon: Icons.call_rounded,
          isDefault: true,
          onPressed: () => _launchContactUri(
              context, Uri(scheme: 'tel', path: phone),
              failure: 'Could not open the dialer for $phone.'),
        ),
        AdaptiveSheetAction(
          label: 'Copy Number',
          icon: Icons.copy_rounded,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: phone));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Phone number copied to clipboard!'),
                behavior: SnackBarBehavior.floating,
                backgroundColor:
                    isDark ? AppTheme.darkCard : AppTheme.darkSlate,
              ),
            );
          },
        ),
      ],
    );
  }

  /// The wording offered when texting a subscriber about an arrival.
  ///
  /// Public so the sheet's starting text can be asserted in a test without
  /// pumping the whole detail screen.
  static String smsTemplate(JobOrderDto job) => smsTemplateFor(job);

  /// Opens the phone's messaging app with [body] already filled in.
  void _composeSms(
      BuildContext context, String phone, JobOrderDto job, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SmsComposeSheet(
        phone: phone,
        initialMessage: smsTemplate(job),
        isDark: isDark,
        onSend: (message) {
          Navigator.pop(ctx);
          _launchContactUri(
            context,
            // `body` as a query parameter is what both iOS Messages and
            // Android SMS apps read; Uri's own encoding handles the newlines
            // and punctuation a technician may type.
            Uri(scheme: 'sms', path: phone, queryParameters: {'body': message}),
            failure: 'Could not open the messaging app for $phone.',
          );
        },
      ),
    );
  }

  /// Hands [uri] to the phone and says so plainly when the phone refuses.
  ///
  /// The previous version only showed a snackbar claiming the call or message
  /// had been opened, so a technician standing at a pole believed a
  /// subscriber had been contacted when nothing had happened.
  Future<void> _launchContactUri(BuildContext context, Uri uri,
      {required String failure}) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(failure),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.danger,
      ),
    );
  }

/*
  String _radiusAccountOf(JobOrderDto job) {
    if (job.rawJson != null) {
      try {
        final map = jsonDecode(job.rawJson!);
        if (map is Map<String, dynamic>) {
          final u = map['username']?.toString().trim();
          if (u != null && u.isNotEmpty && u.toLowerCase() != 'switch') {
            return u;
          }
          final acc = map['accountNumber']?.toString().trim();
          if (acc != null && acc.isNotEmpty) return acc;
        }
      } catch (_) {}
    }
    return job.ticketNumber;
  }
*/
  // Gene - Oct 13, 2026: Replaced duplicated radius account logic with unified job.radiusUsername getter.
  String _radiusAccountOf(JobOrderDto job) => job.radiusUsername;
}

// Gene - Oct 13, 2026: Visual map location preview for Job Order based on lat/long coordinates.
class _JobMapLocationPreview extends StatefulWidget {
  final LatLng latLng;
  final String label;
  final bool isDark;

  const _JobMapLocationPreview({
    required this.latLng,
    required this.label,
    required this.isDark,
  });

  @override
  State<_JobMapLocationPreview> createState() => _JobMapLocationPreviewState();
}

class _JobMapLocationPreviewState extends State<_JobMapLocationPreview> {
  TileProvider? _tiles;

  @override
  void initState() {
    super.initState();
    _loadTiles();
  }

  Future<void> _loadTiles() async {
    try {
      final provider = await MapTiles.provider();
      if (mounted) setState(() => _tiles = provider);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.isDark ? AppTheme.darkInput : AppTheme.lightBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.latLng,
              initialZoom: 16.5,
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              /*
              TileLayer(
                urlTemplate: MapTiles.streetUrl,
                maxZoom: MapTiles.streetMaxZoom,
                userAgentPackageName: MapTiles.userAgentPackageName,
                tileProvider: _tiles,
              ),
              */
              // Gene - Oct 13, 2026: Render TileLayer only when cached provider is ready, preventing unmocked path_provider fallback crashes.
              if (_tiles != null)
                /*
                TileLayer(
                  urlTemplate: MapTiles.streetUrl,
                  maxZoom: MapTiles.streetMaxZoom,
                  userAgentPackageName: MapTiles.userAgentPackageName,
                  tileProvider: _tiles,
                ),
                */
                // Gene - Nov, 11, 2026: Pass maxNativeZoom alongside maxZoom on job detail mini-map TileLayer.
                TileLayer(
                  urlTemplate: MapTiles.streetUrl,
                  maxNativeZoom: MapTiles.streetMaxNativeZoom,
                  maxZoom: MapTiles.streetMaxZoom,
                  userAgentPackageName: MapTiles.userAgentPackageName,
                  tileProvider: _tiles,
                ),
              /*
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.latLng,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.home_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              */
              // Gene - Oct 13, 2026: Render prominent red location pin marker for the Job Order coordinates.
              MarkerLayer(
                markers: [
                  Marker(
                    point: widget.latLng,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.location_on_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Gene - Oct 13, 2026: Added location coordinates overlay chip on map.
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pin_drop_rounded,
                      size: 20, color: Color(0xFFF43F5E)),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.latLng.latitude.toStringAsFixed(5)}, ${widget.latLng.longitude.toStringAsFixed(5)}',
                    style: context.text.labelSmall!.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.zoom_in,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'Pinch to Zoom',
                    style: context.text.labelSmall!.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          /*
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  MapNavigationService.navigateTo(
                    widget.latLng,
                    label: widget.label,
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.navigation_rounded,
                          size: 16 /* map furniture */, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Navigate',
                        style: context.text.labelSmall!.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          */
          // Gene - Oct 13, 2026: Removed Navigate button overlay on map in Job Order details per user request.
        ],
      ),
    );
  }
}

/// The straight-line distance between the technician and the job's coordinates.
///
/// The position request is made once, in [initState], rather than in `build`:
/// a future created during build is re-issued on every rebuild, which turned
/// each repaint of the details screen into a fresh high-accuracy GPS fix.
class _DistanceFromTechnicianRow extends StatefulWidget {
  final LatLng target;
  final bool isDark;

  const _DistanceFromTechnicianRow({
    required this.target,
    required this.isDark,
  });

  @override
  State<_DistanceFromTechnicianRow> createState() =>
      _DistanceFromTechnicianRowState();
}

class _DistanceFromTechnicianRowState
    extends State<_DistanceFromTechnicianRow> {
  late final Future<String?> _distance = _measure();

  Future<String?> _measure() async {
    final here = await LocationService.instance.getCurrentPosition();
    if (here == null) return null;
    final meters = LocationService.instance.distanceBetween(
      startLat: here.latitude,
      startLng: here.longitude,
      endLat: widget.target.latitude,
      endLng: widget.target.longitude,
    );
    return LocationService.instance.formatDistance(meters);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _distance,
      builder: (context, snapshot) {
        final distance = snapshot.data;
        if (distance == null) return const SizedBox.shrink();
        return JobOrderDetailScreen._buildSpecRow(
          context,
          'Distance from You',
          distance,
          CupertinoIcons.arrow_up_right_diamond_fill,
          widget.isDark,
        );
      },
    );
  }
}

/// An editable SMS draft, shown before the phone's messaging app opens.
///
/// Stateful because the draft belongs to the sheet: the technician edits it,
/// and only the final text is handed to the phone.
class _SmsComposeSheet extends StatefulWidget {
  final String phone;
  final String initialMessage;
  final bool isDark;
  final ValueChanged<String> onSend;

  const _SmsComposeSheet({
    required this.phone,
    required this.initialMessage,
    required this.isDark,
    required this.onSend,
  });

  @override
  State<_SmsComposeSheet> createState() => _SmsComposeSheetState();
}

class _SmsComposeSheetState extends State<_SmsComposeSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialMessage);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      // viewInsets lifts the sheet above the keyboard while it is open;
      // padding.bottom clears the system navigation bar once it closes.
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 20 + media.padding.bottom + media.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_outlined, size: 24, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text('Message Subscriber', style: context.text.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'To ${widget.phone}',
            style: context.text.bodySmall!
                .copyWith(color: AppTheme.secondaryInkOf(context)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: context.text.bodyMedium,
            decoration: const InputDecoration(
              hintText: 'Type the message to send',
            ),
          ),
          const SizedBox(height: 8),
          // Restores the suggested wording after an edit, so a technician who
          // types over it can get back without retyping or cancelling.
          Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => TextButton.icon(
                onPressed: value.text.trim() == widget.initialMessage.trim()
                    ? null
                    : () {
                        _controller.text = widget.initialMessage;
                        _controller.selection = TextSelection.collapsed(
                            offset: _controller.text.length);
                      },
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Reset to suggested'),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => ElevatedButton.icon(
                    // An empty draft would open the messaging app with
                    // nothing to send, so the button waits for real text.
                    onPressed: value.text.trim().isEmpty
                        ? null
                        : () => widget.onSend(value.text.trim()),
                    icon: const Icon(Icons.send_rounded, size: 20),
                    label: const Text('Send'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
