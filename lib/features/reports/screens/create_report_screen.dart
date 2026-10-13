import 'dart:async';

import 'package:flutter/material.dart';
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
import '../widgets/optical_power_gauge.dart';
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
  // Gene - Oct 12, 2026: Added _availableLcps for LCP-first hierarchical workflow.
  List<RouterDto> _availableRouters = CatalogService.fallbackRouters;
  List<NapDto> _availableNaps = CatalogService.fallbackNaps;
  List<PortDto> _availablePorts = CatalogService.fallbackPorts;
  List<LcpOptionDto> _availableLcps = CatalogService.fallbackLcps;

  /// Whether the NAP port tiles are open. Closed by default: the header
  /// already names the port the job arrived with, and sixteen tiles pushed
  /// the photo step below the fold. Picking a tile closes it again.
  bool _portsExpanded = false;

  /// Whether the remarks box is open. Closed by default with the text (or
  /// "No remarks") read back, opened with one visible button, the same way
  /// the port tiles work.
  bool _remarksExpanded = false;

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

  Timer? _signatureDebounce;

  @override
  void dispose() {
    _signatureDebounce?.cancel();
    _signatureController.dispose();
    _serialController.dispose();
    _remarksController.dispose();
    _dbmController.dispose();
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

              // Step 2: Optical Power Reading Gauge & Input
              _buildOpticalPowerSection(rep),
              const SizedBox(height: 16),

              // Step 3: Materials Consumed On-Site (BOM)
              _buildMaterialsSection(rep),
              const SizedBox(height: 16),

              // Step 4: Photo Proof Attachments
              _buildPhotoProofSection(rep),
              const SizedBox(height: 16),

              // Step 5: Customer Electronic Sign-Off
              KeyedSubtree(
                key: _signOffSectionKey,
                child: _buildCustomerSignOffSection(rep),
              ),
              const SizedBox(height: 16),

              // Step 6: Technician Remarks & Status
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

  Widget _buildOpticalPowerSection(ReportSignals rep) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /*
            Row(
              children: [
                const Expanded(
                  child: StepHeader(
                      number: 1, title: 'Optical reading', done: true),
                ),
              ],
            ),
            */
            // Gene - Oct 13, 2026: Set StepHeader number to 2 for Optical reading following Hardware in AppSheet flow.
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

            // 4. Modem / ONT Serial Number: text box with barcode scanner button
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
                // Gene - Oct 13, 2026: Set StepHeader to step 6 (Technician remarks & status) following AppSheet workflow.
                Row(
                  children: [
                    const Expanded(
                      child: StepHeader(
                          number: 6,
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

            /*
            return Column(
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
            */
            // Gene - Oct 13, 2026: Added StepHeader number 3 for Materials consumed (BOM) following AppSheet workflow.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StepHeader(
                        number: 3,
                        // Gene - Oct 13, 2026: Set title to Materials Consumed On-Site matching test contract and AppSheet terminology.
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
                      builder: (context) => StepHeader(
                        number: 5,
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
                          TextButton.icon(
                            onPressed: () {
                              rep.setSignature(null);
                              _signatureController.clear();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 24),
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

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SignaturePad(
                      controller: _signatureController,
                      onStrokeEnd: _onStrokeEnd,
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
                                : 'Ask the subscriber to sign in the box above',
                            style: context.text.labelMedium!.copyWith(
                              color: padHasInk
                                  ? AppTheme.successInkOf(context)
                                  : AppTheme.secondaryInkOf(context),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: padHasInk
                              ? () {
                                  _signatureController.clear();
                                  rep.setSignature(null);
                                }
                              : null,
                          icon: const Icon(Icons.backspace_outlined, size: 24),
                          label: const Text('Clear'),
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
          ],
        ),
      ),
    );
  }
}
