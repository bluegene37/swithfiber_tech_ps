import 'package:flutter/widgets.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/map_navigation_service.dart';
import '../models/job_order_model.dart';

/// Opens turn-by-turn navigation to a job: by coordinates when the order has
/// a GPS fix, otherwise by its street address. Shared by the Today home and
/// the job card so both "Navigate" buttons behave the same.
Future<bool> navigateToJob(JobOrderDto job, {BuildContext? context}) {
  final latLng = job.latLng;
  if (latLng != null) {
    return MapNavigationService.navigateToCoordinates(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      destinationLabel: job.customerName,
      context: context,
    );
  }
  final address = [
    job.address,
    if (job.barangay?.isNotEmpty == true) job.barangay!,
    if (job.city?.isNotEmpty == true) job.city!,
    'Philippines',
  ].join(', ');
  return MapNavigationService.navigateToAddress(address);
}

/// Distance from the technician's last known position to the job, formatted
/// for a row lead (`2.4 km`), or null when either side has no fix.
String? distanceLabelFor(JobOrderDto job) {
  final me = LocationService.instance.lastKnownPosition;
  final there = job.latLng;
  if (me == null || there == null) return null;
  final meters = LocationService.instance.distanceBetween(
    startLat: me.latitude,
    startLng: me.longitude,
    endLat: there.latitude,
    endLng: there.longitude,
  );
  return LocationService.instance.formatDistance(meters);
}

/// Metres from the technician to the job, or null without a fix on both.
double? distanceMetersFor(JobOrderDto job) {
  final me = LocationService.instance.lastKnownPosition;
  final there = job.latLng;
  if (me == null || there == null) return null;
  return LocationService.instance.distanceBetween(
    startLat: me.latitude,
    startLng: me.longitude,
    endLat: there.latitude,
    endLng: there.longitude,
  );
}
