import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' show SyncStatus;
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/models/sync_error_log.dart';
import '../../../core/network/api_client.dart';
// Gene - Nov, 23, 2026: Added LocationService and MapTiles imports for offline map tile cache management.
import '../../../core/services/location_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/server_display.dart';
import '../../../core/widgets/adaptive_dialogs.dart';
import '../../../core/sync/powersync_service.dart';
import '../../auth/signals/auth_signals.dart';
import '../signals/settings_signals.dart';
import '../../diagnostics/screens/sync_error_log_screen.dart';
// Gene - Nov, 26, 2026: Added WorkTimingHistoryScreen import for Start/Finish/Stop timing history access in Settings.
import '../../diagnostics/screens/work_timing_history_screen.dart';
import '../../jobs/signals/jobs_signals.dart';
import '../../lcp_nap/services/map_tiles.dart';
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../../service_orders/signals/service_orders_signals.dart';

/// Settings & Technician Terminal Diagnostics screen.
class SettingsScreen extends StatefulWidget {
  final AuthSignals authSignals;
  final JobsSignals jobsSignals;
  // Gene - Nov, 23, 2026: Optional ServiceOrdersSignals and LcpNapSignals for combined queue visibility, Sync Now, per-item retry, and logout safety.
  final ServiceOrdersSignals? serviceOrdersSignals;
  final LcpNapSignals? lcpNapSignals;

  const SettingsScreen({
    super.key,
    required this.authSignals,
    required this.jobsSignals,
    this.serviceOrdersSignals,
    this.lcpNapSignals,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _baseUrl = AppConstants.defaultBaseUrl;
  final _storage = SecureStorageService.instance;

  bool _isTestingPing = false;
  int? _lastPingMs;
  bool? _pingSuccess;
  // Gene - Nov, 23, 2026: Track manual Sync Now execution state and offline map tile cache status.
  bool _isSyncingAll = false;
  int _crudPendingCount = 0;
  StreamSubscription<SyncStatus>? _syncStatusSub;
  int _tileCacheBytes = 0;
  bool _isPrefetchingTiles = false;
  int _tileDone = 0;
  int _tileTotal = 0;

  /*
  @override
  void initState() {
    super.initState();
    _loadUrl();
    _refreshTileCacheSize();
    _refreshCrudPendingCount();
    // Login returns only name and access level; pull contact details too.
    widget.authSignals.refreshProfile();
  }
  */
  // Gene - Nov, 28, 2026: Subscribe to PowerSync statusStream in replicated mode so ps_crud pending badge updates live after sync uploads.
  @override
  void initState() {
    super.initState();
    _loadUrl();
    _refreshTileCacheSize();
    _refreshCrudPendingCount();
    if (PowerSyncService.instance.isReplicatedMode) {
      _syncStatusSub = PowerSyncService.instance.statusStream?.listen((_) {
        _refreshCrudPendingCount();
      });
    }
    // Login returns only name and access level; pull contact details too.
    widget.authSignals.refreshProfile();
  }

  @override
  void dispose() {
    _syncStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshCrudPendingCount() async {
    if (!PowerSyncService.instance.isReplicatedMode) return;
    final count = await PowerSyncService.instance.countPendingCrud();
    if (mounted) setState(() => _crudPendingCount = count);
  }

  Future<void> _refreshTileCacheSize() async {
    final bytes = await MapTiles.getCacheSizeBytes();
    if (mounted) setState(() => _tileCacheBytes = bytes);
  }

  Future<void> _handlePrefetchMapTiles() async {
    if (_isPrefetchingTiles) return;
    final pos = LocationService.instance.lastKnownPosition;
    final lat = pos?.latitude ?? LocationService.fallbackLat;
    final lng = pos?.longitude ?? LocationService.fallbackLng;
    setState(() {
      _isPrefetchingTiles = true;
      _tileDone = 0;
      _tileTotal = 0;
    });
    try {
      final result = await MapTiles.prefetchArea(
        centerLat: lat,
        centerLng: lng,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _tileDone = done;
            _tileTotal = total;
          });
        },
      );
      await _refreshTileCacheSize();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cached ${result.downloaded} of ${result.total} map tiles for offline field work.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrefetchingTiles = false);
    }
  }

  Future<void> _handleClearTileCache() async {
    await MapTiles.clearCache();
    await _refreshTileCacheSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Offline map tile cache cleared.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadUrl() async {
    final url = await _storage.getBaseUrl();
    if (mounted) setState(() => _baseUrl = url);
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTestingPing = true;
      _pingSuccess = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      await ApiClient.instance.get('/Users');
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isTestingPing = false;
        _lastPingMs = stopwatch.elapsedMilliseconds;
        _pingSuccess = true;
      });
    } catch (_) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _isTestingPing = false;
        _lastPingMs = stopwatch.elapsedMilliseconds;
        _pingSuccess = false;
      });
    }
  }

  void _showOpticalPowerStandards() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        // Clear the system navigation bar, which otherwise covers the last
        // row of the sheet.
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 28 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /*
            // iOS Grabber Pill
            Center(
              child: Container(
                width: 36,
                height: 4.5,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF38383A)
                      : const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            */
            // Gene - Nov, 23, 2026: Removed manual drag handle pill because AppTheme.bottomSheetTheme sets showDragHandle: true.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.speedometer,
                        color: AppTheme.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'GPON Optical Power Standards',
                      style: ctx.text.titleSmall,
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 24,
                      color: isDark ? Colors.white : AppTheme.darkSlate,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildStandardRow(
              title: 'Optimal / Pass (-12.0 to -24.0 dBm)',
              description:
                  'Target range for all fiber installations. Ensures maximum throughput and stability.',
              color: AppTheme.success,
              subtle: AppTheme.successSubtle,
            ),
            const SizedBox(height: 10),
            _buildStandardRow(
              title: 'Marginal (-24.0 to -27.0 dBm)',
              description:
                  'Service operational but approaching attenuation floor. Clean connectors & check bend radius.',
              color: AppTheme.warning,
              subtle: AppTheme.warningSubtle,
            ),
            const SizedBox(height: 10),
            _buildStandardRow(
              title: 'Faulty / Out of Spec (< -27.0 or > -8.0 dBm)',
              description:
                  'Excessive insertion loss or saturation. Re-splice drop cable or inspect NAP splitter port.',
              color: AppTheme.danger,
              subtle: AppTheme.dangerSubtle,
            ),
          ],
        ),
      ),
    );
  }

  // Gene - Nov, 23, 2026: Modal bottom sheet to pick technician's preferred turn-by-turn navigation app.
  Future<void> _showNavAppPicker(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = SettingsSignals.instance.preferredNavApp.value;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.location_fill,
                        color: AppTheme.primary, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Default Navigation App',
                        style: ctx.text.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose which maps app opens when you tap Navigate on a job or repair.',
                  style: ctx.text.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final option in PreferredNavApp.values)
                  InkWell(
                    key: ValueKey('nav_app_option_${option.name}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      await SettingsSignals.instance.setPreferredNavApp(option);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              option == current
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: option == current
                                  ? AppTheme.primary
                                  : AppTheme.secondaryInkOf(ctx),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                option.label,
                                style: ctx.text.titleSmall,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildStandardRow({
    required String title,
    required String description,
    required Color color,
    required Color subtle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The three call sites only ever pass one of these three brand/status
    // fills; route the text to the ink that matches so it never renders in
    // the bright colour itself.
    final Color textInk = color == AppTheme.success
        ? AppTheme.successInkOf(context)
        : color == AppTheme.warning
            ? AppTheme.warningInkOf(context)
            : AppTheme.dangerInkOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.18) : subtle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.circle_fill, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: context.text.labelLarge!.copyWith(color: textInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: context.text.bodyMedium!
                .copyWith(color: AppTheme.secondaryInkOf(context)),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, {bool success = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: success
            ? (isDark
                ? const Color(0xFF34C759).withValues(alpha: 0.2)
                : AppTheme.successSubtle)
            : (isDark ? const Color(0xFF3F2327) : AppTheme.primarySubtleBg),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: success
              ? (isDark
                  ? const Color(0xFF34C759).withValues(alpha: 0.3)
                  : const Color(0xFFBBF7D0))
              : (isDark
                  ? AppTheme.primary.withValues(alpha: 0.3)
                  : AppTheme.primarySubtleBorder),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: context.text.labelMedium!.copyWith(
          color: success
              ? AppTheme.successInkOf(context)
              : AppTheme.brandInkOf(context),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppTheme.secondaryInkOf(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: context.text.bodySmall,
              ),
            ),
          ],
        ),
      );

  /*
  Future<void> _handleLogout() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to end your field terminal session?',
      confirmLabel: 'Sign Out',
      destructive: true,
    );

    if (confirm == true) {
      await widget.authSignals.logout();
    }
  }
  */
  // Gene - Nov, 23, 2026: Combined pending count, manual Sync Now flush, per-item SyncErrorLog retry router, and unsynced sign-out guard.
  ({int jobs, int repairs, int plant, int total}) _pendingBreakdown() {
    final jobs = math.max(
      widget.jobsSignals.unsyncedCount.value,
      widget.jobsSignals.repository.syncWorker.pendingCount.value,
    );
    final repairsStreamCount = widget.serviceOrdersSignals?.allOrders.value
            .where((o) => !o.isSynced)
            .length ??
        0;
    final repairsWorkerCount =
        widget.serviceOrdersSignals?.syncWorker?.pendingCount.value ?? 0;
    final repairs = math.max(repairsStreamCount, repairsWorkerCount);
    final plant = widget.lcpNapSignals?.unsyncedCount.value ?? 0;
    return (
      jobs: jobs,
      repairs: repairs,
      plant: plant,
      total: jobs + repairs + plant,
    );
  }

  Future<int> _flushAllQueues() async {
    if (mounted) setState(() => _isSyncingAll = true);
    try {
      // Gene - Nov, 27, 2026: In replicated PowerSync mode, reconnect stream & refresh ps_crud queue count instead of running legacy REST sync workers.
      if (PowerSyncService.instance.isReplicatedMode) {
        /*
        await PowerSyncService.instance.connectIfConfigured();
        */
        // Gene - Nov, 28, 2026: Force credential refresh & stream reconnect on manual Settings sync even if already marked connected.
        await PowerSyncService.instance.reconnect();
        widget.jobsSignals.repository.clearImagesCache();
        widget.serviceOrdersSignals?.clearImagesCache();
        widget.lcpNapSignals?.repository.invalidateImagesCache();
        final crudCount = await PowerSyncService.instance.countPendingCrud();
        if (mounted) setState(() => _crudPendingCount = crudCount);
        return math.max(_pendingBreakdown().total, crudCount);
      }
      await widget.jobsSignals.repository.syncWorker.syncPendingJobs();
      await widget.serviceOrdersSignals?.syncWorker?.syncPendingOrders();
      await widget.lcpNapSignals?.syncPending();
      return _pendingBreakdown().total;
    } finally {
      if (mounted) setState(() => _isSyncingAll = false);
    }
  }

  Future<void> _handleSyncNow() async {
    if (_isSyncingAll) return;
    final remaining = await _flushAllQueues();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          remaining == 0
              ? 'All offline changes synced.'
              : '$remaining item(s) still pending. Check Sync Error Log.',
        ),
        backgroundColor: remaining == 0 ? AppTheme.success : AppTheme.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _retrySyncErrorLog(SyncErrorLog log) async {
    switch (log.entityType) {
      case 'JOB_ORDER':
        return widget.jobsSignals.repository.syncWorker
            .syncSingleJob(log.entityId);
      case 'SERVICE_ORDER':
        final worker = widget.serviceOrdersSignals?.syncWorker;
        if (worker == null) return false;
        return worker.syncSingleOrder(log.entityId);
      case 'LCP_NAP':
        final lcpSignals = widget.lcpNapSignals;
        if (lcpSignals == null) return false;
        await lcpSignals.syncPending();
        return !lcpSignals.allLocations.value
            .any((loc) => loc.id == log.entityId && !loc.isSynced);
      default:
        return false;
    }
  }

  Future<void> _handleLogout() async {
    final counts = _pendingBreakdown();
    if (counts.total <= 0) {
      final confirm = await showConfirmDialog(
        context,
        title: 'Sign Out',
        message: 'Are you sure you want to end your field terminal session?',
        confirmLabel: 'Sign Out',
        destructive: true,
      );
      if (confirm == true) {
        await widget.authSignals.logout();
      }
      return;
    }

    final choice = await showAdaptiveDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Unsynced work on phone'),
        content: Text(
          '${counts.total} offline update(s) have not synced yet '
          '(Jobs: ${counts.jobs} · Repairs: ${counts.repairs} · Plant: ${counts.plant}). '
          'Sync before signing out so no field work is stranded.',
        ),
        actions: [
          adaptiveDialogAction(
            ctx,
            label: 'Cancel',
            isDefault: true,
            onPressed: () => Navigator.of(ctx).pop('cancel'),
          ),
          adaptiveDialogAction(
            ctx,
            label: 'Sync & Sign Out',
            onPressed: () => Navigator.of(ctx).pop('sync'),
          ),
          adaptiveDialogAction(
            ctx,
            label: 'Sign Out Anyway',
            isDestructive: true,
            onPressed: () => Navigator.of(ctx).pop('force'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == 'force') {
      await widget.authSignals.logout();
    } else if (choice == 'sync') {
      final remaining = await _flushAllQueues();
      if (!mounted) return;
      if (remaining == 0) {
        await widget.authSignals.logout();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Still $remaining unsynced item(s). Check Sync Error Log before signing out.',
            ),
            backgroundColor: AppTheme.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildIosSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: context.text.labelSmall,
      ),
    );
  }

  Widget _buildIosGroupedCard({
    required List<Widget> children,
    required bool isDark,
    EdgeInsetsGeometry? padding,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 0.5,
        ),
      ),
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /*
  Widget _buildIosSettingRow({
    required IconData icon,
    required Color iconBg,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    required bool isDark,
    bool showDivider = true,
  }) {
    return Column(
  */
  // Gene - Nov, 23, 2026: Added optional rowKey parameter to _buildIosSettingRow for testable settings rows.
  Widget _buildIosSettingRow({
    Key? rowKey,
    required IconData icon,
    required Color iconBg,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    required bool isDark,
    bool showDivider = true,
  }) {
    return Column(
      key: rowKey,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                // iOS Squircle Icon Badge
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.text.titleMedium,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: context.text.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 56,
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.authSignals;
    final jobs = widget.jobsSignals;
    final syncWorker = jobs.repository.syncWorker;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Titled after its tab so the bar says what was tapped.
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Section 1: Technician Profile Header
          _buildIosSectionHeader('Technician Profile'),
          SignalBuilder(
            builder: (context) {
              final user = auth.currentUser.value;
              return _buildIosGroupedCard(
                isDark: isDark,
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: isDark
                            ? const Color(0xFF3F2327)
                            : AppTheme.primarySubtleBg,
                        child: Text(
                          user?.initials ?? 'T',
                          style: context.text.titleLarge!
                              .copyWith(color: AppTheme.brandInkOf(context)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Technician User',
                              style: context.text.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@${user?.username ?? "technician"}',
                              style: context.text.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _tag(
                                    'Access level ${user?.accessLevelId ?? "-"}'),
                                if (user?.active == true)
                                  _tag('Active', success: true),
                                if (user != null && user.menus.isNotEmpty)
                                  _tag('${user.menus.length} modules'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (user != null &&
                      (user.email.isNotEmpty ||
                          user.contactNumber.isNotEmpty ||
                          user.address.isNotEmpty)) ...[
                    Divider(
                      height: 24,
                      thickness: 0.5,
                      color:
                          isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    ),
                    if (user.email.isNotEmpty)
                      _detailRow(CupertinoIcons.mail, user.email),
                    if (user.contactNumber.isNotEmpty)
                      _detailRow(CupertinoIcons.phone, user.contactNumber),
                    if (user.address.isNotEmpty)
                      _detailRow(CupertinoIcons.location_solid, user.address),
                  ],
                ],
              );
            },
          ),

          // Section 2: Appearance & Display Preferences
          _buildIosSectionHeader('Appearance & Display'),
          SignalBuilder(
            builder: (context) {
              final dark = SettingsSignals.instance.isDarkMode;
              // Gene - Nov, 23, 2026: Added Default Navigation App preference row under Appearance & Display.
              final preferredNav =
                  SettingsSignals.instance.preferredNavApp.value;
              return _buildIosGroupedCard(
                isDark: isDark,
                children: [
                  _buildIosSettingRow(
                    icon: dark
                        ? CupertinoIcons.moon_fill
                        : CupertinoIcons.sun_max_fill,
                    iconBg: const Color(0xFF5856D6), // iOS Indigo
                    title: 'Dark Mode',
                    subtitle: dark
                        ? 'Easier on the eyes in low light'
                        : 'Optimized for high outdoor sunlight',
                    isDark: isDark,
                    /*
                    showDivider: false,
                    */
                    showDivider: true,
                    trailing: Switch.adaptive(
                      value: dark,
                      activeTrackColor: AppTheme.primary,
                      onChanged: (v) => SettingsSignals.instance.setDarkMode(v),
                    ),
                  ),
                  _buildIosSettingRow(
                    rowKey: const ValueKey('settings_nav_app_row'),
                    icon: CupertinoIcons.location_fill,
                    iconBg: AppTheme.primary,
                    title: 'Default Navigation App',
                    subtitle: preferredNav.label,
                    isDark: isDark,
                    showDivider: false,
                    onTap: () => _showNavAppPicker(context),
                    trailing: Icon(
                      CupertinoIcons.chevron_forward,
                      size: 24,
                      color: AppTheme.secondaryInkOf(context),
                    ),
                  ),
                ],
              );
            },
          ),

          // Section 3: Field Reference Tools
          _buildIosSectionHeader('Field Reference Tools'),
          _buildIosGroupedCard(
            isDark: isDark,
            children: [
              _buildIosSettingRow(
                icon: CupertinoIcons.speedometer,
                iconBg: AppTheme.primary,
                title: 'GPON Optical Power Standards',
                subtitle: 'Thresholds & attenuation loss specs',
                isDark: isDark,
                showDivider: false,
                onTap: _showOpticalPowerStandards,
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 24,
                  color: AppTheme.secondaryInkOf(context),
                ),
              ),
            ],
          ),

          // Section 3b: Why a pending push was refused. Sits next to the
          // offline cache because that is the question it answers: the edit
          // is saved, so what is the server objecting to?
          _buildIosSectionHeader('Sync Diagnostics'),
          _buildIosGroupedCard(
            isDark: isDark,
            children: [
              // Gene - Nov, 26, 2026: Added Work Timing History entry row showing Start/Finish/Stop sessions by userId and date.
              _buildIosSettingRow(
                rowKey: const ValueKey('settings_timing_history_row'),
                icon: Icons.history_rounded,
                iconBg: AppTheme.serviceOrderAccent,
                title: 'Work Timing History',
                subtitle: 'Start & finish/stop sessions by user and date',
                isDark: isDark,
                showDivider: true,
                onTap: () {
                  final dao = widget.jobsSignals.timingHistory ??
                      widget.serviceOrdersSignals?.timingHistory;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkTimingHistoryScreen(dao: dao),
                    ),
                  );
                },
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 24,
                  color: AppTheme.secondaryInkOf(context),
                ),
              ),
              _buildIosSettingRow(
                icon: CupertinoIcons.exclamationmark_triangle,
                iconBg: AppTheme.warning,
                title: 'Sync Error Log',
                subtitle: 'What the server said when a push was refused',
                isDark: isDark,
                showDivider: false,
                onTap: () {
                  final dao = widget.jobsSignals.repository.errorLog;
                  if (dao == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SyncErrorLogScreen(
                        dao: dao,
                        onRetryItem: _retrySyncErrorLog,
                      ),
                    ),
                  );
                },
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 24,
                  color: AppTheme.secondaryInkOf(context),
                ),
              ),
            ],
          ),

          // Section 4: Offline Storage & PowerSync Database Cache
          _buildIosSectionHeader('Offline Storage (PowerSync SQLite)'),
          _buildIosGroupedCard(
            isDark: isDark,
            padding: const EdgeInsets.all(14),
            children: [
              /*
              SignalBuilder(
                builder: (context) {
                  final total = jobs.totalCount.value;
                  final pending = syncWorker.pendingCount.value;
                  final isSyncing = syncWorker.isSyncing.value;
                  final cloud = PowerSyncService.instance.isConnected;

                  return Column(
                    children: [
                      _buildMetricRow(
                        'Total Cached Job Orders',
                        '$total records',
                        CupertinoIcons.folder,
                      ),
                      const SizedBox(height: 8),
                      _buildMetricRow(
                        'Pending Sync Queue',
                        '$pending offline updates',
                        CupertinoIcons.cloud_upload,
                        badgeColor:
                            pending > 0 ? AppTheme.warning : AppTheme.success,
                      ),
                      const SizedBox(height: 8),
                      // Honest about the cloud side: every table is local
                      // only until the PowerSync service replicates the
                      // backend, so pushes still go through the REST API.
                      _buildMetricRow(
                        'PowerSync Engine Status',
                        isSyncing
                            ? 'Pushing to API...'
                            : cloud
                                ? 'Cloud sync connected'
                                : 'Local only',
                        CupertinoIcons.layers_alt,
                        badgeColor: isSyncing
                            ? AppTheme.primary
                            : cloud
                                ? AppTheme.success
                                : null,
                      ),
                    ],
                  );
                },
              ),
              */
              // Gene - Nov, 23, 2026: Show combined Jobs + Repairs + Plant pending queue and manual Sync Now button.
              // Gene - Nov, 27, 2026: Observe PowerSync statusStream and include ps_crud queue count when replicated mode is active.
              SignalBuilder(
                builder: (context) {
                  final totalJobs = jobs.totalCount.value;
                  final counts = _pendingBreakdown();
                  final isReplicated =
                      PowerSyncService.instance.isReplicatedMode;
                  final effectivePending = isReplicated
                      ? math.max(counts.total, _crudPendingCount)
                      : counts.total;
                  final isSyncing = _isSyncingAll ||
                      syncWorker.isSyncing.value ||
                      (widget.serviceOrdersSignals?.syncWorker?.isSyncing
                              .value ??
                          false);
                  final statusStream = PowerSyncService.instance.isInitialized
                      ? PowerSyncService.instance.statusStream
                      : null;

                  return StreamBuilder<SyncStatus>(
                    stream: statusStream,
                    initialData: PowerSyncService.instance.isInitialized
                        ? PowerSyncService.instance.currentStatus
                        : null,
                    builder: (context, snapshot) {
                      final syncStatus = snapshot.data;
                      final cloud = syncStatus?.connected ??
                          PowerSyncService.instance.isConnected;
                      final uploading = syncStatus?.uploading ?? false;
                      final downloading = syncStatus?.downloading ?? false;

                      /*
                      final legacyStatusText = isSyncing
                          ? 'Pushing to API...'
                          : cloud
                              ? 'Cloud sync connected'
                              : 'Local only';
                      */
                      final String engineLabel;
                      final Color? engineColor;
                      if (isSyncing || uploading) {
                        engineLabel = isReplicated
                            ? 'Syncing changes…'
                            : 'Pushing to API...';
                        engineColor = AppTheme.primary;
                      } else if (downloading) {
                        engineLabel = 'Downloading updates…';
                        engineColor = AppTheme.primary;
                      } else if (cloud) {
                        engineLabel = 'Cloud sync connected';
                        engineColor = AppTheme.success;
                      } else if (isReplicated) {
                        engineLabel = 'Connecting to PowerSync…';
                        engineColor = AppTheme.warning;
                      } else {
                        engineLabel = 'Local only';
                        engineColor = null;
                      }

                      return Column(
                        children: [
                          _buildMetricRow(
                            'Total Cached Job Orders',
                            '$totalJobs records',
                            CupertinoIcons.folder,
                          ),
                          const SizedBox(height: 8),
                          _buildMetricRow(
                            'Pending Sync Queue',
                            '$effectivePending offline updates',
                            CupertinoIcons.cloud_upload,
                            badgeColor: effectivePending > 0
                                ? AppTheme.warning
                                : AppTheme.success,
                          ),
                          if (effectivePending > 0 ||
                              widget.serviceOrdersSignals != null ||
                              widget.lcpNapSignals != null) ...[
                            const SizedBox(height: 6),
                            _buildMetricRow(
                              'Queue Breakdown',
                              'Jobs ${counts.jobs} · Repairs ${counts.repairs} · Plant ${counts.plant}',
                              CupertinoIcons.list_bullet,
                            ),
                          ],
                          const SizedBox(height: 8),
                          _buildMetricRow(
                            'PowerSync Engine Status',
                            engineLabel,
                            CupertinoIcons.layers_alt,
                            badgeColor: engineColor,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const ValueKey('settings_sync_now_button'),
                              onPressed: isSyncing ? null : _handleSyncNow,
                              icon: isSyncing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync_rounded, size: 20),
                              label: Text(isSyncing ? 'Syncing…' : 'Sync Now'),
                            ),
                          ),
                          // Gene - Nov, 23, 2026: Added Offline Map Tiles cache size display, area prefetch, and cache clear controls.
                          const SizedBox(height: 14),
                          Divider(
                            height: 1,
                            color: isDark
                                ? AppTheme.borderDark
                                : AppTheme.borderLight,
                          ),
                          const SizedBox(height: 12),
                          Column(
                            key: const ValueKey('settings_map_tiles_row'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildMetricRow(
                                'Offline Map Tiles',
                                _isPrefetchingTiles && _tileTotal > 0
                                    ? '$_tileDone / $_tileTotal tiles'
                                    : '${(_tileCacheBytes / (1024 * 1024)).toStringAsFixed(1)} MB cached',
                                CupertinoIcons.map_pin_ellipse,
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    key: const ValueKey(
                                        'settings_download_map_tiles_button'),
                                    onPressed: _isPrefetchingTiles
                                        ? null
                                        : _handlePrefetchMapTiles,
                                    icon: _isPrefetchingTiles
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(
                                            Icons.download_for_offline_outlined,
                                            size: 20),
                                    label: const Text('Download Area'),
                                  ),
                                  TextButton.icon(
                                    key: const ValueKey(
                                        'settings_clear_map_tiles_button'),
                                    onPressed: (_isPrefetchingTiles ||
                                            _tileCacheBytes == 0)
                                        ? null
                                        : _handleClearTileCache,
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20),
                                    label: const Text('Clear'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),

          // Section 5: Backend Connection & SSL Pinning
          _buildIosSectionHeader('Backend Connection & Diagnostics'),
          _buildIosGroupedCard(
            isDark: isDark,
            padding: const EdgeInsets.all(14),
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.shield_lefthalf_fill,
                      size: 17, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'SSL Pinned Channel',
                    style: context.text.titleSmall,
                  ),
                  const Spacer(),
                  _buildPinningBadge(isDark),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Direct communication channel with Switch Fiber dispatch server.',
                style: context.text.bodyMedium!
                    .copyWith(color: AppTheme.secondaryInkOf(context)),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        ServerDisplay.mask(_baseUrl),
                        style: context.text.bodyMedium!.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_lastPingMs != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _pingSuccess == true
                              ? (isDark
                                  ? const Color(0xFF34C759)
                                      .withValues(alpha: 0.2)
                                  : AppTheme.successSubtle)
                              : (isDark
                                  ? const Color(0xFFFF3B30)
                                      .withValues(alpha: 0.2)
                                  : AppTheme.dangerSubtle),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_lastPingMs}ms',
                          style: context.text.labelMedium!.copyWith(
                            color: _pingSuccess == true
                                ? AppTheme.successInkOf(context)
                                : AppTheme.dangerInkOf(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isTestingPing ? null : _testConnection,
                  icon: _isTestingPing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.waveform_path_ecg, size: 24),
                  label: Text(_isTestingPing
                      ? 'Testing latency...'
                      : 'Test Connection Latency'),
                ),
              ),
            ],
          ),

          // Section 6: Session & Logout Action
          _buildIosSectionHeader('Account Session'),
          _buildIosGroupedCard(
            isDark: isDark,
            children: [
              _buildIosSettingRow(
                icon: CupertinoIcons.square_arrow_left,
                iconBg: AppTheme.danger,
                title: 'Sign Out of Terminal',
                isDark: isDark,
                showDivider: false,
                onTap: _handleLogout,
                trailing: const Icon(
                  CupertinoIcons.chevron_forward,
                  size: 24,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // App build info
          Center(
            child: Text(
              '${AppConstants.appName} v${AppConstants.appVersion}\nSwitch Fiber Philippines • Dispatch Ops',
              textAlign: TextAlign.center,
              style: context.text.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinningBadge(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF34C759).withValues(alpha: 0.2)
            : AppTheme.successSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? const Color(0xFF34C759).withValues(alpha: 0.35)
              : const Color(0xFFBBF7D0),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.checkmark_shield_fill,
            size: 20,
            color: isDark ? const Color(0xFF4ADE80) : AppTheme.success,
          ),
          const SizedBox(width: 4),
          Text(
            'SSL Pinned (SHA-256)',
            style: context.text.labelMedium!
                .copyWith(color: AppTheme.successInkOf(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    IconData icon, {
    Color? badgeColor,
  }) {
    // Call sites only ever pass one of these three brand/status fills (or
    // leave it null for the default ink); route whichever was passed to the
    // ink that matches so the value never renders in the bright colour.
    final Color? valueInk = badgeColor == null
        ? null
        : badgeColor == AppTheme.success
            ? AppTheme.successInkOf(context)
            : badgeColor == AppTheme.warning
                ? AppTheme.warningInkOf(context)
                : AppTheme.brandInkOf(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.secondaryInkOf(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: context.text.bodySmall,
          ),
        ),
        Text(
          value,
          style: context.text.labelMedium!.copyWith(
            color: valueInk ??
                (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : AppTheme.darkSlate),
          ),
        ),
      ],
    );
  }
}
