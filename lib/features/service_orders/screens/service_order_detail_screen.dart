import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/draft_storage_service.dart';
import '../../../core/services/image_capture_service.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/utils/data_url.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/action_pair.dart';
import '../../../core/widgets/adaptive_dialogs.dart';
import '../../../core/widgets/sticky_action_bar.dart';
import '../../catalogs/models/catalog_model.dart';
import '../../catalogs/services/catalog_service.dart';
import '../../catalogs/widgets/router_model_picker.dart';
import '../../diagnostics/widgets/radius_connection_card.dart';
import '../../jobs/signals/jobs_signals.dart';
import '../../lcp_nap/screens/lcp_nap_detail_screen.dart';
import '../../lcp_nap/services/nap_port_occupancy.dart';
import '../../lcp_nap/signals/lcp_nap_signals.dart';
import '../../reports/widgets/photo_capture_tile.dart';
import '../../reports/widgets/signature_pad.dart';
import '../../toolkit/services/bom_handoff_service.dart';
import '../../../core/widgets/material_counter_row.dart';
import '../../../core/widgets/searchable_picker_sheet.dart';
import '../../../core/widgets/serial_scanner_sheet.dart';
import '../models/service_order_model.dart';
import '../signals/service_orders_signals.dart';

/// Detailed view and completion form for a Service Order (repair, swap, pullout).
class ServiceOrderDetailScreen extends StatefulWidget {
  final int orderId;
  final ServiceOrdersSignals signals;
  final Future<String?> Function(BuildContext context)? scanBarcode;
  // Gene - Nov, 23, 2026: Optional LcpNapSignals and JobsSignals to allow deep linking from repair ticket to assigned NAP pole.
  final LcpNapSignals? lcpNapSignals;
  final JobsSignals? jobsSignals;

  const ServiceOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.signals,
    this.scanBarcode,
    this.lcpNapSignals,
    this.jobsSignals,
  });

  @override
  State<ServiceOrderDetailScreen> createState() =>
      _ServiceOrderDetailScreenState();
}

class _ServiceOrderDetailScreenState extends State<ServiceOrderDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _signatureController = SignaturePadController();

  late final TextEditingController _remarksController;
  late final TextEditingController _newSnController;
  late final TextEditingController _pulloutSnController;
  late final TextEditingController _pulloutRemarksController;

  String? _selectedRouterModel;
  List<RouterDto> _availableRouters = CatalogService.fallbackRouters;

  /*
  // Materials Counters
  int _dropCableMeters = 0;
  int _fastConnectors = 0;
  int _sClamps = 0;
  */
  // Gene - Nov, 23, 2026: Dynamic catalog materials map, lockable signature pad toggle, and quick-remark helpers for Repairs parity.
  Map<String, int> _materialsUsed = <String, int>{};
  List<String> _availableMaterials =
      List<String>.from(CatalogService.fallbackMaterials);
  bool _isSignaturePadActive = false;

  // Photos (Data URLs)
  String? _photo1;
  String? _photo2;
  String? _photo3;

  bool _isSubmitting = false;

  // Gene - Nov, 23, 2026: Added draft auto-save, signature restoration, and PopScope unsaved-changes guard.
  bool _hasUnsavedChanges = false;
  bool _draftRestored = false;
  bool _isApplyingProgrammaticText = false;
  Timer? _draftDebounce;
  String? _draftSignature;

  @override
  void initState() {
    super.initState();
    final order = _findOrder();
    _remarksController = TextEditingController(text: order?.visitRemarks ?? '');
    _newSnController =
        TextEditingController(text: order?.newRouterModemSN ?? '');
    _pulloutSnController = TextEditingController(
        text: order?.pulloutRouterModelSN ?? order?.routerModemSN ?? '');
    _pulloutRemarksController =
        TextEditingController(text: order?.pulloutRemarks ?? '');

    // Materials prefill
    if (order != null) {
      /*
      _dropCableMeters = order.materialsUsed['Drop Cable (m)'] ?? 0;
      _fastConnectors = order.materialsUsed['SC/APC Fast Connector'] ?? 0;
      _sClamps = order.materialsUsed['S-Clamp'] ?? 0;
      */
      _materialsUsed = {
        for (final entry in order.materialsUsed.entries)
          if (entry.value > 0) entry.key: entry.value,
      };
      _photo1 = order.image1;
      _photo2 = order.image2;
      _photo3 = order.houseFrontPicture ?? order.image3;
    }

    // Show what is on file straight away; the catalog request that follows
    // can take seconds on a poor link and must not leave the model blank
    // or overwrite a choice made while it was in flight.
    _selectedRouterModel = _initialRouterModel(_availableRouters);
    _loadCatalog();

    _remarksController.addListener(_onDraftControllerEdited);
    _newSnController.addListener(_onDraftControllerEdited);
    _pulloutSnController.addListener(_onDraftControllerEdited);
    _pulloutRemarksController.addListener(_onDraftControllerEdited);
    _signatureController.addListener(_onDraftControllerEdited);
    unawaited(_restoreDraftIfAny());

    // Gene - Nov, 20, 2026: Ensure opening ServiceOrderDetailScreen directly marks the order as read safely after the current frame.
    if (!widget.signals.isOrderReadPeek(widget.orderId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.signals.markOrderAsRead(widget.orderId);
      });
    }
  }

  ServiceOrderDto? _findOrder() {
    return widget.signals.allOrders.value
        .where((o) => o.id == widget.orderId)
        .firstOrNull;
  }

  /*
  Future<void> _loadCatalog() async {
    final routers = await CatalogService.instance.getRouters();
    if (!mounted) return;
    setState(() {
      _availableRouters = routers;
      if (_selectedRouterModel?.trim().isNotEmpty != true) {
        _selectedRouterModel = _initialRouterModel(routers);
      }
    });
  }
  */
  // Gene - Nov, 23, 2026: Load both routers and dynamic inventory materials from CatalogService.
  Future<void> _loadCatalog() async {
    final results = await Future.wait([
      CatalogService.instance.getRouters(),
      CatalogService.instance.getMaterials(),
    ]);
    if (!mounted) return;
    final routers = results[0] as List<RouterDto>;
    final materials = results[1] as List<String>;
    setState(() {
      _availableRouters = routers;
      _availableMaterials = materials;
      if (_selectedRouterModel?.trim().isNotEmpty != true) {
        _selectedRouterModel = _initialRouterModel(routers);
      }
    });
  }

  /// The stored model when the order has one, else the first approved model.
  ///
  /// The server sends `''` rather than null for "no model yet"; taken as-is
  /// that blank became the dropdown's value, matched none of its items, and
  /// the whole detail screen failed to build (the red screen on every tap).
  String? _initialRouterModel(List<RouterDto> routers) {
    final stored = _findOrder()?.routerModel?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return routers.isNotEmpty ? routers.first.compactName : null;
  }

  /*
  @override
  void dispose() {
    _signatureController.dispose();
    _remarksController.dispose();
    _newSnController.dispose();
    _pulloutSnController.dispose();
    _pulloutRemarksController.dispose();
    super.dispose();
  }
  */
  // Gene - Nov, 23, 2026: Cancel draft debounce, remove listeners, and add draft save/restore/discard helpers.
  @override
  void dispose() {
    _draftDebounce?.cancel();
    _remarksController.removeListener(_onDraftControllerEdited);
    _newSnController.removeListener(_onDraftControllerEdited);
    _pulloutSnController.removeListener(_onDraftControllerEdited);
    _pulloutRemarksController.removeListener(_onDraftControllerEdited);
    _signatureController.removeListener(_onDraftControllerEdited);
    _signatureController.dispose();
    _remarksController.dispose();
    _newSnController.dispose();
    _pulloutSnController.dispose();
    _pulloutRemarksController.dispose();
    super.dispose();
  }

  String get _draftKey => 'service_order_${widget.orderId}';

  void _onDraftControllerEdited() {
    if (_isApplyingProgrammaticText) return;
    _markDirtyAndSave();
  }

  void _markDirtyAndSave() {
    if (!_hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = true);
    } else {
      _hasUnsavedChanges = true;
    }
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_saveDraftNow());
    });
  }

  Future<void> _saveDraftNow() async {
    String? sig = _draftSignature;
    if (!_signatureController.isEmpty) {
      sig = await _signatureController.toDataUrl();
    }
    /*
    final materials = <String, int>{};
    if (_dropCableMeters > 0) materials['Drop Cable (m)'] = _dropCableMeters;
    if (_fastConnectors > 0) {
      materials['SC/APC Fast Connector'] = _fastConnectors;
    }
    if (_sClamps > 0) materials['S-Clamp'] = _sClamps;
    */
    final materials = <String, int>{
      for (final entry in _materialsUsed.entries)
        if (entry.value > 0) entry.key: entry.value,
    };

    await DraftStorageService.instance.saveDraft(_draftKey, {
      'remarks': _remarksController.text,
      'newSn': _newSnController.text,
      'pulloutSn': _pulloutSnController.text,
      'pulloutRemarks': _pulloutRemarksController.text,
      'routerModel': _selectedRouterModel,
      'materialsUsed': materials,
      'photo1': _photo1,
      'photo2': _photo2,
      'photo3': _photo3,
      'signature': sig,
    });
  }

  Future<void> _restoreDraftIfAny() async {
    final draft = await DraftStorageService.instance.loadDraft(_draftKey);
    if (!mounted || draft == null) return;

    _isApplyingProgrammaticText = true;
    try {
      setState(() {
        final remarks = draft['remarks'] as String?;
        if (remarks != null) _remarksController.text = remarks;
        final newSn = draft['newSn'] as String?;
        if (newSn != null) _newSnController.text = newSn;
        final pulloutSn = draft['pulloutSn'] as String?;
        if (pulloutSn != null) _pulloutSnController.text = pulloutSn;
        final pulloutRemarks = draft['pulloutRemarks'] as String?;
        if (pulloutRemarks != null) {
          _pulloutRemarksController.text = pulloutRemarks;
        }
        if (draft.containsKey('routerModel')) {
          _selectedRouterModel = draft['routerModel'] as String?;
        }
        final matsRaw = draft['materialsUsed'];
        if (matsRaw is Map) {
          /*
          _dropCableMeters = (matsRaw['Drop Cable (m)'] as num?)?.toInt() ?? 0;
          _fastConnectors =
              (matsRaw['SC/APC Fast Connector'] as num?)?.toInt() ?? 0;
          _sClamps = (matsRaw['S-Clamp'] as num?)?.toInt() ?? 0;
          */
          final restored = <String, int>{};
          matsRaw.forEach((k, v) {
            final qty = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
            if (qty > 0) restored[k.toString()] = qty;
          });
          _materialsUsed = restored;
        }
        if (draft.containsKey('photo1')) _photo1 = draft['photo1'] as String?;
        if (draft.containsKey('photo2')) _photo2 = draft['photo2'] as String?;
        if (draft.containsKey('photo3')) _photo3 = draft['photo3'] as String?;
        _draftSignature = draft['signature'] as String?;
        _draftRestored = true;
        _hasUnsavedChanges = true;
      });
    } finally {
      _isApplyingProgrammaticText = false;
    }
  }

  Future<void> _discardDraft() async {
    await DraftStorageService.instance.clearDraft(_draftKey);
    final order = _findOrder();
    _isApplyingProgrammaticText = true;
    try {
      setState(() {
        _remarksController.text = order?.visitRemarks ?? '';
        _newSnController.text = order?.newRouterModemSN ?? '';
        _pulloutSnController.text =
            order?.pulloutRouterModelSN ?? order?.routerModemSN ?? '';
        _pulloutRemarksController.text = order?.pulloutRemarks ?? '';
        /*
        _dropCableMeters = order?.materialsUsed['Drop Cable (m)'] ?? 0;
        _fastConnectors = order?.materialsUsed['SC/APC Fast Connector'] ?? 0;
        _sClamps = order?.materialsUsed['S-Clamp'] ?? 0;
        */
        _materialsUsed = order == null
            ? <String, int>{}
            : {
                for (final e in order.materialsUsed.entries)
                  if (e.value > 0) e.key: e.value,
              };
        _photo1 = order?.image1;
        _photo2 = order?.image2;
        _photo3 = order?.houseFrontPicture ?? order?.image3;
        _selectedRouterModel = _initialRouterModel(_availableRouters);
        _draftSignature = null;
        _isSignaturePadActive = false;
        _signatureController.clear();
        _draftRestored = false;
        _hasUnsavedChanges = false;
      });
    } finally {
      _isApplyingProgrammaticText = false;
    }
  }

  Future<void> _handleBackWithUnsavedDraft() async {
    await _saveDraftNow();
    if (!mounted) return;
    final leave = await showConfirmDialog(
      context,
      title: 'Leave repair ticket?',
      message:
          'Your progress is saved as a draft on this phone and will resume when you return.',
      confirmLabel: 'Leave (keep draft)',
    );
    if (leave == true && mounted) {
      setState(() => _hasUnsavedChanges = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _handleScanSerial(TextEditingController controller) async {
    final scanFn = widget.scanBarcode ?? SerialScannerSheet.show;
    final scanned = await scanFn(context);
    if (!mounted || scanned == null) return;
    final clean = scanned.trim();
    if (clean.isNotEmpty) {
      setState(() {
        controller.text = clean;
      });
      _markDirtyAndSave();
    }
  }

  Future<void> _handleSubmit(ServiceOrderDto order) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);

    String? signature;
    if (!_signatureController.isEmpty) {
      signature = await _signatureController.toDataUrl();
    }

    /*
    final materials = <String, int>{};
    if (_dropCableMeters > 0) materials['Drop Cable (m)'] = _dropCableMeters;
    if (_fastConnectors > 0) {
      materials['SC/APC Fast Connector'] = _fastConnectors;
    }
    if (_sClamps > 0) materials['S-Clamp'] = _sClamps;
    */
    // Gene - Nov, 23, 2026: Serialize full dynamic _materialsUsed map on completion.
    final materials = <String, int>{
      for (final entry in _materialsUsed.entries)
        if (entry.value > 0) entry.key: entry.value,
    };

    final updated = ServiceOrderDto(
      id: order.id,
      accountNumber: order.accountNumber,
      fullName: order.fullName,
      contactNumber: order.contactNumber,
      emailAddress: order.emailAddress,
      address: order.address,
      barangay: order.barangay,
      city: order.city,
      provider: order.provider,
      plan: order.plan,
      username: order.username,
      connectionType: order.connectionType,
      routerModemSN: order.routerModemSN,
      lcp: order.lcp,
      nap: order.nap,
      port: order.port,
      vlan: order.vlan,
      supportStatus: 'Resolved',
      concern: order.concern,
      priorityLevel: order.priorityLevel,
      visitStatus: 'Done',
      visitBy: widget.signals.technicianEmail.value ?? 'Technician',
      visitRemarks: _remarksController.text.trim(),
      assignedEmail: order.assignedEmail,
      newRouterModemSN: _newSnController.text.trim().isNotEmpty
          ? _newSnController.text.trim()
          : null,
      routerModel: _selectedRouterModel,
      pulloutRouterModelSN: _pulloutSnController.text.trim().isNotEmpty
          ? _pulloutSnController.text.trim()
          : null,
      pulloutRemarks: _pulloutRemarksController.text.trim(),
      materialsUsed: materials,
      clientSignature: signature ?? _draftSignature ?? order.clientSignature,
      image1: _photo1 ?? order.image1,
      image2: _photo2 ?? order.image2,
      image3: _photo3 ?? order.image3,
      houseFrontPicture: _photo3 ?? order.houseFrontPicture,
      addressCoordinates: order.addressCoordinates,
    );

    final success = await widget.signals.submitCompletion(updated);
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (success) {
      // Gene - Nov, 23, 2026: Clear saved draft before popping after successful service order save.
      _draftDebounce?.cancel();
      await DraftStorageService.instance.clearDraft(_draftKey);
      if (!mounted) return;
      _hasUnsavedChanges = false;
      _draftRestored = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service Order marked as Completed!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.signals.syncError.value ??
              'Failed to submit service order'),
          backgroundColor: AppTheme.primary,
        ),
      );
    }
  }

  // Gene - Nov, 23, 2026: Added draft restored banner helper for ServiceOrderDetailScreen.
  Widget _buildDraftRestoredBanner() {
    if (!_draftRestored) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('service_order_draft_restored_banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySubtleBgOf(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: AppTheme.primarySubtleBorderOf(context),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.restore_rounded,
            size: 20,
            color: AppTheme.brandInkOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Restored saved draft from phone',
              style: context.text.bodySmall!.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.brandInkOf(context),
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('discard_service_order_draft_button'),
            onPressed: _discardDraft,
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SignalBuilder(
      builder: (context) {
        final order = _findOrder();
        if (order == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Service Order')),
            body: const Center(child: Text('Service order not found.')),
          );
        }

        // Gene - Nov, 23, 2026: Wrapped ServiceOrderDetailScreen Scaffold in PopScope unsaved-changes guard.
        return PopScope(
          canPop: !_hasUnsavedChanges || _isSubmitting,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_handleBackWithUnsavedDraft());
          },
          child: Scaffold(
            appBar: AppBar(
              // Ticket id only, same as the job detail; the concern is the
              // first line of the subscriber card. One line at 200% text.
              title: Text(
                'SO-${order.id.toString().padLeft(4, '0')}',
                style: context.text.bodyLarge!
                    .copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // The screen's one red verb, pinned where the job detail pins its
            // own (DESIGN.md: read at the top, act at the bottom).
            bottomNavigationBar: StickyActionBar(
              label: _isSubmitting ? 'Saving…' : 'Complete service order',
              icon: Icons.check_circle_rounded,
              onPressed: _isSubmitting ? null : () => _handleSubmit(order),
            ),
            body: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildDraftRestoredBanner(),
                  // 1. Concern & Subscriber Card
                  _buildSubscriberCard(order, isDark),
                  const SizedBox(height: 16),

                  // 2. Plant & Hardware Allocation (2x2 Instrument Grid)
                  _buildPlantAndHardwareCard(order, isDark),
                  const SizedBox(height: 16),

                  // 3. Hardware Swaps & Pullout Card
                  _buildHardwareSwapCard(order, isDark),
                  const SizedBox(height: 16),

                  // 3b. Live RADIUS PPPoE Connection & Reconnect Test
                  RadiusConnectionCard(
                    accountName: (order.username != null &&
                            order.username!.isNotEmpty &&
                            order.username!.toLowerCase() != 'switch')
                        ? order.username!
                        : order.accountNumber,
                    subscriberName: order.fullName,
                  ),
                  const SizedBox(height: 16),

                  // 4. Materials Used (BOM)
                  _buildMaterialsCounterCard(isDark),
                  const SizedBox(height: 16),

                  // 5. Photos Proofs (with GPS EXIF)
                  _buildPhotosCard(isDark),
                  const SizedBox(height: 16),

                  // 6. Subscriber Signature Pad
                  _buildSignatureCard(isDark),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubscriberCard(ServiceOrderDto order, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /*
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.primarySubtleBgDark
                        : AppTheme.primarySubtleBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.primarySubtleBorderDark
                          : AppTheme.primarySubtleBorder,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.concern.toLowerCase().contains('pullout')
                            ? CupertinoIcons.arrow_right_arrow_left
                            : CupertinoIcons.wrench_fill,
                        size: 20,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        order.concern,
                        style: context.text.labelMedium!
                            .copyWith(color: AppTheme.brandInkOf(context)),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (order.isUrgent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'URGENT',
                      style: context.text.labelSmall!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.fullName,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  'Account: ',
                  style: context.text.bodySmall,
                ),
                Flexible(
                    child: Text(
                  order.accountNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall!.copyWith(
                    fontFamily: 'JetBrains Mono',
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandInkOf(context),
                  ),
                )),
                Text(
                  ' • ${order.provider ?? order.plan ?? "Switch Fiber"}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
            */
            // Gene - Nov, 23, 2026: Wrapped concern/URGENT header and account/provider line for 200% text-scale safety.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.primarySubtleBgDark
                        : AppTheme.primarySubtleBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.primarySubtleBorderDark
                          : AppTheme.primarySubtleBorder,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.concern.toLowerCase().contains('pullout')
                            ? CupertinoIcons.arrow_right_arrow_left
                            : CupertinoIcons.wrench_fill,
                        size: 20,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          order.concern,
                          style: context.text.labelMedium!
                              .copyWith(color: AppTheme.brandInkOf(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (order.isUrgent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.danger,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'URGENT',
                      style: context.text.labelSmall!.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.fullName,
              style: context.text.titleMedium,
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Account: ',
                    style: context.text.bodySmall,
                  ),
                  TextSpan(
                    text: order.accountNumber,
                    style: context.text.bodySmall!.copyWith(
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w700,
                      color: AppTheme.brandInkOf(context),
                    ),
                  ),
                  TextSpan(
                    text:
                        ' • ${order.provider ?? order.plan ?? "Switch Fiber"}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            // Hidden entirely when the ticket has no address (DESIGN.md,
            // Repairs), rather than a lone pin over an empty line.
            if (order.address.trim().isNotEmpty) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(CupertinoIcons.location_solid,
                      size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.address,
                      style: context.text.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Gene - Oct 12, 2026: Added House Front Picture preview matching AppSheet blue annotation ("ADD FRONT HOUSE PIC").
            if (order.houseFrontPicture != null &&
                order.houseFrontPicture!.trim().isNotEmpty) ...[
              _buildHouseFrontPicturePreview(order.houseFrontPicture!, isDark),
              const SizedBox(height: 14),
            ],

            // Gene - Oct 12, 2026: Added AppSheet metadata details (Concern remarks, Support remarks, Date installed, Connection type).
            if (order.concernRemarks != null ||
                order.supportRemarks != null ||
                order.dateInstalled != null ||
                order.connectionType != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.concernRemarks != null &&
                        order.concernRemarks!.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.report_problem_outlined,
                              size: 20, color: AppTheme.warningInkOf(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Concern Remarks',
                                  style: context.text.labelSmall!.copyWith(
                                    color: AppTheme.secondaryInkOf(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  order.concernRemarks!,
                                  style: context.text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (order.supportRemarks != null &&
                        order.supportRemarks!.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.support_agent_rounded,
                              size: 20, color: AppTheme.infoInkOf(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Support Remarks',
                                  style: context.text.labelSmall!.copyWith(
                                    color: AppTheme.secondaryInkOf(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  order.supportRemarks!,
                                  style: context.text.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (order.dateInstalled != null)
                          Text(
                            'Installed: ${order.dateInstalled!.month}/${order.dateInstalled!.day}/${order.dateInstalled!.year}',
                            style: context.text.labelSmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        if (order.connectionType != null &&
                            order.connectionType!.isNotEmpty)
                          Text(
                            'Connection: ${order.connectionType}',
                            style: context.text.labelSmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        if (order.visitStatus != null &&
                            order.visitStatus!.isNotEmpty)
                          Text(
                            'Status: ${order.visitStatus}',
                            style: context.text.labelSmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Navigate | Call in the same order, size and ink as the job
            // detail. Navigate is ink so the sticky verb stays the one red.
            ActionPair(
              primary: SizedBox(
                height: AppTheme.primaryButtonHeight,
                child: FilledButton.icon(
                  onPressed: () => _navigateTo(order),
                  icon: const Icon(Icons.navigation_rounded, size: 22),
                  label: const Text('Navigate'),
                ),
              ),
              secondary: order.contactNumber.isNotEmpty
                  ? SizedBox(
                      height: AppTheme.primaryButtonHeight,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            launchUrl(Uri.parse('tel:${order.contactNumber}')),
                        icon: const Icon(Icons.call_rounded, size: 22),
                        label: const Text('Call'),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Pinned coordinates when the ticket has them, else the written address,
  /// the same fallback the repair card uses.
  Future<void> _navigateTo(ServiceOrderDto order) {
    final latLng = order.latLng;
    if (latLng != null) {
      return MapNavigationService.navigateTo(latLng, label: order.fullName);
    }
    final fullAddr =
        '${order.address}${order.barangay != null ? ", ${order.barangay}" : ""}${order.city != null ? ", ${order.city}" : ""}, Philippines';
    return MapNavigationService.navigateToAddress(fullAddr);
  }

  // Gene - Oct 12, 2026: Added House Front Picture thumbnail preview and full-screen viewer per AppSheet Page 4 requirement.
  Widget _buildHouseFrontPicturePreview(String picture, bool isDark) {
    final clean = picture.trim();
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
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                const Icon(CupertinoIcons.house_fill,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  'House Front Picture',
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
                showPhotoViewer(context, bytes, title: 'House Front Picture');
              } else if (isHttp) {
                launchUrl(Uri.parse(clean),
                    mode: LaunchMode.externalApplication);
              }
            },
            child: SizedBox(
              height: 180,
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
                            const SizedBox(height: 8),
                            Text(
                              'Tap to open photo link',
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

  Widget _buildPlantAndHardwareCard(ServiceOrderDto order, bool isDark) {
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final muted = AppTheme.secondaryInkOf(context);
    final lcpText = order.lcp?.isNotEmpty == true ? order.lcp! : 'Unassigned';
    final napText = order.nap?.isNotEmpty == true ? order.nap! : 'Unassigned';
    final portText =
        order.port?.isNotEmpty == true ? order.port! : 'Unassigned';
    final ontText = order.routerModel?.isNotEmpty == true
        ? order.routerModel!
        : (order.routerModemSN?.isNotEmpty == true
            ? order.routerModemSN!
            : 'Pending Inspection');

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
                if (order.vlan != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.5),
                    ),
                    child: Text(
                      'VLAN ${order.vlan}',
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
                                    Expanded(
                                      child: Text(
                                        'LCP CABINET',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          color: muted,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
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
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(
                            width: 0.5, thickness: 0.5, color: borderColor),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.alt_route_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'NAP BOX',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          color: muted,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
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
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor),
                  // Row 2: Port & ONT
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
                                    Icon(Icons.settings_ethernet_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'NAP PORT',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          color: muted,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
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
                                ),
                              ],
                            ),
                          ),
                        ),
                        VerticalDivider(
                            width: 0.5, thickness: 0.5, color: borderColor),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.router_rounded,
                                        size: 20, color: muted),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'ONT / MODEM',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            context.text.labelSmall!.copyWith(
                                          color: muted,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ontText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleSmall!.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
            // Gene - Nov, 23, 2026: One-tap deep link from repair ticket's assigned NAP to its Plant pole details.
            if (widget.lcpNapSignals != null)
              Builder(
                builder: (context) {
                  final locations = widget.lcpNapSignals!.allLocations.value;
                  final matched = findMatchingNapLocation(
                        locations,
                        napName: order.nap,
                        lcpName: order.lcp,
                      ) ??
                      findMatchingNapLocation(
                        locations,
                        napName: order.newNAP,
                        lcpName: order.newLCP,
                      );
                  if (matched == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey(
                            'service_order_open_nap_pole_button'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LcpNapDetailScreen(
                                locationId: matched.id,
                                signals: widget.lcpNapSignals!,
                                jobsSignals: widget.jobsSignals,
                                serviceOrdersSignals: widget.signals,
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

  Widget _buildHardwareSwapCard(ServiceOrderDto order, bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Hardware Swap / Pullout',
                      style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _pulloutSnController,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
              decoration: InputDecoration(
                labelText: 'Pullout Modem Serial Number (Old)',
                prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                suffixIcon: IconButton(
                  key: const ValueKey('scan_pullout_serial_button'),
                  tooltip: 'Scan Old Modem Serial',
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  onPressed: () => _handleScanSerial(_pulloutSnController),
                ),
                hintText: 'e.g. HWTC991823 or ZTE88301',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _newSnController,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
              decoration: InputDecoration(
                labelText: 'Replacement Modem Serial Number (New)',
                prefixIcon: const Icon(Icons.router_outlined, size: 20),
                suffixIcon: IconButton(
                  key: const ValueKey('scan_replacement_serial_button'),
                  tooltip: 'Scan Replacement Modem Serial',
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  onPressed: () => _handleScanSerial(_newSnController),
                ),
                hintText: 'e.g. HWTC2026889',
              ),
            ),
            const SizedBox(height: 12),
            // Same searchable sheet as the report's ONT model and NAP box
            // pickers. A model the catalog no longer lists is kept at the
            // top of the sheet so what is on file stays visible.
            PickerField(
              key: const ValueKey('router_model_field'),
              label: 'Approved Replacement Model',
              value: _selectedRouterModel?.trim(),
              placeholder: 'Select or filter model...',
              icon: Icons.router_rounded,
              onTap: () async {
                final picked = await RouterModelPicker.show(
                  context,
                  routers: _availableRouters,
                  selected: _selectedRouterModel,
                );
                if (picked != null && mounted) {
                  setState(() => _selectedRouterModel = picked);
                  _markDirtyAndSave();
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('pullout_remarks_field'),
              controller: _pulloutRemarksController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Pullout Remarks / Retrieved Hardware Status',
                hintText:
                    'e.g. Modem recovered with power supply; optical patch cord intact',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('technician_remarks_field'),
              controller: _remarksController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Technician Remarks / Work Performed',
                hintText:
                    'e.g. Replaced faulty ONU, re-spliced fast connector on Port 4',
              ),
            ),
            // Gene - Nov, 23, 2026: Added 1-tap repair quick-remark ActionChips below remarks field.
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final phrase in const [
                  'Re-spliced drop cable',
                  'Replaced patch cord',
                  'Replaced SC/APC connector',
                  'Replaced faulty ONT',
                  'Relocated router',
                  'Transferred NAP port',
                  'Rebooted / reconfigured ONT',
                  'Optical reading restored normal',
                ])
                  ActionChip(
                    label: Text(phrase),
                    onPressed: () => _appendQuickRemark(phrase),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _appendQuickRemark(String phrase) {
    final current = _remarksController.text.trim();
    if (current.toLowerCase().contains(phrase.toLowerCase())) return;
    final updated = current.isEmpty ? phrase : '$current, $phrase';
    setState(() {
      _remarksController.text = updated;
      _remarksController.selection =
          TextSelection.collapsed(offset: updated.length);
    });
    _markDirtyAndSave();
  }

  static String _unitForMaterial(String material) {
    final lower = material.toLowerCase();
    if (lower.contains('cable') || lower.contains('(m)')) return 'meters';
    if (lower.contains('tape')) return 'rolls';
    if (lower.contains('printer') ||
        lower.contains('meter') ||
        lower.contains('trolly')) {
      return 'units';
    }
    if (lower.contains('screw') ||
        lower.contains('tox') ||
        lower.contains('clip')) {
      return 'sets/pcs';
    }
    return 'pcs';
  }

  static String _materialKeySlug(String material) {
    if (material.contains('Drop Cable')) return 'drop_cable';
    if (material.contains('Fast Connector')) return 'fast_connectors';
    if (material.contains('S-Clamp')) return 's_clamps';
    return material
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _resolveCatalogMaterialName(String preferred, List<String> aliases) {
    for (final candidate in [preferred, ...aliases]) {
      final lower = candidate.toLowerCase();
      for (final item in _availableMaterials) {
        if (item.toLowerCase() == lower) return item;
      }
    }
    for (final candidate in [preferred, ...aliases]) {
      final lower = candidate.toLowerCase();
      for (final item in _availableMaterials) {
        if (item.toLowerCase().contains(lower)) return item;
      }
    }
    return preferred;
  }

  void _quickAddMaterial(String preferred, List<String> aliases) {
    final name = _resolveCatalogMaterialName(preferred, aliases);
    setState(() {
      _materialsUsed[name] = (_materialsUsed[name] ?? 0) + 1;
    });
    _markDirtyAndSave();
  }

  Future<void> _showMaterialPickerDialog(BuildContext context) async {
    final picked = await SearchablePickerSheet.show<String>(
      context,
      title: 'Select Material',
      icon: Icons.inventory_2_outlined,
      searchHint: 'Filter material list (e.g. Patch Cord, Cable)...',
      items: _availableMaterials,
      titleOf: (m) => m,
      subtitleOf: (m) => 'Unit: ${_unitForMaterial(m)}',
      matches: (m, q) => m.toLowerCase().contains(q),
      isSelected: (m) => _materialsUsed.containsKey(m),
      emptyMessage: (q) => 'No material matching "$q"',
    );
    if (picked != null && mounted) {
      setState(() {
        _materialsUsed[picked] = (_materialsUsed[picked] ?? 0) + 1;
      });
      _markDirtyAndSave();
    }
  }

  Future<void> _saveAndLockSignature() async {
    if (!_signatureController.isEmpty) {
      final dataUrl = await _signatureController.toDataUrl();
      if (dataUrl != null && mounted) {
        _draftSignature = dataUrl;
        _signatureController.clear();
      }
    }
    if (mounted) {
      setState(() => _isSignaturePadActive = false);
      _markDirtyAndSave();
    }
  }

  /*
  Widget _buildMaterialsCounterCard(bool isDark) {
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
                  child: Text('Materials Consumed On-Site',
                      style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 14),
            MaterialCounterRow(
              name: 'Drop Cable',
              unit: 'meters',
              count: _dropCableMeters,
              fieldKey: const ValueKey('counter_field_drop_cable'),
              onChanged: (v) {
                setState(() => _dropCableMeters = v);
                _markDirtyAndSave();
              },
            ),
            const Divider(height: 16),
            MaterialCounterRow(
              name: 'SC/APC Fast Connectors',
              unit: 'pcs',
              count: _fastConnectors,
              fieldKey: const ValueKey('counter_field_fast_connectors'),
              onChanged: (v) {
                setState(() => _fastConnectors = v);
                _markDirtyAndSave();
              },
            ),
            const Divider(height: 16),
            MaterialCounterRow(
              name: 'S-Clamps',
              unit: 'pcs',
              count: _sClamps,
              fieldKey: const ValueKey('counter_field_s_clamps'),
              onChanged: (v) {
                setState(() => _sClamps = v);
                _markDirtyAndSave();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_outlined,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proof of Service (GPS Geotagged)',
                    style: context.text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Capture photos of the repaired hardware, drop line, and residence.',
              style: context.text.labelSmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PhotoCaptureTile(
                    label: 'Modem Setup',
                    hint: 'Modem lights',
                    icon: Icons.router_rounded,
                    value: _photo1,
                    pick: (source) =>
                        ImageCaptureService.instance.pickAsDataUrl(source),
                    onChanged: (v) {
                      setState(() => _photo1 = v);
                      _markDirtyAndSave();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PhotoCaptureTile(
                    label: 'Drop / NAP',
                    hint: 'Drop cable',
                    icon: Icons.alt_route_rounded,
                    value: _photo2,
                    pick: (source) =>
                        ImageCaptureService.instance.pickAsDataUrl(source),
                    onChanged: (v) {
                      setState(() => _photo2 = v);
                      _markDirtyAndSave();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PhotoCaptureTile(
                    label: 'House Front',
                    hint: 'House facade',
                    icon: Icons.home_rounded,
                    value: _photo3,
                    pick: (source) =>
                        ImageCaptureService.instance.pickAsDataUrl(source),
                    onChanged: (v) {
                      setState(() => _photo3 = v);
                      _markDirtyAndSave();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.draw_rounded,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Subscriber Sign-off',
                      style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SignaturePad(controller: _signatureController),
          ],
        ),
      ),
    );
  }
  */
  // Gene - Nov, 23, 2026: Dynamic CatalogService materials (with quick-add chips & searchable picker), 2-col photo grid, and lockable signature pad.
  Widget _buildMaterialsCounterCard(bool isDark) {
    const quickMaterials = [
      (label: 'Drop Cable (m)', aliases: ['drop cable']),
      (
        label: 'SC/APC Fast Connector',
        aliases: ['fast connector', 'sc connector']
      ),
      (
        label: 'Patch Cord',
        aliases: ['apc-sc to apc-sc (green)', 'patch cord']
      ),
      (label: 'S-Clamp', aliases: ['s-clamp', 'clamp']),
      (label: 'Fiber Wall Plate', aliases: ['fiber wall plate', 'ioo box']),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Materials Consumed On-Site',
                      style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Gene - Nov, 23, 2026: 1-tap import banner when Drop Cable Estimator stages a BOM.
            SignalBuilder(
              builder: (context) {
                final staged = BomHandoffService.instance.pendingBom.value;
                if (staged == null) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySubtleBgOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primarySubtleBorderOf(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calculate_outlined,
                              size: 20, color: AppTheme.brandInkOf(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              staged.summary.isNotEmpty
                                  ? 'Import Toolkit BOM (${staged.summary})'
                                  : 'Import calculated BOM from Toolkit',
                              style: context.text.labelLarge!.copyWith(
                                color: AppTheme.brandInkOf(context),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss BOM',
                            onPressed: BomHandoffService.instance.clear,
                            icon: Icon(Icons.close_rounded,
                                size: 20, color: AppTheme.brandInkOf(context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          key: const ValueKey('import_toolkit_bom_button'),
                          onPressed: () {
                            const aliasMap = <String, List<String>>{
                              'Drop Cable (m)': ['drop cable'],
                              'SC/APC Fast Connector': [
                                'fast connector',
                                'sc connector',
                              ],
                              'S-Clamp': ['s-clamp', 'clamp'],
                              'Patch Cord': [
                                'apc-sc to apc-sc (green)',
                                'patch cord',
                              ],
                              'Fiber Wall Plate': [
                                'fiber wall plate',
                                'ioo box',
                              ],
                            };
                            setState(() {
                              for (final e in staged.materials.entries) {
                                final resolved = _resolveCatalogMaterialName(
                                  e.key,
                                  aliasMap[e.key] ?? const [],
                                );
                                _materialsUsed[resolved] =
                                    (_materialsUsed[resolved] ?? 0) + e.value;
                              }
                            });
                            BomHandoffService.instance.clear();
                            _markDirtyAndSave();
                          },
                          icon: const Icon(Icons.download_rounded, size: 20),
                          label: const Text('Import'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickMaterials
                  .map(
                    (item) => ActionChip(
                      key: ValueKey(
                          'service_order_quick_material_${_materialKeySlug(item.label)}'),
                      label: Text('+ ${item.label}'),
                      onPressed: () =>
                          _quickAddMaterial(item.label, item.aliases),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                key: const ValueKey('service_order_add_material_button'),
                onPressed: () => _showMaterialPickerDialog(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add Other Material...'),
              ),
            ),
            const SizedBox(height: 14),
            if (_materialsUsed.isEmpty)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.fillOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                child: Text(
                  'No materials added yet. Tap a quick-add chip or Add Other Material.',
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall!.copyWith(
                    color: AppTheme.secondaryInkOf(context),
                  ),
                ),
              )
            else
              for (final entry in _materialsUsed.entries.toList()) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: MaterialCounterRow(
                          name: entry.key,
                          unit: _unitForMaterial(entry.key),
                          count: entry.value,
                          minusKey: ValueKey(
                              'counter_minus_${_materialKeySlug(entry.key)}'),
                          fieldKey: ValueKey(
                              'counter_field_${_materialKeySlug(entry.key)}'),
                          plusKey: ValueKey(
                              'counter_plus_${_materialKeySlug(entry.key)}'),
                          onChanged: (v) {
                            setState(() {
                              if (v <= 0) {
                                _materialsUsed.remove(entry.key);
                              } else {
                                _materialsUsed[entry.key] = v;
                              }
                            });
                            _markDirtyAndSave();
                          },
                        ),
                      ),
                      IconButton(
                        key: ValueKey(
                            'service_order_remove_material_${_materialKeySlug(entry.key)}'),
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: AppTheme.secondaryInkOf(context),
                        tooltip: 'Remove ${entry.key}',
                        onPressed: () {
                          setState(() => _materialsUsed.remove(entry.key));
                          _markDirtyAndSave();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_outlined,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proof of Service (GPS Geotagged)',
                    style: context.text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Capture photos of the repaired hardware, drop line, and residence.',
              style: context.text.labelSmall,
            ),
            const SizedBox(height: 12),
            GridView.count(
              key: const ValueKey('service_order_photos_grid'),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio:
                  (MediaQuery.textScalerOf(context).scale(16) / 16) > 1.2
                      ? 0.72
                      : 0.98,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                PhotoCaptureTile(
                  label: 'Modem Setup',
                  hint: 'Modem lights',
                  icon: Icons.router_rounded,
                  value: _photo1,
                  pick: (source) =>
                      ImageCaptureService.instance.pickAsDataUrl(source),
                  onChanged: (v) {
                    setState(() => _photo1 = v);
                    _markDirtyAndSave();
                  },
                ),
                PhotoCaptureTile(
                  label: 'Drop / NAP',
                  hint: 'Drop cable',
                  icon: Icons.alt_route_rounded,
                  value: _photo2,
                  pick: (source) =>
                      ImageCaptureService.instance.pickAsDataUrl(source),
                  onChanged: (v) {
                    setState(() => _photo2 = v);
                    _markDirtyAndSave();
                  },
                ),
                PhotoCaptureTile(
                  label: 'House Front',
                  hint: 'House facade',
                  icon: Icons.home_rounded,
                  value: _photo3,
                  pick: (source) =>
                      ImageCaptureService.instance.pickAsDataUrl(source),
                  onChanged: (v) {
                    setState(() => _photo3 = v);
                    _markDirtyAndSave();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureCard(bool isDark) {
    final existing = _draftSignature ?? _findOrder()?.clientSignature;
    final existingBytes = PhotoStorageService.instance.resolveBytes(existing) ??
        DataUrl.decode(existing);
    final muted = AppTheme.secondaryInkOf(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.draw_rounded,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Subscriber Sign-off',
                      style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_isSignaturePadActive && existingBytes != null) ...[
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.success.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(existingBytes,
                    cacheWidth: 600, fit: BoxFit.contain),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded,
                          size: 20, color: AppTheme.success),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Signature saved · Locked',
                          style: context.text.labelMedium!.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  FilledButton.tonal(
                    key:
                        const ValueKey('service_order_unlock_signature_button'),
                    onPressed: () {
                      _signatureController.clear();
                      setState(() {
                        _draftSignature = null;
                        _isSignaturePadActive = true;
                      });
                      _markDirtyAndSave();
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_open_rounded, size: 20),
                        SizedBox(width: 8),
                        Flexible(child: Text('Unlock to sign')),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (!_isSignaturePadActive) ...[
              Container(
                constraints: const BoxConstraints(minHeight: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _isSignaturePadActive = true),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.draw_rounded,
                              size: 28,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Tap to sign',
                            style: context.text.titleSmall!.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.brandInkOf(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  size: 20, color: muted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Locked to prevent scroll marks',
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall!
                                      .copyWith(color: muted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: const ValueKey('service_order_unlock_signature_button'),
                  onPressed: () => setState(() => _isSignaturePadActive = true),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_open_rounded, size: 20),
                      SizedBox(width: 8),
                      Flexible(child: Text('Unlock to sign')),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_rounded,
                              size: 20, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Signing active · Sign in box',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelSmall!.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey(
                                'service_order_lock_signature_button'),
                            onPressed: _saveAndLockSignature,
                            icon: const Icon(Icons.check_rounded, size: 20),
                            label: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    SignaturePad(
                      controller: _signatureController,
                      enabled: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    key: const ValueKey('service_order_clear_signature_button'),
                    onPressed: () {
                      _signatureController.clear();
                      setState(() => _draftSignature = null);
                      _markDirtyAndSave();
                    },
                    icon: const Icon(Icons.backspace_outlined, size: 20),
                    label: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
