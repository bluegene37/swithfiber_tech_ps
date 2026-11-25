import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
// Gene - Nov, 25, 2026: Added services.dart, image_picker, AppConstants, SecureStorageService, StatusStamp, AuthSignals, and ServiceOrderImages/SitePhotosCard for full Repair Report & image sync.
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/draft_storage_service.dart';
import '../../../core/services/image_capture_service.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../../core/utils/data_url.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/action_pair.dart';
import '../../../core/widgets/adaptive_dialogs.dart';
import '../../../core/widgets/status_stamp.dart';
import '../../../core/widgets/sticky_action_bar.dart';
// Gene - Nov, 25, 2026: Added WorkTimingLockBanner to communicate Start/Finish lock state on Service Order details.
import '../../../core/widgets/work_timing_bar.dart';
import '../../auth/signals/auth_signals.dart';
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
import '../models/service_order_images_model.dart';
import '../models/service_order_model.dart';
import '../signals/service_orders_signals.dart';
import '../widgets/service_order_site_photos_card.dart';

/// Detailed view and completion form for a Service Order (repair, swap, pullout).
class ServiceOrderDetailScreen extends StatefulWidget {
  final int orderId;
  final ServiceOrdersSignals signals;
  final Future<String?> Function(BuildContext context)? scanBarcode;
  // Gene - Nov, 25, 2026: Optional injectable image picker for deterministic widget testing.
  final Future<String?> Function(ImageSource source)? pickImage;
  // Gene - Nov, 23, 2026: Optional LcpNapSignals and JobsSignals to allow deep linking from repair ticket to assigned NAP pole.
  final LcpNapSignals? lcpNapSignals;
  final JobsSignals? jobsSignals;

  const ServiceOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.signals,
    this.scanBarcode,
    this.pickImage,
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
  // Gene - Nov, 25, 2026: Added structured Repair Report controllers & state (crew, repair category, service charge, pullout model/CPE, plant reassignment, and separate 4th photo slot).
  late final TextEditingController _visitWithOthersController;
  late final TextEditingController _serviceChargeController;
  late final TextEditingController _pulloutCpeSnController;
  late final TextEditingController _connectionRemarksController;
  late final TextEditingController _newVlanController;

  String? _selectedRouterModel;
  String? _pulloutRouterModel;
  String _visitStatus = 'Done';
  String? _repairCategory;
  String? _visitBy;
  String? _visitWith;
  String? _newLcp;
  String? _newNap;
  String? _newPort;
  String? _newPlan;
  bool _plantReassignmentExpanded = false;
  late final DateTime _reportStartedAt;

  List<RouterDto> _availableRouters = CatalogService.fallbackRouters;
  List<String> _availableTechnicians = CatalogService.fallbackTechnicians;
  List<LcpOptionDto> _availableLcps = CatalogService.fallbackLcps;
  List<NapDto> _availableNaps = CatalogService.fallbackNaps;
  List<PortDto> _availablePorts = CatalogService.fallbackPorts;
  List<PlanDto> _availablePlans = CatalogService.fallbackPlans;

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

  // Photos (Data URLs or local file paths; '' indicates explicit removal)
  String? _photo1;
  String? _photo2;
  String? _photo3;
  String? _houseFrontPhoto;
  ServiceOrderImagesDto? _serverImages;

  bool _isSubmitting = false;

  // Gene - Nov, 23, 2026: Added draft auto-save, signature restoration, and PopScope unsaved-changes guard.
  bool _hasUnsavedChanges = false;
  bool _draftRestored = false;
  bool _isApplyingProgrammaticText = false;
  Timer? _draftDebounce;
  String? _draftSignature;
  bool _signatureCleared = false;

  static const List<String> _visitStatusOptions = [
    'In Progress',
    'Done',
    'Pending',
    'Reschedule',
  ];

  static const List<String> _repairCategoryOptions = [
    'Resplice',
    'Replace Patch Cord',
    'Fiber Relaying',
    'Replace Router',
    'Transfer LCP / NAP / PORT',
    'Relocate Router',
    'Update VLAN',
    'Reboot/Reconfig Router',
    'Migrate',
    'Pullout',
    'Retain',
    'Reconfig',
    'Others',
  ];

  static String _todayIsoDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String _normalizeVisitStatus(String? raw) {
    final clean = raw?.trim() ?? '';
    if (clean.isEmpty) return 'Done';
    for (final opt in _visitStatusOptions) {
      if (opt.toLowerCase() == clean.toLowerCase()) return opt;
    }
    if (clean.toLowerCase() == 'inprogress') return 'In Progress';
    return 'Done';
  }

  static String? _initialRepairCategory(ServiceOrderDto? order) {
    if (order == null) return null;
    final existing = order.repairCategory?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final concern = order.concern.trim();
    if (concern.isNotEmpty) return concern;
    return null;
  }

  @override
  void initState() {
    super.initState();
    final order = _findOrder();
    _reportStartedAt = order?.startTimestamp ?? DateTime.now();
    _remarksController = TextEditingController(text: order?.visitRemarks ?? '');
    _newSnController =
        TextEditingController(text: order?.newRouterModemSN ?? '');
    _pulloutSnController = TextEditingController(
        text: order?.pulloutRouterModelSN ?? order?.routerModemSN ?? '');
    _pulloutRemarksController =
        TextEditingController(text: order?.pulloutRemarks ?? '');
    _visitWithOthersController =
        TextEditingController(text: order?.visitWithOthers ?? '');
    _serviceChargeController = TextEditingController(
      text: (order != null && order.serviceCharge > 0)
          ? (order.serviceCharge == order.serviceCharge.roundToDouble()
              ? order.serviceCharge.toInt().toString()
              : order.serviceCharge.toStringAsFixed(2))
          : '',
    );
    _pulloutCpeSnController =
        TextEditingController(text: order?.pulloutCPESN ?? '');
    _connectionRemarksController =
        TextEditingController(text: order?.connectionRemarks ?? '');
    _newVlanController = TextEditingController(text: order?.newVLAN ?? '');

    // Materials & report prefill
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
      /*
      _photo1 = order.image1;
      _photo2 = order.image2;
      _photo3 = order.houseFrontPicture ?? order.image3;
      */
      // Gene - Nov, 25, 2026: Keep image3 and houseFrontPicture as independent photo slots.
      _photo1 = order.image1;
      _photo2 = order.image2;
      _photo3 = order.image3;
      _houseFrontPhoto = order.houseFrontPicture;

      _visitStatus = _normalizeVisitStatus(order.visitStatus);
      _repairCategory = _initialRepairCategory(order);
      _visitBy = order.visitBy?.trim().isNotEmpty == true
          ? order.visitBy!.trim()
          : (AuthSignals.instance.currentUser.value?.fullName ??
              widget.signals.technicianEmail.value);
      _visitWith = order.visitWith?.trim().isNotEmpty == true &&
              order.visitWith!.trim().toLowerCase() != 'none'
          ? order.visitWith!.trim()
          : null;
      _pulloutRouterModel = order.pulloutRouterModel?.trim().isNotEmpty == true
          ? order.pulloutRouterModel!.trim()
          : null;
      _newLcp = order.newLCP?.trim().isNotEmpty == true ? order.newLCP : null;
      _newNap = order.newNAP?.trim().isNotEmpty == true ? order.newNAP : null;
      _newPort =
          order.newPORT?.trim().isNotEmpty == true ? order.newPORT : null;
      _newPlan =
          order.newPLAN?.trim().isNotEmpty == true ? order.newPLAN : null;

      final catLower = (_repairCategory ?? order.concern).toLowerCase();
      _plantReassignmentExpanded = _newLcp != null ||
          _newNap != null ||
          _newPort != null ||
          _newVlanController.text.trim().isNotEmpty ||
          _newPlan != null ||
          catLower.contains('transfer') ||
          catLower.contains('relocat') ||
          catLower.contains('vlan') ||
          catLower.contains('migrat');
    }

    // Show what is on file straight away; the catalog request that follows
    // can take seconds on a poor link and must not leave the model blank
    // or overwrite a choice made while it was in flight.
    _selectedRouterModel = _initialRouterModel(_availableRouters);
    _loadCatalog();
    unawaited(_loadServerImages());
    unawaited(_restoreVisitWithForToday());

    _remarksController.addListener(_onDraftControllerEdited);
    _newSnController.addListener(_onDraftControllerEdited);
    _pulloutSnController.addListener(_onDraftControllerEdited);
    _pulloutRemarksController.addListener(_onDraftControllerEdited);
    _visitWithOthersController.addListener(_onDraftControllerEdited);
    _serviceChargeController.addListener(_onDraftControllerEdited);
    _pulloutCpeSnController.addListener(_onDraftControllerEdited);
    _connectionRemarksController.addListener(_onDraftControllerEdited);
    _newVlanController.addListener(_onDraftControllerEdited);
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
  /*
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
  */
  // Gene - Nov, 25, 2026: Load routers, materials, technicians, LCPs, NAPs, ports, and plans concurrently for the Repair Report form.
  Future<void> _loadCatalog() async {
    final results = await Future.wait([
      CatalogService.instance.getRouters(),
      CatalogService.instance.getMaterials(),
      CatalogService.instance.getTechnicians(),
      CatalogService.instance.getLcps(),
      CatalogService.instance.getNaps(),
      CatalogService.instance.getPorts(),
      CatalogService.instance.getPlans(),
    ]);
    if (!mounted) return;
    final routers = results[0] as List<RouterDto>;
    final materials = results[1] as List<String>;
    final techs = results[2] as List<String>;
    final lcps = results[3] as List<LcpOptionDto>;
    final naps = results[4] as List<NapDto>;
    final ports = results[5] as List<PortDto>;
    final plans = results[6] as List<PlanDto>;
    setState(() {
      _availableRouters = routers;
      _availableMaterials = materials;
      _availableTechnicians = techs;
      _availableLcps = lcps;
      _availableNaps = naps;
      _availablePorts = ports;
      _availablePlans = plans;
      if (_selectedRouterModel?.trim().isNotEmpty != true) {
        _selectedRouterModel = _initialRouterModel(routers);
      }
    });
  }

  Future<void> _loadServerImages() async {
    try {
      final imgs = await widget.signals.getServiceOrderImages(widget.orderId);
      if (mounted && imgs != null) {
        setState(() => _serverImages = imgs);
      }
    } catch (_) {}
  }

  Future<void> _restoreVisitWithForToday() async {
    if (_visitWith != null && _visitWith!.trim().isNotEmpty) return;
    try {
      final storedDate = await SecureStorageService.instance
          .read(AppConstants.keyLastVisitWithDate);
      final storedPartner = await SecureStorageService.instance
          .read(AppConstants.keyLastVisitWith);
      if (!mounted || _draftRestored) return;
      if (_visitWith == null &&
          storedDate == _todayIsoDate() &&
          storedPartner != null &&
          storedPartner.trim().isNotEmpty) {
        setState(() => _visitWith = storedPartner.trim());
      }
    } catch (_) {}
  }

  Future<void> _persistVisitWithForToday(String? val) async {
    try {
      await SecureStorageService.instance.write(
        AppConstants.keyLastVisitWith,
        val?.trim() ?? '',
      );
      await SecureStorageService.instance.write(
        AppConstants.keyLastVisitWithDate,
        _todayIsoDate(),
      );
    } catch (_) {}
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
    _visitWithOthersController.removeListener(_onDraftControllerEdited);
    _serviceChargeController.removeListener(_onDraftControllerEdited);
    _pulloutCpeSnController.removeListener(_onDraftControllerEdited);
    _connectionRemarksController.removeListener(_onDraftControllerEdited);
    _newVlanController.removeListener(_onDraftControllerEdited);
    _signatureController.removeListener(_onDraftControllerEdited);
    _signatureController.dispose();
    _remarksController.dispose();
    _newSnController.dispose();
    _pulloutSnController.dispose();
    _pulloutRemarksController.dispose();
    _visitWithOthersController.dispose();
    _serviceChargeController.dispose();
    _pulloutCpeSnController.dispose();
    _connectionRemarksController.dispose();
    _newVlanController.dispose();
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
    final materials = <String, int>{
      for (final entry in _materialsUsed.entries)
        if (entry.value > 0) entry.key: entry.value,
    };

    await DraftStorageService.instance.saveDraft(_draftKey, {
      'remarks': _remarksController.text,
      'newSn': _newSnController.text,
      'pulloutSn': _pulloutSnController.text,
      'pulloutRemarks': _pulloutRemarksController.text,
      'visitWithOthers': _visitWithOthersController.text,
      'serviceCharge': _serviceChargeController.text,
      'pulloutCpeSn': _pulloutCpeSnController.text,
      'connectionRemarks': _connectionRemarksController.text,
      'newVlan': _newVlanController.text,
      'visitStatus': _visitStatus,
      'repairCategory': _repairCategory,
      'visitBy': _visitBy,
      'visitWith': _visitWith,
      'newLcp': _newLcp,
      'newNap': _newNap,
      'newPort': _newPort,
      'newPlan': _newPlan,
      'routerModel': _selectedRouterModel,
      'pulloutRouterModel': _pulloutRouterModel,
      'materialsUsed': materials,
      'photo1': _photo1,
      'photo2': _photo2,
      'photo3': _photo3,
      'houseFrontPhoto': _houseFrontPhoto,
      'signature': sig,
      'signatureCleared': _signatureCleared,
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
        final visitWithOthers = draft['visitWithOthers'] as String?;
        if (visitWithOthers != null) {
          _visitWithOthersController.text = visitWithOthers;
        }
        final serviceCharge = draft['serviceCharge'] as String?;
        if (serviceCharge != null) {
          _serviceChargeController.text = serviceCharge;
        }
        final pulloutCpeSn = draft['pulloutCpeSn'] as String?;
        if (pulloutCpeSn != null) {
          _pulloutCpeSnController.text = pulloutCpeSn;
        }
        final connRemarks = draft['connectionRemarks'] as String?;
        if (connRemarks != null) {
          _connectionRemarksController.text = connRemarks;
        }
        final newVlan = draft['newVlan'] as String?;
        if (newVlan != null) _newVlanController.text = newVlan;
        if (draft['visitStatus'] is String) {
          _visitStatus = _normalizeVisitStatus(draft['visitStatus'] as String);
        }
        if (draft.containsKey('repairCategory')) {
          _repairCategory = draft['repairCategory'] as String?;
        }
        if (draft.containsKey('visitBy')) {
          _visitBy = draft['visitBy'] as String?;
        }
        if (draft.containsKey('visitWith')) {
          _visitWith = draft['visitWith'] as String?;
        }
        if (draft.containsKey('newLcp')) {
          _newLcp = draft['newLcp'] as String?;
        }
        if (draft.containsKey('newNap')) {
          _newNap = draft['newNap'] as String?;
        }
        if (draft.containsKey('newPort')) {
          _newPort = draft['newPort'] as String?;
        }
        if (draft.containsKey('newPlan')) {
          _newPlan = draft['newPlan'] as String?;
        }
        if (draft.containsKey('routerModel')) {
          _selectedRouterModel = draft['routerModel'] as String?;
        }
        if (draft.containsKey('pulloutRouterModel')) {
          _pulloutRouterModel = draft['pulloutRouterModel'] as String?;
        }
        final matsRaw = draft['materialsUsed'];
        if (matsRaw is Map) {
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
        if (draft.containsKey('houseFrontPhoto')) {
          _houseFrontPhoto = draft['houseFrontPhoto'] as String?;
        }
        _draftSignature = draft['signature'] as String?;
        _signatureCleared = draft['signatureCleared'] == true;
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
        _visitWithOthersController.text = order?.visitWithOthers ?? '';
        _serviceChargeController.text =
            (order != null && order.serviceCharge > 0)
                ? (order.serviceCharge == order.serviceCharge.roundToDouble()
                    ? order.serviceCharge.toInt().toString()
                    : order.serviceCharge.toStringAsFixed(2))
                : '';
        _pulloutCpeSnController.text = order?.pulloutCPESN ?? '';
        _connectionRemarksController.text = order?.connectionRemarks ?? '';
        _newVlanController.text = order?.newVLAN ?? '';
        _visitStatus = _normalizeVisitStatus(order?.visitStatus);
        _repairCategory = _initialRepairCategory(order);
        _visitBy = order?.visitBy?.trim().isNotEmpty == true
            ? order!.visitBy!.trim()
            : (AuthSignals.instance.currentUser.value?.fullName ??
                widget.signals.technicianEmail.value);
        _visitWith = order?.visitWith?.trim().isNotEmpty == true &&
                order!.visitWith!.trim().toLowerCase() != 'none'
            ? order.visitWith!.trim()
            : null;
        _newLcp =
            order?.newLCP?.trim().isNotEmpty == true ? order!.newLCP : null;
        _newNap =
            order?.newNAP?.trim().isNotEmpty == true ? order!.newNAP : null;
        _newPort =
            order?.newPORT?.trim().isNotEmpty == true ? order!.newPORT : null;
        _newPlan =
            order?.newPLAN?.trim().isNotEmpty == true ? order!.newPLAN : null;
        _pulloutRouterModel =
            order?.pulloutRouterModel?.trim().isNotEmpty == true
                ? order!.pulloutRouterModel!.trim()
                : null;
        _materialsUsed = order == null
            ? <String, int>{}
            : {
                for (final e in order.materialsUsed.entries)
                  if (e.value > 0) e.key: e.value,
              };
        _photo1 = order?.image1;
        _photo2 = order?.image2;
        _photo3 = order?.image3;
        _houseFrontPhoto = order?.houseFrontPicture;
        _selectedRouterModel = _initialRouterModel(_availableRouters);
        _draftSignature = null;
        _signatureCleared = false;
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
    // Gene - Nov, 26, 2026: Reject Service Order report/completion submission unless started and not finished.
    if (!order.isWorkUnlocked) return;
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

    /*
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
    */
    // Gene - Nov, 25, 2026: Use order.copyWith to preserve server metadata/rawJson, persist all Repair Report fields, and honor explicit photo clears.
    final now = DateTime.now();
    final isDone = _visitStatus == 'Done';
    final nextSupportStatus = isDone
        ? 'Resolved'
        : (_visitStatus == 'In Progress' ? 'In Progress' : order.supportStatus);
    final parsedCharge =
        double.tryParse(_serviceChargeController.text.trim()) ??
            order.serviceCharge;
    final techEmail = widget.signals.technicianEmail.value?.trim();
    final resolvedVisitBy = (_visitBy?.trim().isNotEmpty == true)
        ? _visitBy!.trim()
        : (AuthSignals.instance.currentUser.value?.fullName ??
            techEmail ??
            order.visitBy ??
            'Technician');

    final updated = order.copyWith(
      supportStatus: nextSupportStatus,
      visitStatus: _visitStatus,
      visitBy: resolvedVisitBy,
      visitWith:
          _visitWith?.trim().isNotEmpty == true ? _visitWith!.trim() : '',
      visitWithOthers: _visitWithOthersController.text.trim(),
      visitRemarks: _remarksController.text.trim(),
      repairCategory: _repairCategory?.trim().isNotEmpty == true
          ? _repairCategory!.trim()
          : order.repairCategory,
      connectionRemarks: _connectionRemarksController.text.trim(),
      newRouterModemSN: _newSnController.text.trim(),
      newLCP: _newLcp ?? order.newLCP,
      newNAP: _newNap ?? order.newNAP,
      newPORT: _newPort ?? order.newPORT,
      newVLAN: _newVlanController.text.trim(),
      newPLAN: _newPlan ?? order.newPLAN,
      routerModel: _selectedRouterModel,
      pulloutRouterModel: _pulloutRouterModel ?? order.pulloutRouterModel,
      pulloutRouterModelSN: _pulloutSnController.text.trim(),
      pulloutCPESN: _pulloutCpeSnController.text.trim(),
      pulloutRemarks: _pulloutRemarksController.text.trim(),
      serviceCharge: parsedCharge,
      startTimestamp: order.startTimestamp ?? _reportStartedAt,
      stopTimestamp: isDone ? now : order.stopTimestamp,
      modifiedBy: resolvedVisitBy,
      modifiedDate: now,
      techModifiedDate: now,
      userEmail: (techEmail != null && techEmail.isNotEmpty)
          ? techEmail
          : order.userEmail,
      materialsUsed: materials,
      clientSignature: signature ??
          (_signatureCleared ? '' : (_draftSignature ?? order.clientSignature)),
      image1: _photo1 ?? order.image1,
      image2: _photo2 ?? order.image2,
      image3: _photo3 ?? order.image3,
      houseFrontPicture: _houseFrontPhoto ?? order.houseFrontPicture,
    );

    if (_visitWith != null && _visitWith!.trim().isNotEmpty) {
      unawaited(_persistVisitWithForToday(_visitWith));
    }

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
        SnackBar(
          content: Text(
            isDone
                ? 'Service Order marked as Completed!'
                : 'Repair report saved and queued for sync.',
          ),
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

  void _copyRepairSummary(
    BuildContext context,
    ServiceOrderDto order,
    bool isDark,
  ) {
    final lines = <String>[
      'Switch Fiber Repair Report: SO-${order.id.toString().padLeft(4, '0')}',
      'Account: ${order.accountNumber} · ${order.fullName}',
      'Concern: ${order.concern}',
      if (_repairCategory?.trim().isNotEmpty == true)
        'Repair Category: ${_repairCategory!.trim()}',
      'Visit Status: $_visitStatus',
      if (_visitWith?.trim().isNotEmpty == true)
        'Crew Partner: ${_visitWith!.trim()}',
      if (_remarksController.text.trim().isNotEmpty)
        'Remarks: ${_remarksController.text.trim()}',
      if (_materialsUsed.isNotEmpty)
        'Materials: ${_materialsUsed.entries.map((e) => '${e.key} x${e.value}').join(', ')}',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Repair report summary copied to clipboard!'),
        backgroundColor: isDark ? AppTheme.darkCard : AppTheme.darkSlate,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
              // Gene - Nov, 25, 2026: Added sync badge, StatusStamp, and Copy Repair Report button to ServiceOrderDetailScreen AppBar.
              actions: [
                Tooltip(
                  message: order.isSynced
                      ? 'Synced with the server'
                      : 'Saved on phone, not yet synced',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      order.isSynced
                          ? Icons.cloud_done_rounded
                          : Icons.cloud_off_rounded,
                      size: 22,
                      color: order.isSynced
                          ? AppTheme.successInkOf(context)
                          : AppTheme.warningInkOf(context),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: StatusStamp(
                      label: order.visitStatus?.trim().isNotEmpty == true
                          ? order.visitStatus!
                          : order.supportStatus,
                      color: order.isDone
                          ? AppTheme.successInkOf(context)
                          : AppTheme.infoInkOf(context),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('service_order_share_report_button'),
                  icon: const Icon(Icons.share_outlined, size: 24),
                  tooltip: 'Copy Repair Report',
                  onPressed: () => _copyRepairSummary(context, order, isDark),
                ),
              ],
            ),
            // The screen's one red verb, pinned where the job detail pins its
            // own (DESIGN.md: read at the top, act at the bottom).
            // Gene - Nov, 25, 2026: Gate repair/report submission until technician clicks Start in the list (and re-lock after Finish).
            /*
            bottomNavigationBar: StickyActionBar(
              label: _isSubmitting
                  ? 'Saving…'
                  : (_visitStatus == 'Done'
                      ? 'Complete service order'
                      : 'Save repair report'),
              icon: Icons.check_circle_rounded,
              onPressed: _isSubmitting ? null : () => _handleSubmit(order),
            ),
            */
            bottomNavigationBar: !order.isWorkUnlocked
                ? null
                : StickyActionBar(
                    label: _isSubmitting
                        ? 'Saving…'
                        : (_visitStatus == 'Done'
                            ? 'Complete service order'
                            : 'Save repair report'),
                    icon: Icons.check_circle_rounded,
                    onPressed:
                        _isSubmitting ? null : () => _handleSubmit(order),
                  ),
            body: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildDraftRestoredBanner(),
                  // Gene - Nov, 25, 2026: Display Start/Finish timing lock banner when Service Order editing is locked.
                  if (!order.isWorkUnlocked)
                    WorkTimingLockBanner(
                      key: const ValueKey('service_order_timing_lock_banner'),
                      status: order.isOpen
                          ? order.workTimingStatus
                          : WorkTimingStatus.finished,
                      startTime: order.startTimestamp,
                      endTime: order.stopTimestamp,
                    ),
                  // 1. Concern & Subscriber Card
                  _buildSubscriberCard(order, isDark),
                  const SizedBox(height: 16),

                  // 2. Plant & Hardware Allocation (2x2 Instrument Grid)
                  _buildPlantAndHardwareCard(order, isDark),
                  const SizedBox(height: 16),

                  // 3. Hardware Swaps & Pullout Card
                  IgnorePointer(
                    ignoring: !order.isWorkUnlocked,
                    child: Opacity(
                      opacity: order.isWorkUnlocked ? 1.0 : 0.58,
                      child: _buildHardwareSwapCard(order, isDark),
                    ),
                  ),
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
                  IgnorePointer(
                    ignoring: !order.isWorkUnlocked,
                    child: Opacity(
                      opacity: order.isWorkUnlocked ? 1.0 : 0.58,
                      child: _buildMaterialsCounterCard(isDark),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gene - Nov, 25, 2026: Render structured Field Repair Report card and remote/local Site Photo Proofs gallery.
                  // 5. Field Repair Report (Status, Category, Crew, Charge, Pullout Model/CPE, Reassignment)
                  IgnorePointer(
                    ignoring: !order.isWorkUnlocked,
                    child: Opacity(
                      opacity: order.isWorkUnlocked ? 1.0 : 0.58,
                      child: _buildRepairReportCard(order, isDark),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. Site Photo Proofs (from GetServiceOrderImage + local fallback)
                  ServiceOrderSitePhotosCard(
                    order: order,
                    signals: widget.signals,
                    onImagesLoaded: (imgs) {
                      if (mounted) {
                        setState(() => _serverImages = imgs);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // 7. Photos Proofs (with GPS EXIF)
                  IgnorePointer(
                    ignoring: !order.isWorkUnlocked,
                    child: Opacity(
                      opacity: order.isWorkUnlocked ? 1.0 : 0.58,
                      child: _buildPhotosCard(isDark),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 8. Subscriber Signature Pad
                  IgnorePointer(
                    ignoring: !order.isWorkUnlocked,
                    child: Opacity(
                      opacity: order.isWorkUnlocked ? 1.0 : 0.58,
                      child: _buildSignatureCard(isDark),
                    ),
                  ),
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
            /*
            if (order.houseFrontPicture != null &&
                order.houseFrontPicture!.trim().isNotEmpty) ...[
              _buildHouseFrontPicturePreview(order.houseFrontPicture!, isDark),
              const SizedBox(height: 14),
            ],
            */
            // Gene - Nov, 25, 2026: Show House Front Picture preview when resolved from GetServiceOrderImage or local/order field.
            if ((_serverImages?.houseFrontPicture?.hasImage == true) ||
                (order.houseFrontPicture != null &&
                    order.houseFrontPicture!.trim().isNotEmpty)) ...[
              _buildHouseFrontPicturePreview(
                order.houseFrontPicture ?? '',
                isDark,
                serverBytes: _serverImages?.houseFrontPicture?.bytes,
              ),
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

  /*
  // Gene - Oct 12, 2026: Added House Front Picture thumbnail preview and full-screen viewer per AppSheet Page 4 requirement.
  Widget _buildHouseFrontPicturePreview(String picture, bool isDark) {
    final clean = picture.trim();
    final bytes = PhotoStorageService.instance.resolveBytes(clean) ??
        DataUrl.decode(clean);
    final isHttp = clean.startsWith('http://') || clean.startsWith('https://');
  */
  // Gene - Nov, 25, 2026: Prefer fetched GetServiceOrderImage bytes for House Front preview and open remote URLs in closeable photo viewer.
  Widget _buildHouseFrontPicturePreview(
    String picture,
    bool isDark, {
    Uint8List? serverBytes,
  }) {
    final clean = picture.trim();
    final bytes = serverBytes ??
        PhotoStorageService.instance.resolveBytes(clean) ??
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
                showPhotoViewer(
                  context,
                  Uint8List(0),
                  title: 'House Front Picture',
                  imageUrl: clean,
                );
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_done_outlined,
                              size: 28,
                              color: AppTheme.secondaryInkOf(context),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Photo stored on server',
                              style: context.text.labelSmall!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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

  // Gene - Nov, 25, 2026: Added structured Field Repair Report card covering visit status, repair category, crew partner, service charge, diagnostic remarks, and optional plant/plan reassignment.
  Widget _buildRepairReportCard(ServiceOrderDto order, bool isDark) {
    final borderColor = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final lcpItems = _availableLcps.map((e) => e.name).toList();
    final napItems = _availableNaps.map((e) => e.name).toList();
    final portItems = _availablePorts.map((e) => e.name).toList();
    final planItems = _availablePlans.map((e) => e.name).toList();
    final techItems = ['None', ..._availableTechnicians];

    return Card(
      key: const ValueKey('service_order_repair_report_card'),
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
                    'Field Repair Report',
                    style: context.text.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Visit Status',
              style: context.text.labelMedium!.copyWith(
                color: AppTheme.secondaryInkOf(context),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in _visitStatusOptions)
                  ChoiceChip(
                    key: ValueKey(
                        'service_order_visit_status_${status.toLowerCase().replaceAll(' ', '_')}'),
                    label: Text(status),
                    selected: _visitStatus == status,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() => _visitStatus = status);
                      _markDirtyAndSave();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            PickerField(
              key: const ValueKey('service_order_repair_category_field'),
              label: 'Repair Category',
              value: _repairCategory?.trim(),
              placeholder: 'Select repair category...',
              icon: Icons.build_circle_outlined,
              onTap: () async {
                final picked = await SearchablePickerSheet.show<String>(
                  context,
                  title: 'Select Repair Category',
                  icon: Icons.build_circle_outlined,
                  searchHint: 'Filter repair categories...',
                  items: _repairCategoryOptions,
                  titleOf: (c) => c,
                  matches: (c, q) => c.toLowerCase().contains(q),
                  isSelected: (c) =>
                      c.toLowerCase() ==
                      (_repairCategory ?? '').trim().toLowerCase(),
                  emptyMessage: (q) => 'No category matching "$q"',
                );
                if (picked != null && mounted) {
                  setState(() {
                    _repairCategory = picked;
                    final lower = picked.toLowerCase();
                    if (lower.contains('transfer') ||
                        lower.contains('relocat') ||
                        lower.contains('vlan') ||
                        lower.contains('migrat')) {
                      _plantReassignmentExpanded = true;
                    }
                  });
                  _markDirtyAndSave();
                }
              },
            ),
            const SizedBox(height: 12),
            PickerField(
              key: const ValueKey('service_order_visit_with_field'),
              label: 'Crew Partner (Visit With)',
              value: _visitWith?.trim(),
              placeholder: 'Optional companion technician...',
              icon: Icons.group_outlined,
              onTap: () async {
                final picked = await SearchablePickerSheet.show<String>(
                  context,
                  title: 'Select Crew Partner',
                  icon: Icons.group_outlined,
                  searchHint: 'Search technician name...',
                  items: techItems,
                  titleOf: (t) => t,
                  matches: (t, q) => t.toLowerCase().contains(q),
                  isSelected: (t) =>
                      (_visitWith == null && t == 'None') ||
                      (_visitWith != null &&
                          t.toLowerCase() == _visitWith!.trim().toLowerCase()),
                  emptyMessage: (q) => 'No technician matching "$q"',
                );
                if (picked != null && mounted) {
                  setState(() {
                    _visitWith = picked == 'None' ? null : picked;
                  });
                  _markDirtyAndSave();
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('service_order_visit_with_others_field'),
              controller: _visitWithOthersController,
              decoration: const InputDecoration(
                labelText: 'Other Crew / Helper (Optional)',
                hintText: 'Names not in technician list',
                prefixIcon: Icon(Icons.person_add_alt_1_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('service_order_service_charge_field'),
              controller: _serviceChargeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Service Charge (PHP)',
                hintText: '0.00',
                prefixIcon: Icon(Icons.payments_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('service_order_connection_remarks_field'),
              controller: _connectionRemarksController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Connection / Diagnostic Remarks',
                hintText: 'e.g. Optical reading -19.2 dBm; LOS cleared',
                prefixIcon: Icon(Icons.network_check_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            // Gene - Nov, 25, 2026: Moved Pullout Modem Model picker and Pullout CPE Serial Number field into Field Repair Report card to preserve above-the-fold Hardware Swap layout.
            PickerField(
              key: const ValueKey('pullout_router_model_field'),
              label: 'Pullout Modem Model (Old)',
              value: _pulloutRouterModel?.trim(),
              placeholder: 'Select retrieved modem model...',
              icon: Icons.devices_other_rounded,
              onTap: () async {
                final picked = await RouterModelPicker.show(
                  context,
                  routers: _availableRouters,
                  selected: _pulloutRouterModel,
                );
                if (picked != null && mounted) {
                  setState(() => _pulloutRouterModel = picked);
                  _markDirtyAndSave();
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('pullout_cpe_sn_field'),
              controller: _pulloutCpeSnController,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
              decoration: InputDecoration(
                labelText: 'Pullout CPE Serial Number (Optional)',
                prefixIcon: const Icon(Icons.qr_code_2_rounded, size: 20),
                suffixIcon: IconButton(
                  key: const ValueKey('scan_pullout_cpe_serial_button'),
                  tooltip: 'Scan Pullout CPE Serial',
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  onPressed: () => _handleScanSerial(_pulloutCpeSnController),
                ),
                hintText: 'If different from router S/N',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkInput : AppTheme.lightBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Column(
                children: [
                  InkWell(
                    key: const ValueKey(
                        'service_order_plant_reassignment_toggle'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _plantReassignmentExpanded =
                        !_plantReassignmentExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.swap_calls_rounded,
                              size: 20, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Plant / Plan Reassignment (Transfer / Upgrade)',
                              style: context.text.titleSmall!.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            _plantReassignmentExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_plantReassignmentExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          PickerField(
                            key: const ValueKey('service_order_new_lcp_field'),
                            label: 'New LCP Cabinet',
                            value: _newLcp?.trim(),
                            placeholder:
                                'Keep current (${order.lcp ?? "None"})',
                            icon: Icons.storage_rounded,
                            onTap: () async {
                              final picked =
                                  await SearchablePickerSheet.show<String>(
                                context,
                                title: 'Select New LCP',
                                icon: Icons.storage_rounded,
                                searchHint: 'Filter LCP cabinets...',
                                items: lcpItems,
                                titleOf: (v) => v,
                                matches: (v, q) => v.toLowerCase().contains(q),
                                isSelected: (v) =>
                                    v.toLowerCase() ==
                                    (_newLcp ?? '').trim().toLowerCase(),
                                emptyMessage: (q) => 'No LCP matching "$q"',
                              );
                              if (picked != null && mounted) {
                                setState(() => _newLcp = picked);
                                _markDirtyAndSave();
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          PickerField(
                            key: const ValueKey('service_order_new_nap_field'),
                            label: 'New NAP Box',
                            value: _newNap?.trim(),
                            placeholder:
                                'Keep current (${order.nap ?? "None"})',
                            icon: Icons.alt_route_rounded,
                            onTap: () async {
                              final picked =
                                  await SearchablePickerSheet.show<String>(
                                context,
                                title: 'Select New NAP',
                                icon: Icons.alt_route_rounded,
                                searchHint: 'Filter NAP boxes...',
                                items: napItems,
                                titleOf: (v) => v,
                                matches: (v, q) => v.toLowerCase().contains(q),
                                isSelected: (v) =>
                                    v.toLowerCase() ==
                                    (_newNap ?? '').trim().toLowerCase(),
                                emptyMessage: (q) => 'No NAP matching "$q"',
                              );
                              if (picked != null && mounted) {
                                setState(() => _newNap = picked);
                                _markDirtyAndSave();
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          PickerField(
                            key: const ValueKey('service_order_new_port_field'),
                            label: 'New NAP Port',
                            value: _newPort?.trim(),
                            placeholder:
                                'Keep current (${order.port ?? "None"})',
                            icon: Icons.settings_ethernet_rounded,
                            onTap: () async {
                              final picked =
                                  await SearchablePickerSheet.show<String>(
                                context,
                                title: 'Select New Port',
                                icon: Icons.settings_ethernet_rounded,
                                searchHint: 'Filter ports...',
                                items: portItems,
                                titleOf: (v) => v,
                                matches: (v, q) => v.toLowerCase().contains(q),
                                isSelected: (v) =>
                                    v.toLowerCase() ==
                                    (_newPort ?? '').trim().toLowerCase(),
                                emptyMessage: (q) => 'No port matching "$q"',
                              );
                              if (picked != null && mounted) {
                                setState(() => _newPort = picked);
                                _markDirtyAndSave();
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            key: const ValueKey('service_order_new_vlan_field'),
                            controller: _newVlanController,
                            decoration: InputDecoration(
                              labelText: 'New VLAN',
                              hintText: order.vlan?.isNotEmpty == true
                                  ? 'Current: ${order.vlan}'
                                  : 'e.g. 100',
                              prefixIcon:
                                  const Icon(Icons.lan_outlined, size: 20),
                            ),
                          ),
                          const SizedBox(height: 10),
                          PickerField(
                            key: const ValueKey('service_order_new_plan_field'),
                            label: 'New Plan (Migration / Upgrade)',
                            value: _newPlan?.trim(),
                            placeholder:
                                'Keep current (${order.plan ?? "None"})',
                            icon: Icons.speed_rounded,
                            onTap: () async {
                              final picked =
                                  await SearchablePickerSheet.show<String>(
                                context,
                                title: 'Select New Plan',
                                icon: Icons.speed_rounded,
                                searchHint: 'Filter broadband plans...',
                                items: planItems,
                                titleOf: (v) => v,
                                matches: (v, q) => v.toLowerCase().contains(q),
                                isSelected: (v) =>
                                    v.toLowerCase() ==
                                    (_newPlan ?? '').trim().toLowerCase(),
                                emptyMessage: (q) => 'No plan matching "$q"',
                              );
                              if (picked != null && mounted) {
                                setState(() => _newPlan = picked);
                                _markDirtyAndSave();
                              }
                            },
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
        _signatureCleared = false;
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

  // Gene - Nov, 25, 2026: Resolve photo tile value preferring explicit local edits/clears, then fetched server DataUrl, then order field.
  String? _effectivePhotoValue(
    String? localVal,
    String? orderVal,
    ServiceOrderImageFileDto? serverFile,
  ) {
    if (localVal != null) {
      if (localVal.isEmpty) return '';
      final resolvedLocal =
          PhotoStorageService.instance.resolveBytes(localVal) ??
              DataUrl.decode(localVal);
      if (resolvedLocal != null) return localVal;
    }
    if (serverFile?.hasImage == true) {
      return serverFile!.dataUrl;
    }
    return localVal ?? orderVal;
  }

  Widget _buildPhotosCard(bool isDark) {
    final order = _findOrder();
    final pickFn =
        widget.pickImage ?? ImageCaptureService.instance.pickAsDataUrl;

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
              'Capture photos of the repaired hardware, drop line, repair proof, and residence.',
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
                  key: const ValueKey('service_order_photo_tile_1'),
                  label: 'Modem Setup',
                  hint: 'Modem lights',
                  icon: Icons.router_rounded,
                  value: _effectivePhotoValue(
                      _photo1, order?.image1, _serverImages?.image1),
                  pick: pickFn,
                  onChanged: (v) {
                    setState(() => _photo1 = v);
                    _markDirtyAndSave();
                  },
                ),
                PhotoCaptureTile(
                  key: const ValueKey('service_order_photo_tile_2'),
                  label: 'Drop / NAP',
                  hint: 'Drop cable',
                  icon: Icons.alt_route_rounded,
                  value: _effectivePhotoValue(
                      _photo2, order?.image2, _serverImages?.image2),
                  pick: pickFn,
                  onChanged: (v) {
                    setState(() => _photo2 = v);
                    _markDirtyAndSave();
                  },
                ),
                PhotoCaptureTile(
                  key: const ValueKey('service_order_photo_tile_3'),
                  label: 'Repair Proof',
                  hint: 'Splice / reading',
                  icon: CupertinoIcons.wrench_fill,
                  value: _effectivePhotoValue(
                      _photo3, order?.image3, _serverImages?.image3),
                  pick: pickFn,
                  onChanged: (v) {
                    setState(() => _photo3 = v);
                    _markDirtyAndSave();
                  },
                ),
                PhotoCaptureTile(
                  key: const ValueKey('service_order_photo_tile_house_front'),
                  label: 'House Front',
                  hint: 'House facade',
                  icon: Icons.home_rounded,
                  value: _effectivePhotoValue(
                      _houseFrontPhoto,
                      order?.houseFrontPicture,
                      _serverImages?.houseFrontPicture),
                  pick: pickFn,
                  onChanged: (v) {
                    setState(() => _houseFrontPhoto = v);
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
    final existing = _signatureCleared
        ? null
        : (_draftSignature ?? _findOrder()?.clientSignature);
    final existingBytes = _signatureCleared
        ? null
        : (PhotoStorageService.instance.resolveBytes(existing) ??
            DataUrl.decode(existing) ??
            _serverImages?.clientSignature?.bytes);
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
                        _signatureCleared = true;
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
                      setState(() {
                        _draftSignature = null;
                        _signatureCleared = true;
                      });
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
