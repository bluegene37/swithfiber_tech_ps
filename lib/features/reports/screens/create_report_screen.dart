import 'dart:async';

import 'package:flutter/material.dart';
// Gene - Oct 13, 2026: Added services.dart import for FilteringTextInputFormatter in dynamic materials input.
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/services/image_capture_service.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/port_tile_grid.dart';
import '../../../core/widgets/step_header.dart';
import '../../../core/widgets/sticky_action_bar.dart';
import '../../../core/utils/data_url.dart';
import '../../../core/widgets/material_counter_row.dart';
import '../../../core/widgets/searchable_picker_sheet.dart';
import '../../catalogs/models/catalog_model.dart';
import '../../catalogs/services/catalog_service.dart';
import '../../catalogs/widgets/router_model_picker.dart';
import '../../jobs/models/job_order_model.dart';
import '../../jobs/signals/jobs_signals.dart';
import '../../../core/widgets/serial_scanner_sheet.dart';
import '../signals/report_signals.dart';
// Gene - Oct 13, 2026: Commented out unused optical_power_gauge import since Optical reading was removed from report.
// import '../widgets/optical_power_gauge.dart';
import '../widgets/photo_capture_tile.dart';
import '../widgets/signature_pad.dart';

/// On-Site Completion Report form screen for optical power validation and subscriber sign-off.
class CreateReportScreen extends StatefulWidget {
  final JobsSignals jobsSignals;
  final ReportSignals reportSignals;

  /// Photo source; injected so tests can hand over an image without a camera.
  final Future<String?> Function(ImageSource source)? pickImage;

  /// Barcode scanner callback; injected so tests can supply mock scans without camera.
  final Future<String?> Function(BuildContext context)? scanBarcode;
  final VoidCallback? onReportSubmitted;

  const CreateReportScreen({
    super.key,
    required this.jobsSignals,
    required this.reportSignals,
    this.onReportSubmitted,
    this.pickImage,
    this.scanBarcode,
  });

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hardwareSectionKey = GlobalKey();
  final _signOffSectionKey = GlobalKey();
  final _signatureController = SignatureController();
  late final TextEditingController _serialController;
  late final TextEditingController _remarksController;
  late final TextEditingController _dbmController;
/*
  List<RouterDto> _availableRouters = CatalogService.fallbackRouters;
  List<NapDto> _availableNaps = CatalogService.fallbackNaps;
  List<PortDto> _availablePorts = CatalogService.fallbackPorts;
*/
  /*
  // Gene - Oct 12, 2026: Added _availableLcps for LCP-first hierarchical workflow.
  List<RouterDto> _availableRouters = CatalogService.fallbackRouters;
  List<NapDto> _availableNaps = CatalogService.fallbackNaps;
  List<PortDto> _availablePorts = CatalogService.fallbackPorts;
  List<LcpOptionDto> _availableLcps = CatalogService.fallbackLcps;
  */
  // Gene - Oct 13, 2026: Added _availablePlans to allow updating or upgrading plan on-site from /Plans API.
  List<RouterDto> _availableRouters = CatalogService.fallbackRouters;
  List<NapDto> _availableNaps = CatalogService.fallbackNaps;
  List<PortDto> _availablePorts = CatalogService.fallbackPorts;
  List<LcpOptionDto> _availableLcps = CatalogService.fallbackLcps;
  List<PlanDto> _availablePlans = CatalogService.fallbackPlans;

  /// Whether the NAP port tiles are open. Closed by default: the header
  /// already names the port the job arrived with, and sixteen tiles pushed
  /// the photo step below the fold. Picking a tile closes it again.
  bool _portsExpanded = false;

  /// Whether the remarks box is open. Closed by default with the text (or
  /// "No remarks") read back, opened with one visible button, the same way
  /// the port tiles work.
  bool _remarksExpanded = false;

  // Gene - Oct 13, 2026: State variables for dynamic materials selection and addition.
  String? _selectedMaterialToAdd;
  final TextEditingController _materialAddQtyController =
      TextEditingController(text: '1');

  // Gene - Oct 13, 2026: Signature pad lock state to prevent accidental scratch lines while scrolling.
  bool _isSignaturePadActive = false;

  @override
  void initState() {
    super.initState();
    final rep = widget.reportSignals;
    _serialController = TextEditingController(text: rep.routerSerial.value);
    _remarksController = TextEditingController(text: rep.remarks.value);
    _dbmController =
        TextEditingController(text: rep.opticalPower.value.toStringAsFixed(1));

    _loadCatalog();

    // Auto-select first available job order if none selected
    if (rep.selectedJobOrder.value == null &&
        widget.jobsSignals.allJobs.value.isNotEmpty) {
      rep.setJobOrder(widget.jobsSignals.allJobs.value.first);
      _serialController.text = rep.routerSerial.value;
      _remarksController.text = rep.remarks.value;
      _dbmController.text = rep.opticalPower.value.toStringAsFixed(1);
    }
  }

/*
  Future<void> _loadCatalog() async {
    final routersFuture = CatalogService.instance.getRouters();
    final napsFuture = CatalogService.instance.getNaps();
    final portsFuture = CatalogService.instance.getPorts();
    final results = await Future.wait([routersFuture, napsFuture, portsFuture]);
    if (!mounted) return;
    setState(() {
      _availableRouters = results[0] as List<RouterDto>;
      _availableNaps = results[1] as List<NapDto>;
      _availablePorts = results[2] as List<PortDto>;
    });
  }
*/
  /*
  // Gene - Oct 12, 2026: Also load available LCP cabinets in catalog fetch.
  Future<void> _loadCatalog() async {
    final routersFuture = CatalogService.instance.getRouters();
    final napsFuture = CatalogService.instance.getNaps();
    final portsFuture = CatalogService.instance.getPorts();
    final lcpsFuture = CatalogService.instance.getLcps();
    final results = await Future.wait([routersFuture, napsFuture, portsFuture, lcpsFuture]);
    if (!mounted) return;
    setState(() {
      _availableRouters = results[0] as List<RouterDto>;
      _availableNaps = results[1] as List<NapDto>;
      _availablePorts = results[2] as List<PortDto>;
      _availableLcps = results[3] as List<LcpOptionDto>;
    });
  }
  */
  // Gene - Oct 13, 2026: Fetch available plans from /Plans API table to populate on-site plan dropdown.
  Future<void> _loadCatalog() async {
    final routersFuture = CatalogService.instance.getRouters();
    final napsFuture = CatalogService.instance.getNaps();
    final portsFuture = CatalogService.instance.getPorts();
    final lcpsFuture = CatalogService.instance.getLcps();
    final plansFuture = CatalogService.instance.getPlans();
    final results = await Future.wait([routersFuture, napsFuture, portsFuture, lcpsFuture, plansFuture]);
    if (!mounted) return;
    setState(() {
      _availableRouters = results[0] as List<RouterDto>;
      _availableNaps = results[1] as List<NapDto>;
      _availablePorts = results[2] as List<PortDto>;
      _availableLcps = results[3] as List<LcpOptionDto>;
      _availablePlans = results[4] as List<PlanDto>;
    });
  }

  Timer? _signatureDebounce;

  /*
  @override
  void dispose() {
    _signatureDebounce?.cancel();
    _signatureController.dispose();
    _serialController.dispose();
    _remarksController.dispose();
    _dbmController.dispose();
    super.dispose();
  }
  */
  // Gene - Oct 13, 2026: Dispose _materialAddQtyController when CreateReportScreen is destroyed.
  @override
  void dispose() {
    _signatureDebounce?.cancel();
    _signatureController.dispose();
    _serialController.dispose();
    _remarksController.dispose();
    _dbmController.dispose();
    _materialAddQtyController.dispose();
    super.dispose();
  }

  Future<String?> _pick(ImageSource source) =>
      (widget.pickImage ?? ImageCaptureService.instance.pickAsDataUrl)(source);

  Future<void> _handleScanRouterSerial() async {
    final scanFn = widget.scanBarcode ?? SerialScannerSheet.show;
    final scanned = await scanFn(context);
    if (!mounted || scanned == null) return;
    final clean = scanned.trim();
    if (clean.isNotEmpty) {
      setState(() {
        _serialController.text = clean;
      });
      widget.reportSignals.routerSerial.value = clean;
    }
  }

  /*
  /// Debounced export after a stroke so fast consecutive strokes don't
  /// repeatedly encode PNGs on the UI thread, while ensuring signature is ready.
  void _onStrokeEnd() {
    _signatureDebounce?.cancel();
    _signatureDebounce = Timer(const Duration(milliseconds: 300), () {
      _captureSignature();
    });
  }

  Future<void> _captureSignature() async {
    final dataUrl = await _signatureController.toDataUrl();
    if (!mounted) return;
    widget.reportSignals.setSignature(dataUrl);
  }
  */
  // Gene - Oct 13, 2026: Debounced auto-save deprecated in favor of explicit Save & Lock button to prevent UI re-renders during active stroke drawing.

  /*
  // Gene - Oct 13, 2026: Opens dedicated modal dialog for subscriber signature to isolate signing from list scrolling.
  Future<void> _openSignatureDialog(ReportSignals rep) async {
    final dialogController = SignatureController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.draw_rounded, size: 24, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Subscriber Signature',
                    style: dialogContext.text.titleMedium),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Please sign in the space below:',
                  style: dialogContext.text.bodySmall,
                ),
                const SizedBox(height: 12),
                SignaturePad(
                  controller: dialogController,
                  height: 200,
                  enabled: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => dialogController.clear(),
              icon: const Icon(Icons.backspace_outlined, size: 20),
              label: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (dialogController.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please draw signature before saving'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final dataUrl = await dialogController.toDataUrl();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(dataUrl);
                }
              },
              icon: const Icon(Icons.check_rounded, size: 20),
              label: const Text('Done'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      rep.setSignature(result);
      _signatureController.clear();
      setState(() => _isSignaturePadActive = false);
    }
  }
  */
  // Gene - Oct 13, 2026: Removed signature dialog in favor of inline locked signature pad with Done/Save and Unlock to sign.
  Future<void> _saveAndLockSignature(ReportSignals rep) async {
    _signatureDebounce?.cancel();
    if (!_signatureController.isEmpty) {
      final dataUrl = await _signatureController.toDataUrl();
      if (dataUrl != null && mounted) {
        rep.setSignature(dataUrl);
      }
      _signatureController.clear();
    }
    if (mounted) {
      setState(() => _isSignaturePadActive = false);
    }
  }

  Future<void> _handleSubmit() async {
    final rep = widget.reportSignals;

    // Check 1: Modem / Router Serial Number
    if (_serialController.text.trim().isEmpty) {
      if (_hardwareSectionKey.currentContext != null) {
        Scrollable.ensureVisible(
          _hardwareSectionKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      _formKey.currentState?.validate();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Modem / Router Serial Number is required.'),
              ),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check 2: Form validation
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Please correct the highlighted form errors.'),
              ),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check 3: Customer Signature
    if (_signatureController.isEmpty && !rep.hasSignature.value) {
      if (_signOffSectionKey.currentContext != null) {
        Scrollable.ensureVisible(
          _signOffSectionKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Customer signature is required before saving report.'),
              ),
            ],
          ),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    _signatureDebounce?.cancel();

    if (!_signatureController.isEmpty) {
      rep.setSignature(await _signatureController.toDataUrl());
      if (!mounted) return;
    }
    rep.routerSerial.value = _serialController.text.trim();
    rep.remarks.value = _remarksController.text.trim();

    final success = await rep.submitReport(
      widget.jobsSignals.repository,
      technicianEmail: widget.jobsSignals.technicianEmail.value,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rep.submissionMessage.value ??
                      'Report submitted successfully!',
                  style: context.text.bodySmall!.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      widget.onReportSubmitted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rep = widget.reportSignals;

    return Scaffold(
      appBar: AppBar(title: const Text('Completion report')),
      bottomNavigationBar: _buildSaveBar(rep),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              /*
              // 1. Target Job Order Selector
              _buildJobOrderSummary(rep),
              const SizedBox(height: 16),

              // 2. Optical Power Reading Gauge & Input
              _buildOpticalPowerSection(rep),
              const SizedBox(height: 16),

              // 3. Hardware & Port Details
              KeyedSubtree(
                key: _hardwareSectionKey,
                child: _buildHardwareSection(rep),
              ),
              const SizedBox(height: 16),

              // 4. Materials Consumed On-Site (BOM)
              _buildMaterialsSection(rep),
              const SizedBox(height: 16),

              // 5. Photo Proof Attachments
              _buildPhotoProofSection(rep),
              const SizedBox(height: 16),

              // 5. On-site Remarks
              _buildRemarksSection(),
              const SizedBox(height: 16),

              // 6. Customer Electronic Sign-Off
              KeyedSubtree(
                key: _signOffSectionKey,
                child: _buildCustomerSignOffSection(rep),
              ),
              const SizedBox(height: 24),
              */
              // Gene - Oct 13, 2026: Reordered sections into consistent AppSheet field flow:
              // Context Header -> 1. Network Plant & Hardware -> 2. Optical Reading -> 3. Materials (BOM) -> 4. Photo Proofs -> 5. Customer Sign-Off -> 6. Technician Remarks & Status.
              _buildJobOrderSummary(rep),
              const SizedBox(height: 16),

              // Step 1: Network Plant & Hardware Details
              KeyedSubtree(
                key: _hardwareSectionKey,
                child: _buildHardwareSection(rep),
              ),
              const SizedBox(height: 16),

              /*
              // Step 2: Optical Power Reading Gauge & Input
              _buildOpticalPowerSection(rep),
              const SizedBox(height: 16),
              */
              // Gene - Oct 13, 2026: Removed optical reading from report screen as requested. Remaining sections follow physical flow.

              // Step 2: Materials Consumed On-Site
              _buildMaterialsSection(rep),
              const SizedBox(height: 16),

              // Step 3: Photo Proof Attachments
              _buildPhotoProofSection(rep),
              const SizedBox(height: 16),

              // Step 4: Customer Electronic Sign-Off
              KeyedSubtree(
                key: _signOffSectionKey,
                child: _buildCustomerSignOffSection(rep),
              ),
              const SizedBox(height: 16),

              // Step 5: Technician Remarks & Status
              _buildRemarksSection(),
              const SizedBox(height: 24),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// The screen's one red verb. The line above it names what is still
  /// missing instead of greying the button out silently; saving still runs
  /// the validation that scrolls to the first empty field.
  Widget _buildSaveBar(ReportSignals rep) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _serialController,
      builder: (context, serial, _) => ListenableBuilder(
        listenable: _signatureController,
        builder: (context, _) => SignalBuilder(
          builder: (context) {
            final submitting = rep.isSubmitting.value;
            final photos = rep.attachedPhotoCount.value;
            final total = JobPhoto.values.length;
            final missing = <String>[
              if (serial.text.trim().isEmpty) 'serial number',
              if (photos < total) '${total - photos} of $total photos',
              if (!rep.hasSignature.value && _signatureController.isEmpty)
                'signature',
            ];
            return StickyActionBar(
              label: submitting ? 'Saving…' : 'Save report',
              icon: Icons.check_circle_outline_rounded,
              why: missing.isEmpty
                  ? 'All steps done · saved on the phone first, sent when online'
                  : 'Missing: ${missing.join(' · ')}',
              onPressed: submitting ? null : _handleSubmit,
            );
          },
        ),
      ),
    );
  }

  /// A report always belongs to the job order the technician opened, so the
  /// job is shown read-only rather than as a picker. Letting it be changed
  /// here allowed a report to be filed against the wrong job.
  /*
  Widget _buildJobOrderSummary(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SignalBuilder(
          builder: (context) {
            final job = rep.selectedJobOrder.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 18, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Job Order',
                        style: context.text.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (job == null)
                  Text(
                    'No job order is linked to this report.',
                    style: context.text.bodySmall,
                  )
                else ...[
                  Text(
                    job.ticketNumber,
                    style: context.text.titleSmall!.copyWith(
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: AppTheme.brandInkOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.customerName,
                    style: context.text.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    job.address,
                    style: context.text.bodySmall,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
  */
/*
  // Gene - Oct 13, 2026: Enhanced Job Order & Subscriber summary card to display ticket, customer, plan, contact, and barangay/address matching AppSheet header hierarchy.
  Widget _buildJobOrderSummary(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SignalBuilder(
          builder: (context) {
            final job = rep.selectedJobOrder.value;
            if (job == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 18, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Job Order & Subscriber',
                          style: context.text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No job order is linked to this report.',
                    style: context.text.bodySmall,
                  ),
                ],
              );
            }

            final fullAddress = [
              job.address.trim(),
              if (job.barangay != null && job.barangay!.trim().isNotEmpty)
                'Brgy. ${job.barangay!.trim()}',
              if (job.city != null && job.city!.trim().isNotEmpty)
                job.city!.trim(),
            ].where((s) => s.isNotEmpty).join(', ');

            final phone = [
              if (job.contactNumber != null &&
                  job.contactNumber!.trim().isNotEmpty)
                job.contactNumber!.trim(),
              if (job.secondContactNumber != null &&
                  job.secondContactNumber!.trim().isNotEmpty)
                job.secondContactNumber!.trim(),
            ].join(' · ');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Job Order & Subscriber',
                        style: context.text.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.fillOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        job.ticketNumber,
                        style: context.text.labelSmall!.copyWith(
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandInkOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  job.customerName,
                  style: context.text.titleSmall!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (job.planName != null && job.planName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      /*
                      Icon(Icons.wifi_rounded,
                          size: 16, color: AppTheme.secondaryInkOf(context)), // map furniture
                      */
                      // Gene - Oct 13, 2026: Set icon size to 20 to meet outdoor readability standard.
                      Icon(Icons.wifi_rounded,
                          size: 20, color: AppTheme.secondaryInkOf(context)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${job.planName!} · Fiber to the Home',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      /*
                      Icon(Icons.call_outlined,
                          size: 16, color: AppTheme.secondaryInkOf(context)), // map furniture
                      */
                      // Gene - Oct 13, 2026: Set icon size to 20 to meet outdoor readability standard.
                      Icon(Icons.call_outlined,
                          size: 20, color: AppTheme.secondaryInkOf(context)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          phone,
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (fullAddress.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child:
                            /*
                            Icon(Icons.location_on_outlined,
                                size: 16, color: AppTheme.secondaryInkOf(context)), // map furniture
                            */
                            // Gene - Oct 13, 2026: Set icon size to 20 to meet outdoor readability standard.
                            Icon(Icons.location_on_outlined,
                                size: 20, color: AppTheme.secondaryInkOf(context)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fullAddress,
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
*/
  // Gene - Oct 13, 2026: Displayed subscriber PPPoE / RADIUS username badge with 1-tap clipboard copy at the top of the report for dedicated Wi-Fi records.
  Widget _buildJobOrderSummary(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SignalBuilder(
          builder: (context) {
            final job = rep.selectedJobOrder.value;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            if (job == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 20, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Job Order & Subscriber',
                          style: context.text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No job order is linked to this report.',
                    style: context.text.bodySmall,
                  ),
                ],
              );
            }

            final fullAddress = [
              job.address.trim(),
              if (job.barangay != null && job.barangay!.trim().isNotEmpty)
                'Brgy. ${job.barangay!.trim()}',
              if (job.city != null && job.city!.trim().isNotEmpty)
                job.city!.trim(),
            ].where((s) => s.isNotEmpty).join(', ');

            final phone = [
              if (job.contactNumber != null &&
                  job.contactNumber!.trim().isNotEmpty)
                job.contactNumber!.trim(),
              if (job.secondContactNumber != null &&
                  job.secondContactNumber!.trim().isNotEmpty)
                job.secondContactNumber!.trim(),
            ].join(' · ');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Job Order & Subscriber',
                        style: context.text.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.fillOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        job.ticketNumber,
                        style: context.text.labelSmall!.copyWith(
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brandInkOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  job.customerName,
                  style: context.text.titleSmall!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                /*
                if (job.planName != null && job.planName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.wifi_rounded,
                          size: 20, color: AppTheme.secondaryInkOf(context)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${job.planName!} · Fiber to the Home',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                */
                // Gene - Oct 13, 2026: Subscription plan dropdown selector allowing technician to upgrade or change plan on-site.
                SignalBuilder(
                  builder: (context) {
                    final activePlanId = rep.planId.value ?? job.planId;
                    final activePlanName = rep.planName.value ?? job.planName;

                    final plans = List<PlanDto>.from(_availablePlans);
                    int? matchedId;

                    if (activePlanId != null &&
                        plans.any((p) => p.id == activePlanId)) {
                      matchedId = activePlanId;
                    } else if (activePlanName != null &&
                        activePlanName.trim().isNotEmpty) {
                      final found = plans.where((p) =>
                          p.name.trim().toLowerCase() ==
                          activePlanName.trim().toLowerCase());
                      if (found.isNotEmpty) {
                        matchedId = found.first.id;
                      } else {
                        final fallbackId = activePlanId ?? -999;
                        plans.insert(
                          0,
                          PlanDto(
                            id: fallbackId,
                            name: activePlanName.trim(),
                            description: 'Assigned Subscription Plan',
                            amount: 0,
                          ),
                        );
                        matchedId = fallbackId;
                      }
                    } else if (plans.isNotEmpty) {
                      matchedId = plans.first.id;
                    }

                    final isUpgraded = (activePlanName != null &&
                            job.planName != null &&
                            activePlanName.trim() != job.planName!.trim()) ||
                        (activePlanId != null &&
                            job.planId != null &&
                            activePlanId != job.planId);

                    return Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 2),
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('plan_dropdown_field'),
                        initialValue: matchedId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Subscription Plan',
                          prefixIcon: const Icon(Icons.wifi_rounded, size: 20),
                          helperText: isUpgraded
                              ? 'Plan updated on-site from: ${job.planName ?? "Initial Plan"}'
                              : 'Select to update or upgrade plan on-site',
                          helperStyle: isUpgraded
                              ? context.text.labelSmall!.copyWith(
                                  color: AppTheme.successInkOf(context),
                                  fontWeight: FontWeight.w600,
                                )
                              : null,
                        ),
                        items: plans.map((plan) {
                          final priceSuffix = plan.amount > 0
                              ? ' · ${plan.formattedPrice}'
                              : '';
                          return DropdownMenuItem<int>(
                            value: plan.id,
                            child: Text(
                              '${plan.name}$priceSuffix',
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMedium,
                            ),
                          );
                        }).toList(),
                        onChanged: (newId) {
                          if (newId != null) {
                            final chosen =
                                plans.firstWhere((p) => p.id == newId);
                            rep.setPlan(chosen.id, chosen.name);
                          }
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                // RADIUS / Wi-Fi dedicated account identity
                Container(
                  key: const ValueKey('radius_username_banner'),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          isDark ? AppTheme.borderDark : AppTheme.borderLight,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.wifi_lock_rounded,
                        size: 20,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RADIUS / Wi-Fi Username',
                              style: context.text.labelSmall!.copyWith(
                                color: AppTheme.secondaryInkOf(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              job.radiusUsername,
                              style: context.text.bodyMedium!.copyWith(
                                fontFamily: 'JetBrains Mono',
                                fontWeight: FontWeight.w700,
                                color: AppTheme.brandInkOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('copy_radius_username_button'),
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'Copy username',
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 36),
                        /*
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: job.radiusUsername));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('RADIUS username copied to clipboard'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        */
                        // Gene - Oct 13, 2026: Disable copy button if username is empty.
                        onPressed: job.radiusUsername.trim().isEmpty
                            ? null
                            : () {
                                Clipboard.setData(
                                    ClipboardData(text: job.radiusUsername));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'RADIUS username copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                      ),
                    ],
                  ),
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.call_outlined,
                          size: 20, color: AppTheme.secondaryInkOf(context)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          phone,
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (fullAddress.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.location_on_outlined,
                            size: 20, color: AppTheme.secondaryInkOf(context)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fullAddress,
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // Gene - Oct 13, 2026: Commented out unused _buildOpticalPowerSection since Optical reading was removed from the report as requested.
  /*
  Widget _buildOpticalPowerSection(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: StepHeader(
                      number: 2, title: 'Optical reading', done: true),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Live Quality Gauge
            SignalBuilder(
              builder: (context) {
                return OpticalPowerGauge(
                    opticalPowerDbm: rep.opticalPower.value);
              },
            ),

            const SizedBox(height: 16),

            // Slider & Manual Text Input Row
            Row(
              children: [
                Expanded(
                  child: SignalBuilder(
                    builder: (context) {
                      final dbm = rep.opticalPower.value;
                      return Slider(
                        value: dbm,
                        min: -35.0,
                        max: -8.0,
                        divisions: 54,
                        activeColor: AppTheme.primary,
                        onChanged: (val) {
                          rep.opticalPower.value =
                              double.parse(val.toStringAsFixed(1));
                          _dbmController.text = val.toStringAsFixed(1);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _dbmController,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      suffixText: 'dBm',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed >= -40 && parsed <= 0) {
                        rep.opticalPower.value = parsed;
                      }
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
  */

/*
  Widget _buildHardwareSection(ReportSignals rep) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _serialController,
                    builder: (context, serial, _) => StepHeader(
                      number: 2,
                      title: 'Hardware & port',
                      done: serial.text.trim().isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Router SN
            TextFormField(
              controller: _serialController,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
              onChanged: (val) => widget.reportSignals.routerSerial.value = val,
              decoration: InputDecoration(
                labelText: 'Modem / ONT Serial Number (SN)',
                prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                suffixIcon: IconButton(
                  key: const ValueKey('scan_router_serial_button'),
                  tooltip: 'Scan Serial Barcode',
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  onPressed: _handleScanRouterSerial,
                ),
                hintText: 'e.g. HWTC12345678 or ZTE8839001',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter modem/router serial number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ONT model: the same searchable sheet as the NAP box below,
            // because the approved catalog keeps growing.
            SignalBuilder(
              builder: (context) {
                final model = rep.routerModel.value;
                return PickerField(
                  key: const ValueKey('router_model_field'),
                  label: 'Approved ONT Model',
                  value: model,
                  placeholder: 'Select or filter model...',
                  icon: Icons.router_rounded,
                  onTap: () async {
                    final picked = await RouterModelPicker.show(
                      context,
                      routers: _availableRouters,
                      selected: model,
                    );
                    if (picked != null) rep.routerModel.value = picked;
                  },
                );
              },
            ),
            const SizedBox(height: 12),

            // NAP Box: searchable sheet, one tap to pick.
            SignalBuilder(
              builder: (context) {
                final selected = rep.nap.value;
                return PickerField(
                  key: const ValueKey('nap_dropdown_field'),
                  label: 'NAP Box',
                  value: selected,
                  placeholder: 'Select or filter NAP (e.g. NAP 001)...',
                  icon: Icons.hub_rounded,
                  onTap: () => _showNapFilterDialog(context, rep, isDark),
                );
              },
            ),
            const SizedBox(height: 14),
            SignalBuilder(
              builder: (context) {
                final port = rep.napPort.value;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NAP PORT',
                            style: context.text.labelMedium!.copyWith(
                                color: AppTheme.secondaryInkOf(context)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            port.isEmpty ? 'Not selected' : port,
                            style: context.text.bodyLarge!.copyWith(
                              fontWeight: FontWeight.w500,
                              color: port.isEmpty
                                   ? AppTheme.secondaryInkOf(context)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      expanded: _portsExpanded,
                      label: _portsExpanded
                          ? 'Close port tiles'
                          : 'Change NAP port',
                      child: TextButton.icon(
                        key: const ValueKey('nap_port_toggle'),
                        onPressed: () =>
                            setState(() => _portsExpanded = !_portsExpanded),
                        icon: Icon(
                          _portsExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                        ),
                        label: Text(_portsExpanded ? 'Done' : 'Change'),
                      ),
                    ),
                  ],
                );
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _portsExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SignalBuilder(
                        builder: (context) {
                          final names =
                              _availablePorts.map((p) => p.name).toList();
                          return PortTileGrid(
                            ports: names,
                            selected: rep.napPort.value,
                            onSelected: (port) {
                              rep.napPort.value = port;
                              setState(() => _portsExpanded = false);
                            },
                          );
                        },
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNapFilterDialog(
      BuildContext context, ReportSignals rep, bool isDark) async {
    final picked = await SearchablePickerSheet.show<NapDto>(
      context,
      title: 'Select NAP Box',
      icon: Icons.hub_rounded,
      searchHint: 'Filter NAP list (e.g. 001, test)...',
      items: _availableNaps,
      titleOf: (n) => n.name,
      subtitleOf: (n) => n.description,
      matches: (n, q) =>
          n.name.toLowerCase().contains(q) ||
          n.description.toLowerCase().contains(q),
      isSelected: (n) => n.name == rep.nap.value,
      emptyMessage: (q) => 'No NAP matching "$q"',
    );
    if (picked != null) rep.nap.value = picked.name;
  }
*/
  // Gene - Oct 12, 2026: Calculate ports already in use on this NAP by other subscriber job orders so they are disabled in PortTileGrid.
  Set<String> _getUsedPorts(ReportSignals rep) {
    final used = <String>{};
    final currentJobId = rep.selectedJobOrder.value?.id;
    final currentNap = rep.nap.value;
    if (currentNap == null || currentNap.trim().isEmpty) return used;

    for (final job in widget.jobsSignals.allJobs.value) {
      if (job.id != currentJobId &&
          job.portId != null &&
          job.portId!.trim().isNotEmpty) {
        final jobNap = job.nap?.trim();
        if (jobNap != null &&
            jobNap.toLowerCase() == currentNap.trim().toLowerCase()) {
          used.add(job.portId!.trim());
        }
      }
    }
    return used;
  }

  // Gene - Oct 12, 2026: Show LCP Cabinet selection sheet with search and filter.
  Future<void> _showLcpFilterDialog(
      BuildContext context, ReportSignals rep, bool isDark) async {
    final picked = await SearchablePickerSheet.show<LcpOptionDto>(
      context,
      title: 'Select LCP Cabinet',
      icon: Icons.account_tree_rounded,
      searchHint: 'Filter LCP (e.g. 01, Batingan)...',
      items: _availableLcps,
      titleOf: (l) => l.name,
      subtitleOf: (l) => l.description,
      matches: (l, q) =>
          l.name.toLowerCase().contains(q) ||
          l.description.toLowerCase().contains(q),
      isSelected: (l) => l.name == rep.lcp.value,
      emptyMessage: (q) => 'No LCP matching "$q"',
    );
    if (picked != null) {
      final prev = rep.lcp.value;
      rep.lcp.value = picked.name;
      // If LCP was changed, reset NAP so tech chooses from this LCP
      if (prev != null && prev != picked.name) {
        rep.nap.value = null;
      }
    }
  }

  // Gene - Oct 12, 2026: Reordered hardware answering flow matching AppSheet:
  // 1. LCP Cabinet (Picker)
  // 2. NAP Box (Picker: requires LCP first; 8 or 16 NAPs)
  // 3. NAP Port (PortTileGrid: used ports disabled)
  // 4. Modem / ONT Serial Number (Text input + Barcode scanner)
  // 5. Approved ONT Model (Picker)
  Widget _buildHardwareSection(ReportSignals rep) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /*
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _serialController,
                    builder: (context, serial, _) => StepHeader(
                      number: 2,
                      title: 'Hardware & port',
                      done: serial.text.trim().isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
            */
            // Gene - Oct 13, 2026: Set StepHeader number to 1 for Hardware & port matching AppSheet workflow.
            Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _serialController,
                    builder: (context, serial, _) => StepHeader(
                      number: 1,
                      title: 'Hardware & port',
                      done: serial.text.trim().isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 1. LCP Cabinet: Searchable sheet, required before NAP
            SignalBuilder(
              builder: (context) {
                final selectedLcp = rep.lcp.value;
                return PickerField(
                  key: const ValueKey('lcp_dropdown_field'),
                  label: 'LCP Cabinet',
                  value: selectedLcp,
                  placeholder: 'Select or filter LCP (e.g. LCP 01)...',
                  icon: Icons.account_tree_rounded,
                  onTap: () => _showLcpFilterDialog(context, rep, isDark),
                );
              },
            ),
            const SizedBox(height: 12),

            // 2. NAP Box: Searchable sheet, requires LCP selection first (8 or 16 NAPs)
            SignalBuilder(
              builder: (context) {
                final selectedNap = rep.nap.value;
                final lcpSelected =
                    rep.lcp.value != null && rep.lcp.value!.trim().isNotEmpty;
                return PickerField(
                  key: const ValueKey('nap_dropdown_field'),
                  label: 'NAP Box',
                  value: selectedNap,
                  placeholder: lcpSelected
                      ? 'Select or filter NAP (e.g. NAP 001)...'
                      : 'Select LCP Cabinet first...',
                  icon: Icons.hub_rounded,
                  onTap: () => _showNapFilterDialog(context, rep, isDark),
                );
              },
            ),
            const SizedBox(height: 14),

            // 3. NAP Port: 8 or 16 port grid with used ports disabled
            SignalBuilder(
              builder: (context) {
                final port = rep.napPort.value;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NAP PORT',
                            style: context.text.labelMedium!.copyWith(
                                color: AppTheme.secondaryInkOf(context)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            port.isEmpty ? 'Not selected' : port,
                            style: context.text.bodyLarge!.copyWith(
                              fontWeight: FontWeight.w500,
                              color: port.isEmpty
                                  ? AppTheme.secondaryInkOf(context)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      expanded: _portsExpanded,
                      label: _portsExpanded
                          ? 'Close port tiles'
                          : 'Change NAP port',
                      child: TextButton.icon(
                        key: const ValueKey('nap_port_toggle'),
                        onPressed: () =>
                            setState(() => _portsExpanded = !_portsExpanded),
                        icon: Icon(
                          _portsExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                        ),
                        label: Text(_portsExpanded ? 'Done' : 'Change'),
                      ),
                    ),
                  ],
                );
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _portsExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SignalBuilder(
                        builder: (context) {
                          final names =
                              _availablePorts.map((p) => p.name).toList();
                          final usedPorts = _getUsedPorts(rep);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PortTileGrid(
                                ports: names,
                                selected: rep.napPort.value,
                                unavailable: usedPorts,
                                onSelected: (port) {
                                  rep.napPort.value = port;
                                  setState(() => _portsExpanded = false);
                                },
                              ),
                              if (usedPorts.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      // Gene - Oct 12, 2026: Updated icon to 20px and styled label using theme tokens without fontSize literal.
                                      Icon(Icons.info_outline_rounded,
                                          size: 20,
                                          color: AppTheme.secondaryInkOf(
                                              context)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Struck-through ports (${usedPorts.length}) are in use by other subscribers',
                                          style:
                                              context.text.bodySmall!.copyWith(
                                            color: AppTheme.secondaryInkOf(
                                                context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 14),

            // Gene - Oct 13, 2026: Added VLAN dropdown selection with default value 1000 as requested.
            SignalBuilder(
              builder: (context) {
                final currentVlan = rep.vlan.value;
                const vlanOptions = ['1000', '100', '200', '300', '400', '500'];
                final items = vlanOptions.contains(currentVlan)
                    ? vlanOptions
                    : [currentVlan, ...vlanOptions];

                /*
                return DropdownButtonFormField<String>(
                  key: const ValueKey('vlan_dropdown_field'),
                  value: currentVlan,
                  decoration: const InputDecoration(
                    labelText: 'VLAN',
                    prefixIcon: Icon(Icons.alt_route_rounded, size: 20),
                  ),
                  items: items
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v == '1000' ? '$v (Default)' : v),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      rep.vlan.value = val;
                    }
                  },
                );
                */
                /*
                // Gene - Oct 13, 2026: Set isExpanded: true on VLAN dropdown to prevent horizontal overflow on narrow phone screens.
                return DropdownButtonFormField<String>(
                  key: const ValueKey('vlan_dropdown_field'),
                  value: currentVlan,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'VLAN',
                    prefixIcon: Icon(Icons.alt_route_rounded, size: 20),
                  ),
                  items: items
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v == '1000' ? '$v (Default)' : v),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      rep.vlan.value = val;
                    }
                  },
                );
                */
                // Gene - Oct 13, 2026: Set isExpanded: true and initialValue on VLAN dropdown to prevent horizontal overflow and avoid deprecated value parameter.
                return DropdownButtonFormField<String>(
                  key: const ValueKey('vlan_dropdown_field'),
                  initialValue: currentVlan,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'VLAN',
                    prefixIcon: Icon(Icons.alt_route_rounded, size: 20),
                  ),
                  items: items
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v == '1000' ? '$v (Default)' : v),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      rep.vlan.value = val;
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 12),

            // 5. Modem / ONT Serial Number: text box with barcode scanner button
            TextFormField(
              controller: _serialController,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
              onChanged: (val) => widget.reportSignals.routerSerial.value = val,
              decoration: InputDecoration(
                labelText: 'Modem / ONT Serial Number (SN)',
                prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                suffixIcon: IconButton(
                  key: const ValueKey('scan_router_serial_button'),
                  tooltip: 'Scan Serial Barcode',
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  onPressed: _handleScanRouterSerial,
                ),
                hintText: 'e.g. HWTC12345678 or ZTE8839001',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter modem/router serial number';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // 5. Approved ONT Model: searchable picker sheet
            SignalBuilder(
              builder: (context) {
                final model = rep.routerModel.value;
                return PickerField(
                  key: const ValueKey('router_model_field'),
                  label: 'Approved ONT Model',
                  value: model,
                  placeholder: 'Select or filter model...',
                  icon: Icons.router_rounded,
                  onTap: () async {
                    final picked = await RouterModelPicker.show(
                      context,
                      routers: _availableRouters,
                      selected: model,
                    );
                    if (picked != null) rep.routerModel.value = picked;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Gene - Oct 12, 2026: Enforce LCP selection before allowing NAP Box picker sheet.
  Future<void> _showNapFilterDialog(
      BuildContext context, ReportSignals rep, bool isDark) async {
    if (rep.lcp.value == null || rep.lcp.value!.trim().isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                    'Please select an LCP Cabinet first before choosing a NAP Box.'),
              ),
            ],
          ),
          backgroundColor: AppTheme.brandInkOf(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picked = await SearchablePickerSheet.show<NapDto>(
      context,
      title: 'Select NAP Box',
      icon: Icons.hub_rounded,
      searchHint: 'Filter NAP list (e.g. 001, test)...',
      items: _availableNaps,
      titleOf: (n) => n.name,
      subtitleOf: (n) => n.description,
      matches: (n, q) =>
          n.name.toLowerCase().contains(q) ||
          n.description.toLowerCase().contains(q),
      isSelected: (n) => n.name == rep.nap.value,
      emptyMessage: (q) => 'No NAP matching "$q"',
    );
    if (picked != null) rep.nap.value = picked.name;
  }

  static IconData _iconFor(JobPhoto photo) => switch (photo) {
        JobPhoto.boxReading => Icons.speed_rounded,
        JobPhoto.routerReading => Icons.router_rounded,
        JobPhoto.setup => Icons.settings_input_antenna_rounded,
        JobPhoto.speedtest => Icons.network_check_rounded,
        JobPhoto.portLabel => Icons.label_rounded,
        JobPhoto.signedContract => Icons.description_rounded,
        JobPhoto.houseFront => Icons.house_rounded,
      };

  /// Step 4, collapsible. Closed: the remark text (or "No remarks") and an
  /// Add / Edit button. Open: the text box and a Done button.
/*
  Widget _buildRemarksSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _remarksController,
          builder: (context, value, _) {
            final text = value.text.trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: StepHeader(
                          number: 4, title: 'Remarks', hint: 'optional'),
                    ),
                    Semantics(
                      button: true,
                      expanded: _remarksExpanded,
                      label: _remarksExpanded
                          ? 'Close remarks'
                          : (text.isEmpty ? 'Add remarks' : 'Edit remarks'),
                      child: TextButton.icon(
                        key: const ValueKey('remarks_toggle'),
                        onPressed: () => setState(
                            () => _remarksExpanded = !_remarksExpanded),
                        icon: Icon(
                          _remarksExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                        ),
                        label: Text(_remarksExpanded
                            ? 'Done'
                            : (text.isEmpty ? 'Add' : 'Edit')),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _remarksExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: TextFormField(
                            controller: _remarksController,
                            maxLines: 4,
                            minLines: 3,
                            decoration: const InputDecoration(
                              hintText:
                                  'Enter fiber splice details, cable distance, speedtest results...',
                            ),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            text.isEmpty ? 'No remarks' : text,
                            key: const ValueKey('remarks_preview'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium!.copyWith(
                              color: text.isEmpty
                                  ? AppTheme.secondaryInkOf(context)
                                  : null,
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
*/
  // Gene - Oct 12, 2026: Added quick-select status remarks chips matching AppSheet options.
  Widget _buildRemarksSection() {
/*
    const quickRemarks = [
      'Office',
      'Customer Not Around',
      'Customer Requested',
      'No Available Port',
      'High Attenuation / Low Signal',
      'Bad Weather',
      'No Materials',
      'Address Not Found',
      'Completed Normal',
    ];
*/
    // Gene - Oct 12, 2026: Updated quick status remarks chips to match 13 AppSheet Status Remarks Categories.
    const quickRemarks = [
      'No pole attachment',
      'No facility',
      'Passing private property',
      'Request by sub',
      'Pole issue',
      'For add nap',
      'No response',
      'House closed',
      'Over span',
      'Wrong address',
      'Duplicate',
      'Full nap',
      'Floating',
      'Office',
      'Completed Normal',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _remarksController,
          builder: (context, value, _) {
            final text = value.text.trim();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /*
                Row(
                  children: [
                    const Expanded(
                      child: StepHeader(
                          number: 4, title: 'Remarks', hint: 'optional'),
                    ),
                */
                /*
                // Gene - Oct 13, 2026: Set StepHeader to step 6 (Technician remarks & status) following AppSheet workflow.
                Row(
                  children: [
                    const Expanded(
                      child: StepHeader(
                          number: 6,
                          title: 'Technician remarks & status',
                          hint: 'optional'),
                    ),
                */
                // Gene - Oct 13, 2026: Set StepHeader to step 5 (Technician remarks & status) now that optical reading is removed.
                Row(
                  children: [
                    const Expanded(
                      child: StepHeader(
                          number: 5,
                          title: 'Technician remarks & status',
                          hint: 'optional'),
                    ),
                    Semantics(
                      button: true,
                      expanded: _remarksExpanded,
                      label: _remarksExpanded
                          ? 'Close remarks'
                          : (text.isEmpty ? 'Add remarks' : 'Edit remarks'),
                      child: TextButton.icon(
                        key: const ValueKey('remarks_toggle'),
                        onPressed: () => setState(
                            () => _remarksExpanded = !_remarksExpanded),
                        icon: Icon(
                          _remarksExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                        ),
                        label: Text(_remarksExpanded
                            ? 'Done'
                            : (text.isEmpty ? 'Add' : 'Edit')),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _remarksExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _remarksController,
                                maxLines: 4,
                                minLines: 3,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Enter fiber splice details, cable distance, speedtest results...',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'QUICK STATUS REMARKS',
                                  style: context.text.labelSmall!.copyWith(
                                    color: AppTheme.secondaryInkOf(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final remark in quickRemarks)
                                    // Gene - Oct 12, 2026: Removed compact visual density and literal fontSize to obey field standard guidelines.
                                    ActionChip(
                                      key: ValueKey('quick_remark_$remark'),
                                      label: Text(remark,
                                          style: context.text.labelSmall),
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        final cur =
                                            _remarksController.text.trim();
                                        final updated = cur.isEmpty
                                            ? remark
                                            : (cur.contains(remark)
                                                ? cur
                                                : '$cur · $remark');
                                        _remarksController.text = updated;
                                        widget.reportSignals.remarks.value =
                                            updated;
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            text.isEmpty ? 'No remarks' : text,
                            key: const ValueKey('remarks_preview'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium!.copyWith(
                              color: text.isEmpty
                                  ? AppTheme.secondaryInkOf(context)
                                  : null,
                            ),
                          ),
                        ),
                ),
                // Gene - Oct 13, 2026: Display technician attribution and final Done completion status matching AppSheet report footer.
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    /*
                    Icon(Icons.badge_outlined,
                        size: 16, color: AppTheme.secondaryInkOf(context)), // map furniture
                    */
                    // Gene - Oct 13, 2026: Set icon size to 20 to meet outdoor readability standard.
                    Icon(Icons.badge_outlined,
                        size: 20, color: AppTheme.secondaryInkOf(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.jobsSignals.technicianEmail.value
                                    ?.trim()
                                    .isNotEmpty ==
                                true
                            ? 'Tech: ${widget.jobsSignals.technicianEmail.value!.trim()}'
                            : 'Field Technician',
                        style: context.text.bodySmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          /*
                          const Icon(Icons.check_circle_rounded,
                              size: 14, color: AppTheme.success), // map furniture
                          */
                          // Gene - Oct 13, 2026: Set icon size to 20 to meet outdoor readability standard.
                          const Icon(Icons.check_circle_rounded,
                              size: 20, color: AppTheme.success),
                          const SizedBox(width: 4),
                          Text(
                            'Status: Done',
                            style: context.text.labelSmall!.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.successInkOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /*
  Widget _buildMaterialsSection(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SignalBuilder(
          builder: (context) {
            final materials = rep.materialsUsed.value;
            final dropCable = materials['Drop Cable (m)'] ?? 0;
            final fastConnectors = materials['SC/APC Fast Connector'] ?? 0;
            final sClamps = materials['S-Clamp'] ?? 0;

            // Gene - Oct 13, 2026: Set StepHeader to step 2 for Materials Consumed On-Site now that optical reading is removed.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StepHeader(
                        number: 2,
                        title: 'Materials Consumed On-Site',
                        done: materials.values.any((qty) => qty > 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                MaterialCounterRow(
                  name: 'Drop Cable',
                  unit: 'meters',
                  count: dropCable,
                  minusKey: const ValueKey('counter_minus_drop_cable'),
                  fieldKey: const ValueKey('counter_field_drop_cable'),
                  plusKey: const ValueKey('counter_plus_drop_cable'),
                  onChanged: (v) =>
                      rep.setMaterialQuantity('Drop Cable (m)', v),
                ),
                const Divider(height: 16),
                MaterialCounterRow(
                  name: 'SC/APC Fast Connectors',
                  unit: 'pcs',
                  count: fastConnectors,
                  minusKey: const ValueKey('counter_minus_fast_connectors'),
                  fieldKey: const ValueKey('counter_field_fast_connectors'),
                  plusKey: const ValueKey('counter_plus_fast_connectors'),
                  onChanged: (v) =>
                      rep.setMaterialQuantity('SC/APC Fast Connector', v),
                ),
                const Divider(height: 16),
                MaterialCounterRow(
                  name: 'S-Clamps',
                  unit: 'pcs',
                  count: sClamps,
                  minusKey: const ValueKey('counter_minus_s_clamps'),
                  fieldKey: const ValueKey('counter_field_s_clamps'),
                  plusKey: const ValueKey('counter_plus_s_clamps'),
                  onChanged: (v) => rep.setMaterialQuantity('S-Clamp', v),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  */

  // Gene - Oct 13, 2026: Hardcoded available materials list copied from AppSheet web dropdown.
  static const List<String> kAvailableMaterials = [
    'APC-SC TO APC-SC (GREEN)',
    'APC-SC TO UPC-SC (GREEN TO BLUE)',
    'BROTHER CASSETTE TAPE',
    'BROTHER LABEL PRINTER',
    'Drop Cable (m)',
    'F-CLAMP',
    'FIBER OPTIC TROLLY',
    'FLAT CABLE CLIP',
    'HOUSE BRACKET',
    'IOO BOX',
    'MID SPAN',
    'OPTI-S',
    'OPTICAL POWER METER',
    'S-Clamp',
    'SC CONNECTOR',
    'SC/APC Fast Connector',
    'SCREW AND TOX',
    'SENKO SC CONNECTOR',
    'ZTE HG260',
  ];

  static String _unitForMaterial(String material) {
    final lower = material.toLowerCase();
    if (lower.contains('cable') || lower.contains('(m)')) {
      return 'meters';
    } else if (lower.contains('tape')) {
      return 'rolls';
    } else if (lower.contains('printer') ||
        lower.contains('meter') ||
        lower.contains('trolly')) {
      return 'units';
    } else if (lower.contains('screw') ||
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

  Future<void> _showMaterialPickerDialog(
      BuildContext context, bool isDark) async {
    final picked = await SearchablePickerSheet.show<String>(
      context,
      title: 'Select Material',
      icon: Icons.inventory_2_outlined,
      searchHint: 'Filter material list (e.g. F-Clamp, Cable)...',
      items: kAvailableMaterials,
      titleOf: (m) => m,
      subtitleOf: (m) => 'Unit: ${_unitForMaterial(m)}',
      matches: (m, q) => m.toLowerCase().contains(q),
      isSelected: (m) => m == _selectedMaterialToAdd,
      emptyMessage: (q) => 'No material matching "$q"',
    );
    if (picked != null) {
      setState(() {
        _selectedMaterialToAdd = picked;
      });
    }
  }

  void _handleAddMaterial(ReportSignals rep) {
    if (_selectedMaterialToAdd == null ||
        _selectedMaterialToAdd!.trim().isEmpty) {
      return;
    }
    final mat = _selectedMaterialToAdd!.trim();
    final qtyToAdd = int.tryParse(_materialAddQtyController.text) ?? 1;
    final validQty = qtyToAdd > 0 ? qtyToAdd : 1;
    final currentQty = rep.materialsUsed.value[mat] ?? 0;
    rep.setMaterialQuantity(mat, currentQty + validQty);
    setState(() {
      _selectedMaterialToAdd = null;
      _materialAddQtyController.text = '1';
    });
  }

  // Gene - Oct 13, 2026: Dynamic materials consumed section: dropdown selector with search, Add button with custom quantity, and dynamic list of added items with counters and remove buttons.
  Widget _buildMaterialsSection(ReportSignals rep) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SignalBuilder(
          builder: (context) {
            final materials = rep.materialsUsed.value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StepHeader(
                        number: 2,
                        title: 'Materials Consumed On-Site',
                        done: materials.values.any((qty) => qty > 0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Dynamic Material Selector: Dropdown with search
                PickerField(
                  key: const ValueKey('material_select_field'),
                  label: 'Select Material',
                  value: _selectedMaterialToAdd,
                  placeholder: 'Search or select material to add...',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => _showMaterialPickerDialog(context, isDark),
                ),
                const SizedBox(height: 10),

                // Quantity and Add Material button row
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        key: const ValueKey('material_add_qty_field'),
                        controller: _materialAddQtyController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          key: const ValueKey('add_material_button'),
                          onPressed: (_selectedMaterialToAdd == null ||
                                  _selectedMaterialToAdd!.trim().isEmpty)
                              ? null
                              : () => _handleAddMaterial(rep),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Add Material'),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Dynamic Added Materials list at the bottom
                if (materials.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.fillOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? AppTheme.borderDark
                            : AppTheme.borderLight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No materials added yet.\nSelect a material above and tap "Add Material".',
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                        ),
                      ),
                    ),
                  )
                else
                  ...materials.entries.map((entry) {
                    final slug = _materialKeySlug(entry.key);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: MaterialCounterRow(
                              name: entry.key,
                              unit: _unitForMaterial(entry.key),
                              count: entry.value,
                              minusKey: ValueKey('counter_minus_$slug'),
                              fieldKey: ValueKey('counter_field_$slug'),
                              plusKey: ValueKey('counter_plus_$slug'),
                              onChanged: (qty) =>
                                  rep.setMaterialQuantity(entry.key, qty),
                            ),
                          ),
                          IconButton(
                            key: ValueKey('remove_material_$slug'),
                            icon: const Icon(Icons.close_rounded, size: 20),
                            color: AppTheme.secondaryInkOf(context),
                            tooltip: 'Remove ${entry.key}',
                            onPressed: () =>
                                rep.setMaterialQuantity(entry.key, 0),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPhotoProofSection(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /*
            Row(
              children: [
                Expanded(
                  child: SignalBuilder(
                    builder: (context) => StepHeader(
                      number: 3,
                      title: 'Photo proofs',
                      done: rep.attachedPhotoCount.value ==
                          JobPhoto.values.length,
                    ),
                  ),
                ),
            */
            /*
            // Gene - Oct 13, 2026: Set StepHeader number to 4 for Photo proofs following Materials in AppSheet workflow.
            Row(
              children: [
                Expanded(
                  child: SignalBuilder(
                    builder: (context) => StepHeader(
                      number: 4,
                      title: 'Photo proofs',
                      done: rep.attachedPhotoCount.value ==
                          JobPhoto.values.length,
                    ),
                  ),
                ),
            */
            // Gene - Oct 13, 2026: Set StepHeader to step 3 for Photo proofs now that optical reading is removed.
            Row(
              children: [
                Expanded(
                  child: SignalBuilder(
                    builder: (context) => StepHeader(
                      number: 3,
                      title: 'Photo proofs',
                      done: rep.attachedPhotoCount.value ==
                          JobPhoto.values.length,
                    ),
                  ),
                ),
                SignalBuilder(
                  builder: (context) {
                    final job = rep.selectedJobOrder.value;
                    final count = JobPhoto.values
                        .where((p) => rep.photoFor(p)?.isNotEmpty == true)
                        .length;
                    final label = '$count / ${JobPhoto.values.length}';
                    return Text(
                      job == null ? '' : label,
                      style: context.text.bodySmall!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Photos are compressed on the phone and saved with the job order.',
              style: context.text.labelSmall,
            ),
            const SizedBox(height: 12),
            SignalBuilder(
              builder: (context) {
                // Read so the grid rebuilds when any photo changes.
                rep.photos.value;
                rep.selectedJobOrder.value;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.98,
                  ),
                  itemCount: JobPhoto.values.length,
                  itemBuilder: (context, index) {
                    final photo = JobPhoto.values[index];
                    return PhotoCaptureTile(
                      key: ValueKey(photo),
                      label: photo.label,
                      hint: photo.hint,
                      icon: _iconFor(photo),
                      value: rep.photoFor(photo),
                      pick: _pick,
                      onChanged: (v) => rep.setPhoto(photo, v),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSignOffSection(ReportSignals rep) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppTheme.textSecondaryDark : AppTheme.textMuted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: _signatureController,
                    builder: (context, _) => SignalBuilder(
                      /*
                      builder: (context) => StepHeader(
                        number: 5,
                        title: 'Customer sign-off',
                        done: rep.hasSignature.value ||
                            !_signatureController.isEmpty,
                      ),
                      */
                      // Gene - Oct 13, 2026: Set StepHeader to step 4 for Customer sign-off now that optical reading is removed.
                      builder: (context) => StepHeader(
                        number: 4,
                        title: 'Customer sign-off',
                        done: rep.hasSignature.value ||
                            !_signatureController.isEmpty,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Subscriber acknowledges proper optical installation and functional internet connectivity.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 12),
            /*
            SignalBuilder(
              builder: (context) {
                final existing = rep.signature.value;
                final existingBytes =
                    PhotoStorageService.instance.resolveBytes(existing) ??
                        DataUrl.decode(existing);
                final padHasInk = !_signatureController.isEmpty;

                // A signature already on the job is shown as-is until the
                // technician chooses to capture a new one.
                if (existingBytes != null && !padHasInk) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 140,
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
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded,
                              size: 20, color: AppTheme.success),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Signature captured',
                              style: context.text.labelMedium!.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.successInkOf(context),
                              ),
                            ),
                          ),
                          // Gene - Oct 13, 2026: Sign again resets signature and unlocks pad into active signing mode.
                          TextButton.icon(
                            onPressed: () {
                              rep.setSignature(null);
                              _signatureController.clear();
                              setState(() => _isSignaturePadActive = true);
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: const Text('Sign again'),
                          ),
                        ],
                      ),
                      // Gene - Oct 13, 2026: Display subscriber name matching AppSheet signature block footer for existing signature.
                      if (rep.selectedJobOrder.value != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Signed by: ${rep.selectedJobOrder.value!.customerName}',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );
                }

                // Gene - Oct 13, 2026: Display scroll-safe locked signature card by default to prevent accidental scratch strokes during list scroll.
                if (!_isSignaturePadActive && !padHasInk) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.borderDark
                                : AppTheme.borderLight,
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const ValueKey('unlock_signature_pad_button'),
                            onTap: () =>
                                setState(() => _isSignaturePadActive = true),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.1),
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
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 20,
                                        color:
                                            AppTheme.secondaryInkOf(context),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Locked to prevent scroll marks',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.text.bodySmall!.copyWith(
                                            color: AppTheme.secondaryInkOf(
                                                context),
                                          ),
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton.tonalIcon(
                            key: const ValueKey('activate_signature_button'),
                            onPressed: () =>
                                setState(() => _isSignaturePadActive = true),
                            icon: const Icon(Icons.edit_rounded, size: 20),
                            label: const Text('Unlock to sign'),
                          ),
                          TextButton.icon(
                            key: const ValueKey('open_signature_dialog_button'),
                            onPressed: () => _openSignatureDialog(rep),
                            icon: const Icon(Icons.open_in_full_rounded,
                                size: 20),
                            label: const Text('Sign in dialog'),
                          ),
                        ],
                      ),
                      if (rep.selectedJobOrder.value != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Signed by: ${rep.selectedJobOrder.value!.customerName}',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );
                }

                // Gene - Oct 13, 2026: Active signature drawing mode with active outline, clear, done lock, and full dialog options.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primary,
                          width: 1.5,
                        ),
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
                                      'lock_signature_pad_button'),
                                  // Gene - Oct 13, 2026: Removed custom compact style to satisfy tap target accessibility standards (min 48dp).
                                  onPressed: () {
                                    _onStrokeEnd();
                                    setState(
                                        () => _isSignaturePadActive = false);
                                  },
                                  icon: const Icon(Icons.check_rounded,
                                      size: 20),
                                  label: const Text('Done'),
                                ),
                              ],
                            ),
                          ),
                          SignaturePad(
                            controller: _signatureController,
                            onStrokeEnd: _onStrokeEnd,
                            enabled: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          padHasInk
                              ? Icons.check_circle_rounded
                              : Icons.touch_app_rounded,
                          size: 20,
                          color: padHasInk ? AppTheme.success : muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            padHasInk
                                ? 'Signature captured'
                                : 'Ask subscriber to sign above',
                            style: context.text.labelMedium!.copyWith(
                              color: padHasInk
                                  ? AppTheme.successInkOf(context)
                                  : AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: padHasInk
                              ? () {
                                  _signatureController.clear();
                                  rep.setSignature(null);
                                }
                              : null,
                          icon: const Icon(Icons.backspace_outlined, size: 20),
                          label: const Text('Clear'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _onStrokeEnd();
                            setState(() => _isSignaturePadActive = false);
                          },
                          icon: const Icon(Icons.lock_rounded, size: 20),
                          label: const Text('Done'),
                        ),
                      ],
                    ),
                    // Gene - Oct 13, 2026: Display subscriber name matching AppSheet signature block footer.
                    if (rep.selectedJobOrder.value != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Signed by: ${rep.selectedJobOrder.value!.customerName}',
                        style: context.text.bodySmall!.copyWith(
                          color: AppTheme.secondaryInkOf(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            */
            // Gene - Oct 13, 2026: Replaced signature dialog and multi-branch drawing view with a robust locking signature pad:
            // Starts locked to prevent accidental scratch gestures while scrolling.
            // Technician taps "Unlock to sign" to sign. Tapping "Done" / "Save" immediately locks and captures the signature.
            // When locked, static signature is shown and can be unlocked to sign again.
            SignalBuilder(
              builder: (context) {
                final existing = rep.signature.value;
                final existingBytes =
                    PhotoStorageService.instance.resolveBytes(existing) ??
                        DataUrl.decode(existing);

                // State 1: Locked with an existing or saved signature
                if (!_isSignaturePadActive && existingBytes != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 140,
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
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded,
                              size: 20, color: AppTheme.success),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Signature saved · Locked',
                              style: context.text.labelMedium!.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.successInkOf(context),
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            key: const ValueKey('unlock_signature_pad_button'),
                            onPressed: () {
                              rep.setSignature(null);
                              _signatureController.clear();
                              setState(() => _isSignaturePadActive = true);
                            },
                            icon: const Icon(Icons.lock_open_rounded, size: 20),
                            label: const Text('Unlock to sign'),
                          ),
                        ],
                      ),
                      if (rep.selectedJobOrder.value != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Signed by: ${rep.selectedJobOrder.value!.customerName}',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );
                }

                // State 2: Locked without a signature (scroll-safe placeholder)
                if (!_isSignaturePadActive) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkInput : AppTheme.fillLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.borderDark
                                : AppTheme.borderLight,
                            width: 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const ValueKey('unlock_signature_pad_button'),
                            onTap: () =>
                                setState(() => _isSignaturePadActive = true),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.1),
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
                                      Icon(
                                        Icons.lock_outline_rounded,
                                        size: 20,
                                        color:
                                            AppTheme.secondaryInkOf(context),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Locked to prevent scroll marks',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.text.bodySmall!.copyWith(
                                            color: AppTheme.secondaryInkOf(
                                                context),
                                          ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.tonalIcon(
                            key: const ValueKey('activate_signature_button'),
                            onPressed: () =>
                                setState(() => _isSignaturePadActive = true),
                            icon: const Icon(Icons.lock_open_rounded, size: 20),
                            label: const Text('Unlock to sign'),
                          ),
                        ],
                      ),
                      if (rep.selectedJobOrder.value != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Signed by: ${rep.selectedJobOrder.value!.customerName}',
                          style: context.text.bodySmall!.copyWith(
                            color: AppTheme.secondaryInkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  );
                }

                // State 3: Active signature drawing mode
                return ListenableBuilder(
                  listenable: _signatureController,
                  builder: (context, _) {
                    final padHasInk = !_signatureController.isEmpty;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primary,
                              width: 1.5,
                            ),
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
                                          'lock_signature_pad_button'),
                                      onPressed: () =>
                                          _saveAndLockSignature(rep),
                                      icon: const Icon(Icons.check_rounded,
                                          size: 20),
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
                          children: [
                            Icon(
                              padHasInk
                                  ? Icons.check_circle_rounded
                                  : Icons.touch_app_rounded,
                              size: 20,
                              color: padHasInk ? AppTheme.success : muted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                padHasInk
                                    ? 'Signature drawn · Tap Done to lock'
                                    : 'Ask subscriber to sign above',
                                style: context.text.labelMedium!.copyWith(
                                  color: padHasInk
                                      ? AppTheme.successInkOf(context)
                                      : AppTheme.secondaryInkOf(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              key: const ValueKey('clear_signature_button'),
                              onPressed: padHasInk
                                  ? () {
                                      _signatureController.clear();
                                      rep.setSignature(null);
                                    }
                                  : null,
                              icon: const Icon(Icons.backspace_outlined,
                                  size: 20),
                              label: const Text('Clear'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              key: const ValueKey('save_signature_pad_button'),
                              onPressed: () => _saveAndLockSignature(rep),
                              icon: const Icon(Icons.lock_rounded, size: 20),
                              label: const Text('Done'),
                            ),
                          ],
                        ),
                        if (rep.selectedJobOrder.value != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Signed by: ${rep.selectedJobOrder.value!.customerName}',
                            style: context.text.bodySmall!.copyWith(
                              color: AppTheme.secondaryInkOf(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
