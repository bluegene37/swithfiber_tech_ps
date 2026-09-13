import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/image_capture_service.dart';
import '../../../core/services/map_navigation_service.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/action_pair.dart';
import '../../../core/widgets/sticky_action_bar.dart';
import '../../catalogs/models/catalog_model.dart';
import '../../catalogs/services/catalog_service.dart';
import '../../catalogs/widgets/router_model_picker.dart';
import '../../diagnostics/widgets/radius_connection_card.dart';
import '../../reports/widgets/photo_capture_tile.dart';
import '../../reports/widgets/signature_pad.dart';
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

  const ServiceOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.signals,
    this.scanBarcode,
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

  // Materials Counters
  int _dropCableMeters = 0;
  int _fastConnectors = 0;
  int _sClamps = 0;

  // Photos (Data URLs)
  String? _photo1;
  String? _photo2;
  String? _photo3;

  bool _isSubmitting = false;

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
      _dropCableMeters = order.materialsUsed['Drop Cable (m)'] ?? 0;
      _fastConnectors = order.materialsUsed['SC/APC Fast Connector'] ?? 0;
      _sClamps = order.materialsUsed['S-Clamp'] ?? 0;
      _photo1 = order.image1;
      _photo2 = order.image2;
      _photo3 = order.houseFrontPicture ?? order.image3;
    }

    // Show what is on file straight away; the catalog request that follows
    // can take seconds on a poor link and must not leave the model blank
    // or overwrite a choice made while it was in flight.
    _selectedRouterModel = _initialRouterModel(_availableRouters);
    _loadCatalog();
  }

  ServiceOrderDto? _findOrder() {
    return widget.signals.allOrders.value
        .where((o) => o.id == widget.orderId)
        .firstOrNull;
  }

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

  @override
  void dispose() {
    _signatureController.dispose();
    _remarksController.dispose();
    _newSnController.dispose();
    _pulloutSnController.dispose();
    _pulloutRemarksController.dispose();
    super.dispose();
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

    final materials = <String, int>{};
    if (_dropCableMeters > 0) materials['Drop Cable (m)'] = _dropCableMeters;
    if (_fastConnectors > 0) {
      materials['SC/APC Fast Connector'] = _fastConnectors;
    }
    if (_sClamps > 0) materials['S-Clamp'] = _sClamps;

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
      clientSignature: signature ?? order.clientSignature,
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

        return Scaffold(
          appBar: AppBar(
            // Ticket id only, same as the job detail; the concern is the
            // first line of the subscriber card. One line at 200% text.
            title: Text(
              'SO-${order.id.toString().padLeft(4, '0')}',
              style:
                  context.text.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
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
              const SizedBox(height: 16),
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
          ],
        ),
      ),
    );
  }

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
              onChanged: (v) => setState(() => _dropCableMeters = v),
            ),
            const Divider(height: 16),
            MaterialCounterRow(
              name: 'SC/APC Fast Connectors',
              unit: 'pcs',
              count: _fastConnectors,
              fieldKey: const ValueKey('counter_field_fast_connectors'),
              onChanged: (v) => setState(() => _fastConnectors = v),
            ),
            const Divider(height: 16),
            MaterialCounterRow(
              name: 'S-Clamps',
              unit: 'pcs',
              count: _sClamps,
              fieldKey: const ValueKey('counter_field_s_clamps'),
              onChanged: (v) => setState(() => _sClamps = v),
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
                    onChanged: (v) => setState(() => _photo1 = v),
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
                    onChanged: (v) => setState(() => _photo2 = v),
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
                    onChanged: (v) => setState(() => _photo3 = v),
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
}
