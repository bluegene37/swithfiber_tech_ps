// Gene - Nov, 23, 2026: Added NAP port occupancy calculation and job/service-order to LCP/NAP pole matching helpers.
import '../../jobs/models/job_order_model.dart';
import '../../service_orders/models/service_order_model.dart';
import '../models/lcp_nap_model.dart';

/// Describes a subscriber or ticket currently occupying a port on a NAP box.
class OccupiedPortInfo {
  final int portNumber;
  final String portLabel;
  final String subscriberName;
  final String reference;
  final String status;
  final bool isServiceOrder;

  const OccupiedPortInfo({
    required this.portNumber,
    required this.portLabel,
    required this.subscriberName,
    required this.reference,
    required this.status,
    this.isServiceOrder = false,
  });
}

/// Extracts the positive integer port number from raw port strings like
/// `'PORT 004'`, `'Port 4'`, `'P4'`, or `'4'`. Returns `null` for `'0'` or blank.
int? parsePortNumber(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '0') return null;
  final match = RegExp(r'(\d+)').firstMatch(trimmed);
  if (match == null) return null;
  final value = int.tryParse(match.group(1)!);
  if (value == null || value <= 0) return null;
  return value;
}

String _compact(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');

int? _extractNumber(String raw, String prefix) {
  final clean = raw.trim();
  if (clean.isEmpty || clean == '0') return null;
  final prefixed = RegExp(
    '^$prefix[-\\s_]*0*(\\d+)\$',
    caseSensitive: false,
  ).firstMatch(clean);
  if (prefixed != null) {
    final n = int.tryParse(prefixed.group(1)!);
    return (n != null && n > 0) ? n : null;
  }
  final bare = RegExp(r'^0*(\d+)$').firstMatch(clean);
  if (bare != null) {
    final n = int.tryParse(bare.group(1)!);
    return (n != null && n > 0) ? n : null;
  }
  return null;
}

bool _lcpMatches(LcpNapDto location, {int? lcpId, String? lcpName}) {
  final locLcp = location.lcp.trim();
  final hasLcpName =
      lcpName != null && lcpName.trim().isNotEmpty && lcpName.trim() != '0';
  final hasLcpId = lcpId != null && lcpId > 0;
  if (!hasLcpName && !hasLcpId) return true;
  if (locLcp.isEmpty) return false;

  if (hasLcpName) {
    if (_compact(locLcp) == _compact(lcpName)) return true;
    final locNum = _extractNumber(locLcp, 'lcp');
    final targetNum = _extractNumber(lcpName, 'lcp');
    if (locNum != null && targetNum != null) return locNum == targetNum;
    return false;
  }

  // Only lcpId is given
  final locNum = _extractNumber(locLcp, 'lcp');
  if (locNum != null) return locNum == lcpId;
  return false;
}

bool _napMatches(LcpNapDto location, {String? napName}) {
  if (napName == null) return false;
  final clean = napName.trim();
  if (clean.isEmpty || clean == '0') return false;

  final compactTarget = _compact(clean);
  if (_compact(location.lcpNap) == compactTarget) return true;
  if (_compact(location.nap) == compactTarget) return true;

  final locNum = _extractNumber(location.nap, 'nap');
  final targetNum = _extractNumber(clean, 'nap');
  if (locNum != null && targetNum != null && locNum == targetNum) {
    return true;
  }
  return false;
}

/// Returns true if [location] matches the supplied NAP/LCP identifiers.
bool matchesNapLocation(
  LcpNapDto location, {
  int? napId,
  String? napName,
  int? lcpId,
  String? lcpName,
}) {
  if (napId != null && napId > 0 && location.id == napId) {
    return true;
  }
  if (napName != null && napName.trim().isNotEmpty && napName.trim() != '0') {
    final compactTarget = _compact(napName);
    if (location.lcpNap.trim().isNotEmpty &&
        _compact(location.lcpNap) == compactTarget) {
      return true;
    }
    if (_napMatches(location, napName: napName) &&
        _lcpMatches(location, lcpId: lcpId, lcpName: lcpName)) {
      return true;
    }
  }
  if (napId != null && napId > 0) {
    final syntheticNap = 'NAP $napId';
    if (_napMatches(location, napName: syntheticNap) &&
        _lcpMatches(location, lcpId: lcpId, lcpName: lcpName)) {
      return true;
    }
  }
  return false;
}

/// Finds the matching [LcpNapDto] from [locations], or `null` when none matches.
LcpNapDto? findMatchingNapLocation(
  List<LcpNapDto> locations, {
  int? napId,
  String? napName,
  int? lcpId,
  String? lcpName,
}) {
  // Prefer direct ID match first when available.
  if (napId != null && napId > 0) {
    for (final loc in locations) {
      if (loc.id == napId) return loc;
    }
  }
  for (final loc in locations) {
    if (matchesNapLocation(
      loc,
      napId: napId,
      napName: napName,
      lcpId: lcpId,
      lcpName: lcpName,
    )) {
      return loc;
    }
  }
  return null;
}

/// Computes occupied port entries (1..[location.portTotal]) by cross-referencing
/// cached [jobs] and [serviceOrders].
Map<int, OccupiedPortInfo> computeNapPortOccupancy({
  required LcpNapDto location,
  List<JobOrderDto> jobs = const [],
  List<ServiceOrderDto> serviceOrders = const [],
}) {
  final occupied = <int, OccupiedPortInfo>{};
  final total = location.portTotal;
  if (total <= 0) return occupied;

  for (final job in jobs) {
    if (job.isRescheduled && !job.hasCompletedReport) continue;
    final lowerStatus = job.status.trim().toLowerCase();
    if (lowerStatus.contains('cancel')) continue;

    if (!matchesNapLocation(
      location,
      napId: job.napId,
      napName: job.nap,
      lcpId: job.lcpId,
    )) {
      continue;
    }

    final portNum = parsePortNumber(job.portId);
    if (portNum == null || portNum < 1 || portNum > total) continue;

    occupied.putIfAbsent(
      portNum,
      () => OccupiedPortInfo(
        portNumber: portNum,
        portLabel: job.portId!.trim(),
        subscriberName: job.customerName,
        reference: job.ticketNumber,
        status: job.status,
      ),
    );
  }

  for (final order in serviceOrders) {
    if (!order.isOpen) continue;
    final effNap =
        (order.newNAP?.trim().isNotEmpty == true) ? order.newNAP : order.nap;
    final effLcp =
        (order.newLCP?.trim().isNotEmpty == true) ? order.newLCP : order.lcp;
    final effPort =
        (order.newPORT?.trim().isNotEmpty == true) ? order.newPORT : order.port;

    if (!matchesNapLocation(
      location,
      napName: effNap,
      lcpName: effLcp,
    )) {
      continue;
    }

    final portNum = parsePortNumber(effPort);
    if (portNum == null || portNum < 1 || portNum > total) continue;

    occupied.putIfAbsent(
      portNum,
      () => OccupiedPortInfo(
        portNumber: portNum,
        portLabel: effPort!.trim(),
        subscriberName: order.fullName,
        reference: 'SO-${order.id.toString().padLeft(4, '0')}',
        status: order.supportStatus,
        isServiceOrder: true,
      ),
    );
  }

  return occupied;
}

/// Counts available (unoccupied) splitter ports on [location].
int countFreePorts(
  LcpNapDto location, {
  List<JobOrderDto> jobs = const [],
  List<ServiceOrderDto> serviceOrders = const [],
}) {
  final used = computeNapPortOccupancy(
    location: location,
    jobs: jobs,
    serviceOrders: serviceOrders,
  ).length;
  return (location.portTotal - used).clamp(0, location.portTotal);
}
