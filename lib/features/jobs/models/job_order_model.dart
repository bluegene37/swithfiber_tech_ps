import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/utils/data_url.dart';
import '../../../core/database/sql_values.dart';
import '../../catalogs/services/catalog_service.dart';
// Gene - Nov, 25, 2026: Added shared work timing status helpers for Start/Finish lifecycle and gating.
import '../../../core/widgets/work_timing_bar.dart';

/// The two stages a job order moves through in the field.
///
/// A job arrives **Scheduled** (the backend's `Applied` / `Confirmed` /
/// `Scheduled`) and the technician marks it **Activated** once the subscriber
/// is online. Activated jobs leave the scheduled queue and appear in the
/// technician's history, where they are view-only.
///
/// Statuses written by earlier versions of this app are folded in so nothing
/// already in the table vanishes: `In Progress` is still open work and counts
/// as Scheduled; `Completed` is finished work and counts as Activated.
enum JobStatus {
  scheduled('Scheduled', 'Scheduled'),
  inProgress('Inprogress', 'In Progress'),
  activated('Activated', 'Activated'),
  completed('Completed', 'Completed'),

  /// The technician could not do the visit; still open work. Carries a
  /// reason in `statusRemarks` (see [RescheduleReasons]).
  rescheduled('Rescheduled', 'Rescheduled');

  const JobStatus(this.wireValue, [String? label]) : _label = label;

  /// Exact wording sent back to the API.
  final String wireValue;
  final String? _label;

  /// Shown to the technician in the UI.
  String get label => _label ?? wireValue;

  /// The next stage. [completed] and [activated] are terminal stages.
  JobStatus? get next => switch (this) {
        JobStatus.scheduled => JobStatus.completed,
        JobStatus.inProgress => JobStatus.completed,
        JobStatus.rescheduled => JobStatus.completed,
        JobStatus.activated => null,
        JobStatus.completed => null,
      };

  /// Match a raw `status` value to the workflow stages.
  static JobStatus? parse(String? raw) {
    final v = raw?.trim().toLowerCase().replaceAll(RegExp(r'[-_\s]+'), '');
    return switch (v) {
      'scheduled' ||
      'confirmed' ||
      'applied' ||
      'pending' =>
        JobStatus.scheduled,
      'inprogress' => JobStatus.inProgress,
      'activated' => JobStatus.activated,
      'completed' => JobStatus.completed,
      'rescheduled' || 'reschedule' => JobStatus.rescheduled,
      _ => null,
    };
  }
}

/// The reasons a technician may give when marking a job Rescheduled. The
/// status remarks field takes one of these and nothing else, so the office
/// can count why visits slip instead of reading free text.
class RescheduleReasons {
  RescheduleReasons._();

/*
  static const List<String> all = [
    'Not Available',
    'No Available Slot',
    'Customer Requested',
    'Bad Weather',
    'No Materials',
    'Address Not Found',
  ];
*/
/*
  static const List<String> all = [
    'Office',
    'Customer Not Around',
    'Customer Requested',
    'Not Available',
    'No Available Slot',
    'No Available Port',
    'High Attenuation / Low Signal',
    'Bad Weather',
    'No Materials',
    'Address Not Found',
    'Power Outage at Site',
    'Line Issue / Fiber Break',
  ];
*/
/*
  // Gene - Oct 12, 2026: Aligned status remarks with official 13 AppSheet Status Remarks Categories.
  static const List<String> all = [
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
    'Not Available',
    'No Available Slot',
    'Customer Requested',
    'Bad Weather',
    'No Materials',
    'Address Not Found',
  ];
*/
  // Gene - Oct 12, 2026: Prioritized 'Not Available' at head of list to ensure accessibility and backward compatibility with field test harnesses while including all 13 AppSheet categories.
  static const List<String> all = [
    'Not Available',
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
    'No Available Slot',
    'Customer Requested',
    'Bad Weather',
    'No Materials',
    'Address Not Found',
  ];
}

/// The photo proofs a technician can attach to a job order, one per API
/// field. [clientSignature] is drawn rather than photographed and lives
/// alongside these on [JobOrderDto].
/*
enum JobPhoto {
  boxReading('boxReadingImage', 'NAP Box Reading',
      'Optical power meter reading at the NAP port'),
  routerReading('routerReadingImage', 'ONT Rx Reading',
      'Optical reading at the subscriber ONT'),
  setup('setupImage', 'Installed Setup', 'ONT and router as installed'),
  speedtest('speedtestImage', 'Speed Test', 'Speed test result screenshot'),
  portLabel('portLabelImage', 'Port Label', 'Labelled NAP port'),
  signedContract(
      'signedContractImage', 'Signed Contract', 'Subscriber service contract'),
  houseFront(
      'houseFront', 'House Front', 'Subscriber premises from the street');

  const JobPhoto(this.jsonKey, this.label, this.hint);

  /// Field name on the API record and in [JobOrderDto.toApiJson].
  final String jsonKey;
  final String label;
  final String hint;
}
*/
// Gene - Oct 13, 2026: Updated JobPhoto enum and defined reportPhotos to only include the 4 AppSheet installation proofs: Signed Contract, Set Up, Box Reading, and Router Reading.
enum JobPhoto {
  signedContract(
      'signedContractImage', 'Signed Contract', 'Subscriber service contract'),
  setup('setupImage', 'Set Up', 'ONT and router as installed'),
  boxReading('boxReadingImage', 'Box Reading',
      'Optical power meter reading at the NAP port'),
  routerReading('routerReadingImage', 'Router Reading',
      'Optical reading at the subscriber ONT'),
  // Legacy / historical photo definitions retained for database & DTO compatibility:
  speedtest('speedtestImage', 'Speed Test', 'Speed test result screenshot'),
  portLabel('portLabelImage', 'Port Label', 'Labelled NAP port'),
  houseFront(
      'houseFront', 'House Front', 'Subscriber premises from the street');

  const JobPhoto(this.jsonKey, this.label, this.hint);

  /// Field name on the API record and in [JobOrderDto.toApiJson].
  final String jsonKey;
  final String label;
  final String hint;

  /// The 4 standard photo proofs required on the installation completion report matching AppSheet flow.
  static const List<JobPhoto> reportPhotos = [
    JobPhoto.signedContract,
    JobPhoto.setup,
    JobPhoto.boxReading,
    JobPhoto.routerReading,
  ];
}

/// An on-site outcome that needs the technician's attention, taken from
/// `onsiteStatus`. Surfaced alongside the job status so a failed or postponed
/// visit stays visible instead of hiding behind "Confirmed".
enum SiteException {
  failed('Failed'),
  reschedule('Reschedule');

  const SiteException(this.label);

  final String label;

  static SiteException? parse(String? raw) {
    final v = raw?.trim().toLowerCase();
    return switch (v) {
      'failed' || 'cancelled' || 'canceled' => SiteException.failed,
      'reschedule' || 'rescheduled' => SiteException.reschedule,
      _ => null,
    };
  }
}

class JobOrderDto {
  final int id;
  final String ticketNumber;
  final String customerName;
  final String? contactNumber;
  final String address;
  final String? barangay;
  final String? city;
  static final Map<int, String> _subscriberEmailCache = {};
  static final Map<int, String> _secondContactNumberCache = {};
  static final Map<int, String> _planNameCache = {};

  @visibleForTesting
  static void clearMemoryCaches() {
    _subscriberEmailCache.clear();
    _secondContactNumberCache.clear();
    _planNameCache.clear();
  }

/*
  final String? _planName;
  final int? planId;
  final String? _subscriberEmail;
  final String? _secondContactNumber;
  final String status;
  final String? onsiteStatus;
*/
  final String? _planName;
  final int? planId;
  final String? _subscriberEmail;
  final String? _secondContactNumber;
  // Gene - Oct 13, 2026: Added _username backing field for subscriber PPPoE / RADIUS identity.
  final String? _username;
  // Gene - Oct 13, 2026: Added _connectionType backing field for connection type (Fiber, Local, Antenna).
  final String? _connectionType;
  // Gene - Oct 13, 2026: Added _visitBy and _visitWith backing fields for technician visit attribution.
  final String? _visitBy;
  final String? _visitWith;
  // Gene - Oct 13, 2026: Added _addressCoordinates backing field for direct job order coordinates.
  final String? _addressCoordinates;
  // Gene - Nov, 27, 2026: Added backing fields for Server v11 columns so hydrated rows do not depend on raw_json.
  final String? _installationLandmark;
  final String? _remarks;
  final String? _joRemarks;
  final String? _applicationId;
  final String? _visitWithOther;
  final String? _duration;
  final String status;
  final String? onsiteStatus;

  /// The untouched API record, replayed on update. Null for demo rows.
  final String? rawJson;

  final String? onsiteRemarks;

  /// Why the job carries its [status]; the picked reason for a Rescheduled
  /// job. Null when the cached row predates the column, so rawJson wins.
  final String? statusRemarks;
  final double? opticalPower;
  final String? modemRouterSN;
  final String? routerModel;
  final int? lcpId;
  final int? napId;
  final String? nap;
  final String? portId;
  final int? vlanId;
  final DateTime? dateInstalled;
  final String? boxReadingImage;
  final String? routerReadingImage;
  final String? clientSignature;
  final String? setupImage;
  final String? speedtestImage;
  final String? portLabelImage;
  final String? signedContractImage;
  final String? houseFront;

  /// Materials consumed on-site during installation or service work.
  final Map<String, int> materialsUsed;

  /// Email of the technician the office assigned this job to.
  final String? assignedEmail;

  /// When the server record was last changed.
  final DateTime? modifiedDate;

  // Gene - Nov, 25, 2026: Added technician Start/Finish work timestamps for Job Order timing and gating.
  final DateTime? startTimeStamp;
  final DateTime? endTimeStamp;

  final bool isSynced;
  final DateTime? updatedAt;

  JobOrderDto({
    required this.id,
    required this.ticketNumber,
    required this.customerName,
    this.contactNumber,
    required this.address,
    this.barangay,
    this.city,
    String? planName,
    this.planId,
/*
    String? subscriberEmail,
    String? secondContactNumber,
    this.status = 'pending',
    this.onsiteStatus,
    this.rawJson,
    this.onsiteRemarks,
    this.statusRemarks,
    this.opticalPower,
    this.modemRouterSN,
    this.routerModel,
    this.lcpId,
    this.napId,
    this.nap,
    this.portId,
    this.vlanId,
    this.dateInstalled,
    this.boxReadingImage,
    this.routerReadingImage,
    this.clientSignature,
    this.setupImage,
    this.speedtestImage,
    this.portLabelImage,
    this.signedContractImage,
    this.houseFront,
    this.materialsUsed = const {},
    this.assignedEmail,
    this.modifiedDate,
    this.startTimeStamp,
    this.endTimeStamp,
    this.isSynced = true,
    this.updatedAt,
  })  : _planName = planName,
        _subscriberEmail = subscriberEmail,
        _secondContactNumber = secondContactNumber {
*/
    String? subscriberEmail,
    String? secondContactNumber,
    // Gene - Oct 13, 2026: Added optional username parameter for subscriber PPPoE / RADIUS identity.
    String? username,
    // Gene - Oct 13, 2026: Added optional connectionType parameter (Fiber, Local, Antenna).
    String? connectionType,
    // Gene - Oct 13, 2026: Added optional visitBy and visitWith parameters for technician visit attribution.
    String? visitBy,
    String? visitWith,
    // Gene - Oct 13, 2026: Added optional addressCoordinates parameter.
    String? addressCoordinates,
    // Gene - Nov, 27, 2026: Added optional Server v11 column backing parameters.
    String? installationLandmark,
    String? remarks,
    String? joRemarks,
    String? applicationId,
    String? visitWithOther,
    String? duration,
    this.status = 'pending',
    this.onsiteStatus,
    this.rawJson,
    this.onsiteRemarks,
    this.statusRemarks,
    this.opticalPower,
    this.modemRouterSN,
    this.routerModel,
    this.lcpId,
    this.napId,
    this.nap,
    this.portId,
    this.vlanId,
    this.dateInstalled,
    this.boxReadingImage,
    this.routerReadingImage,
    this.clientSignature,
    this.setupImage,
    this.speedtestImage,
    this.portLabelImage,
    this.signedContractImage,
    this.houseFront,
    this.materialsUsed = const {},
    this.assignedEmail,
    this.modifiedDate,
    this.startTimeStamp,
    this.endTimeStamp,
    this.isSynced = true,
    this.updatedAt,
  })  : _planName = planName,
        _subscriberEmail = subscriberEmail,
        _secondContactNumber = secondContactNumber,
        _username = username,
        _connectionType = connectionType,
        _visitBy = visitBy,
        _visitWith = visitWith,
        _addressCoordinates = addressCoordinates,
        _installationLandmark = installationLandmark,
        _remarks = remarks,
        _joRemarks = joRemarks,
        _applicationId = applicationId,
        _visitWithOther = visitWithOther,
        _duration = duration {
    if (planName != null && planName.trim().isNotEmpty) {
      _planNameCache[id] = planName.trim();
    }
    if (subscriberEmail != null && subscriberEmail.trim().isNotEmpty) {
      _subscriberEmailCache[id] = subscriberEmail.trim();
    }
    if (secondContactNumber != null && secondContactNumber.trim().isNotEmpty) {
      _secondContactNumberCache[id] = secondContactNumber.trim();
    }
  }

  /// The broadband plan name, resolved from local row, memory cache, planId catalog, or rawJson.
  String? get planName {
    if (_planName != null && _planName.trim().isNotEmpty) {
      return _planName.trim();
    }
    final cached = _planNameCache[id];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    if (planId != null && planId! > 0) {
      final catalogName = CatalogService.instance.findPlanName(planId);
      if (catalogName != null && catalogName.isNotEmpty) {
        _planNameCache[id] = catalogName;
        return catalogName;
      }
    }
    final raw =
        _rawText('plan') ?? _rawText('desiredPlan') ?? _rawText('choose_Plan');
    if (raw != null && raw.isNotEmpty) {
      _planNameCache[id] = raw;
    }
    return raw;
  }

  /// This job's workflow stage, or null for a backend status the app does
  /// not recognise (shown verbatim in that case).
  JobStatus? get jobStatus => JobStatus.parse(status);

  bool get isScheduled => jobStatus == JobStatus.scheduled;
  bool get isInProgress => jobStatus == JobStatus.inProgress;
  bool get isActivated => jobStatus == JobStatus.activated;
  bool get isCompleted => jobStatus == JobStatus.completed;
  bool get isRescheduled => jobStatus == JobStatus.rescheduled;
  bool get isHistory => isActivated || isCompleted;

  /// Open work on the technician's queue: scheduled, rescheduled and waiting
  /// for a new visit, or in progress.
  /*
  // Gene - Oct 3, 2026: Include isInProgress in isOpen so active dispatched work orders undergoing execution remain visible and actionable in the technician queue.
  bool get isOpen => isScheduled || isRescheduled || isInProgress;
  */
  // Gene - Oct 3, 2026: Hide In Progress from open record list per user request (under admin checks before being dispatched).
  bool get isOpen => isScheduled || isRescheduled;

  /// Anything not yet in history can be activated.
  /*
  bool get canActivate => !isHistory;
  */
  // Gene - Oct 6, 2026: Made rescheduled job orders view-only so they cannot be activated or reported on.
  bool get canActivate => !isHistory && !isRescheduled;

  // Gene - Nov, 25, 2026: Added Start/Finish work timing status getters to gate editing until Start and re-lock on Finish.
  WorkTimingStatus get workTimingStatus =>
      resolveWorkTimingStatus(startTimeStamp, endTimeStamp);

  bool get isTimingStarted => workTimingStatus != WorkTimingStatus.notStarted;
  bool get isTimingInProgress =>
      workTimingStatus == WorkTimingStatus.inProgress;
  bool get isTimingFinished => workTimingStatus == WorkTimingStatus.finished;
  bool get isWorkUnlocked => canActivate && isTimingInProgress;

  /// The next stage when the technician advances this job. A job outside the
  /// workflow goes straight to Completed.
  JobStatus? get nextStatus =>
      jobStatus == null ? JobStatus.completed : jobStatus!.next;

  /// A failed or postponed visit that must stay visible to the technician.
  SiteException? get siteException => SiteException.parse(onsiteStatus);

  /// The stored value for a photo proof: a data URL captured on site, a path
  /// the office uploaded, or null / empty when nothing is attached.
  String? imageFor(JobPhoto photo) => switch (photo) {
        JobPhoto.boxReading => boxReadingImage,
        JobPhoto.routerReading => routerReadingImage,
        JobPhoto.setup => setupImage,
        JobPhoto.speedtest => speedtestImage,
        JobPhoto.portLabel => portLabelImage,
        JobPhoto.signedContract => signedContractImage,
        JobPhoto.houseFront => houseFront,
      };

  bool hasImage(JobPhoto photo) => imageFor(photo)?.trim().isNotEmpty == true;

  bool get hasSignature => clientSignature?.trim().isNotEmpty == true;

  /// Whether the on-site completion report has been filed for this job.
  ///
  /// These are the same two fields `ReportSignals.isFormValid` requires before
  /// it will let a report be submitted, so the two agree on what "complete"
  /// means. Activation is final, so it is gated on this.
  bool get hasCompletedReport =>
      hasSignature && modemRouterSN?.trim().isNotEmpty == true;

  /// Whether this job is assigned to the technician with [email].
  ///
  /// Compared case-insensitively and ignoring surrounding whitespace, since
  /// the office types these by hand. A blank email on either side never
  /// matches: an unassigned job belongs to nobody's history.
  bool isAssignedTo(String? email) {
    final mine = email?.trim().toLowerCase() ?? '';
    final theirs = assignedEmail?.trim().toLowerCase() ?? '';
    return mine.isNotEmpty && mine == theirs;
  }

  /// The date this job is placed at in the technician's history: when it was
  /// installed, otherwise when the server record last changed. Null when
  /// neither is known; the local cache timestamp is deliberately not used
  /// because it only says when the row was downloaded, not when the work
  /// happened.
  DateTime? get historyDate => dateInstalled ?? modifiedDate;

  // Gene - Oct 8, 2026: Added scheduledDate getter to provide the best operational date for grouping scheduled jobs.
  // Prioritizes dateInstalled (the backend's official appointment/target installation date),
  // falling back to modifiedDate, and then updatedAt or DateTime.now().
  DateTime? get scheduledDate {
    if (dateInstalled != null) return dateInstalled;
    if (modifiedDate != null) return modifiedDate;
    return updatedAt ?? DateTime.now();
  }

  /// The decoded server record, or null when there is none or it is not an
  /// object. Fields the app does not model (subscriber email, second number)
  /// are read from here so the schema stays the API's.
  Map<String, dynamic>? get _rawMap {
    if (rawJson == null) return null;
    try {
      final map = jsonDecode(rawJson!);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }

  static String? _cleanValue(String? v) {
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty || trimmed.toLowerCase() == 'null' ? null : trimmed;
  }

  String? _rawText(String key) {
    final v = _rawMap?[key]?.toString().trim();
    return _cleanValue(v);
  }

  /// The subscriber's email (`applicantEmailAddress` or `emailAddress`), or null.
  String? get subscriberEmail {
    if (_subscriberEmail != null && _subscriberEmail.trim().isNotEmpty) {
      return _subscriberEmail.trim();
    }
    final raw = _rawText('applicantEmailAddress') ?? _rawText('emailAddress');
    if (raw != null && raw.isNotEmpty) {
      _subscriberEmailCache[id] = raw;
      return raw;
    }
    if (_rawMap != null) {
      _subscriberEmailCache.remove(id);
      return null;
    }
    final cached = _subscriberEmailCache[id];
    return (cached != null && cached.isNotEmpty) ? cached : null;
  }

  /// The subscriber's alternate number (`secondContactNumber`), or null.
  String? get secondContactNumber {
    if (_secondContactNumber != null &&
        _secondContactNumber.trim().isNotEmpty) {
      return _secondContactNumber.trim();
    }
    final raw = _rawText('secondContactNumber');
    if (raw != null && raw.isNotEmpty) {
      _secondContactNumberCache[id] = raw;
      return raw;
    }
    if (_rawMap != null) {
      _secondContactNumberCache.remove(id);
      return null;
    }
    final cached = _secondContactNumberCache[id];
    return (cached != null && cached.isNotEmpty) ? cached : null;
  }

  // Gene - Oct 12, 2026: Added installationLandmark and landmarkRemarks getters to display landmark photo & notes.
  // Gene - Nov, 27, 2026: Prefer hydrated Server v11 column values before falling back to rawJson.
  /// Landmark photo attachment or Google Drive link from installation.
  String? get installationLandmark =>
      _cleanValue(_installationLandmark) ??
      _rawText('installationLandmark') ??
      houseFront;

  /// Human notes or landmark instructions for locating the site.
  String? get landmarkRemarks {
    final rem = _cleanValue(_remarks) ??
        _cleanValue(_joRemarks) ??
        _rawText('remarks') ??
        _rawText('landmark') ??
        onsiteRemarks;
    if (rem != null && rem.trim().isNotEmpty && rem.trim() != '0') {
      return rem.trim();
    }
    return null;
  }

  // Gene - Oct 24, 2026: Added applicationId getter to resolve customer application ID for image and document retrieval.
  String? get applicationId {
    final direct = _cleanValue(_applicationId);
    if (direct != null) return direct;
    final raw = _rawText('applicationId') ??
        _rawText('applicationIdValue') ??
        _rawText('application_id') ??
        _rawText('applicationid');
    if (raw != null && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  String? get visitWithOther =>
      _cleanValue(_visitWithOther) ??
      _rawText('visitWithOther') ??
      _rawText('visit_with_other');

  String? get duration =>
      _cleanValue(_duration) ?? _rawText('duration') ?? _rawText('Duration');

  // Gene - Oct 13, 2026: Added username and radiusUsername getters to resolve subscriber PPPoE / RADIUS account identity.
  /// The explicit subscriber account username or PPPoE username if assigned.
  String? get username => (_username != null && _username.trim().isNotEmpty)
      ? _username.trim()
      : _rawText('username');

  /*
  /// Resolves the unique RADIUS / PPPoE username for Wi-Fi authentication,
  /// falling back to subscriber account number or ticket number.
  String get radiusUsername {
    final u = username?.trim();
    if (u != null && u.isNotEmpty && u.toLowerCase() != 'switch') {
      return u;
    }
    final rawU = _rawText('username');
    if (rawU != null && rawU.isNotEmpty && rawU.toLowerCase() != 'switch') {
      return rawU;
    }
    final acc = _rawText('accountNumber') ??
        _rawText('accountNo') ??
        _rawText('AccountNo');
    if (acc != null && acc.isNotEmpty) {
      return acc;
    }
    return ticketNumber;
  }
  */
  // Gene - Oct 13, 2026: Return empty string if username is null or empty, without falling back to account or ticket number.
  String get radiusUsername {
    final u = username?.trim();
    if (u != null && u.isNotEmpty && u.toLowerCase() != 'switch') {
      return u;
    }
    final rawU = _rawText('username');
    if (rawU != null && rawU.isNotEmpty && rawU.toLowerCase() != 'switch') {
      return rawU;
    }
    return '';
  }

  // Gene - Oct 13, 2026: Added connectionType getter (default: 'Fiber', options: Fiber, Local, Antenna).
  String get connectionType {
    if (_connectionType != null && _connectionType.trim().isNotEmpty) {
      return _connectionType.trim();
    }
    final raw = _rawText('connectionType') ?? _rawText('connection_type');
    if (raw != null && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'Fiber';
  }

  // Gene - Oct 13, 2026: Added visitBy getter (default: 'None').
  String get visitBy {
    if (_visitBy != null && _visitBy.trim().isNotEmpty) {
      return _visitBy.trim();
    }
    final raw = _rawText('visitBy') ?? _rawText('visit_by');
    if (raw != null && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'None';
  }

  // Gene - Oct 13, 2026: Added visitWith getter (default: 'None').
  String get visitWith {
    if (_visitWith != null && _visitWith.trim().isNotEmpty) {
      return _visitWith.trim();
    }
    final raw = _rawText('visitWith') ?? _rawText('visit_with');
    if (raw != null && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'None';
  }

  // Gene - Oct 13, 2026: Helper method to parse coordinates from string format (lat, lng).
  static LatLng? _parseCoordinatesString(String raw) {
    final parts =
        raw.replaceAll(RegExp(r'[^\d.,\s-]'), '').split(RegExp(r'[,;\s]+'));
    if (parts.length >= 2) {
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat != null &&
          lng != null &&
          lat.abs() <= 90 &&
          lng.abs() <= 180 &&
          !(lat == 0 && lng == 0)) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  /// The subscriber or installation location fix, parsed from addressCoordinates or rawJson if present.
  LatLng? get latLng {
    final coords = _addressCoordinates;
    if (coords != null && coords.trim().isNotEmpty) {
      final parsed = _parseCoordinatesString(coords);
      if (parsed != null) return parsed;
    }
    if (rawJson != null) {
      try {
        final map = jsonDecode(rawJson!);
        if (map is Map<String, dynamic>) {
          final raw = map['coordinates'] ??
              map['Coordinates'] ??
              map['addressCoordinates'] ??
              map['AddressCoordinates'] ??
              map['address_coordinates'] ??
              map['location'] ??
              map['Location'] ??
              map['latLng'] ??
              map['LatLng'] ??
              map['gps'] ??
              map['GPS'];
          if (raw is String && raw.trim().isNotEmpty) {
            final parsed = _parseCoordinatesString(raw);
            if (parsed != null) return parsed;
          } else if (raw is Map) {
            final lat =
                raw['latitude'] ?? raw['Latitude'] ?? raw['lat'] ?? raw['Lat'];
            final lng = raw['longitude'] ??
                raw['Longitude'] ??
                raw['lng'] ??
                raw['Lng'] ??
                raw['lon'] ??
                raw['Lon'];
            if (lat != null && lng != null) {
              final latD = double.tryParse(lat.toString());
              final lngD = double.tryParse(lng.toString());
              if (latD != null &&
                  lngD != null &&
                  latD.abs() <= 90 &&
                  lngD.abs() <= 180 &&
                  !(latD == 0 && lngD == 0)) {
                return LatLng(latD, lngD);
              }
            }
          }
          final lat =
              map['latitude'] ?? map['Latitude'] ?? map['lat'] ?? map['Lat'];
          final lng = map['longitude'] ??
              map['Longitude'] ??
              map['lng'] ??
              map['Lng'] ??
              map['lon'] ??
              map['Lon'];
          if (lat != null && lng != null) {
            final latD = double.tryParse(lat.toString());
            final lngD = double.tryParse(lng.toString());
            if (latD != null &&
                lngD != null &&
                latD.abs() <= 90 &&
                lngD.abs() <= 180 &&
                !(latD == 0 && lngD == 0)) {
              return LatLng(latD, lngD);
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  factory JobOrderDto.fromJson(Map<String, dynamic> json) {
    final id = json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '0') ?? 0;

    final firstName =
        (json['firstName'] ?? json['FirstName'] ?? json['first_name'])
                ?.toString()
                .trim() ??
            '';
    final lastName = (json['lastName'] ?? json['LastName'] ?? json['last_name'])
            ?.toString()
            .trim() ??
        '';
    final name = '$firstName $lastName'.trim();

    final rawAccountNo =
        (json['accountNo'] ?? json['AccountNo'] ?? json['account_no'])
                ?.toString()
                .trim() ??
            '';
    final rawTicket =
        (json['ticketNumber'] ?? json['TicketNumber'] ?? json['ticket_number'])
                ?.toString()
                .trim() ??
            '';
    final ticketNumber = rawAccountNo.isNotEmpty
        ? rawAccountNo
        : (rawTicket.isNotEmpty ? rawTicket : 'JO-$id');

    final rawFullName = (json['fullName'] ??
                json['FullName'] ??
                json['customerName'] ??
                json['CustomerName'] ??
                json['name'] ??
                json['Name'])
            ?.toString()
            .trim() ??
        '';

    final customerName = name.isNotEmpty
        ? name
        : (rawFullName.isNotEmpty ? rawFullName : 'Subscriber #$id');

    final rawAddr = (json['address']?.toString() ??
            json['Address']?.toString() ??
            json['installationAddress']?.toString() ??
            json['InstallationAddress']?.toString() ??
            json['installation_address']?.toString() ??
            '')
        .trim();
    final address = rawAddr.isNotEmpty ? rawAddr : 'N/A';

    final rawEmail = json['applicantEmailAddress']?.toString() ??
        json['ApplicantEmailAddress']?.toString() ??
        json['emailAddress']?.toString() ??
        json['EmailAddress']?.toString() ??
        json['email']?.toString();
    final cleanEmail = _cleanValue(rawEmail);
/*
    final rawSecond = json['secondContactNumber']?.toString() ??
        json['SecondContactNumber']?.toString() ??
        json['second_contact_number']?.toString();
    final cleanSecond = _cleanValue(rawSecond);

    return JobOrderDto(
      id: id,
      ticketNumber: ticketNumber,
      customerName: customerName,
      contactNumber: (json['contactNumber'] ??
              json['ContactNumber'] ??
              json['mobileNumber'] ??
              json['MobileNumber'] ??
              json['contact_number'] ??
              json['mobile_number'])
          ?.toString(),
      address: address,
      barangay: (json['barangay'] ?? json['Barangay'])?.toString(),
      city: (json['city'] ?? json['City'])?.toString(),
      planName: json['plan']?.toString() ??
          json['Plan']?.toString() ??
          json['desiredPlan']?.toString() ??
          json['DesiredPlan']?.toString() ??
          (json['planId'] is String ? json['planId'] as String : null) ??
          json['choose_Plan']?.toString() ??
          '',
      planId: (json['planId'] ?? json['PlanId']) is int
          ? (json['planId'] ?? json['PlanId']) as int
          : int.tryParse((json['planId'] ?? json['PlanId'])?.toString() ?? '0'),
      subscriberEmail: cleanEmail,
      secondContactNumber: cleanSecond,
      // Preserved verbatim: the API's office-side vocabulary is 'Applied' /
      // 'Confirmed', and lowercasing it silently broke every status comparison.
      status: json['status']?.toString().trim() ?? 'pending',
*/
    final rawSecond = json['secondContactNumber']?.toString() ??
        json['SecondContactNumber']?.toString() ??
        json['second_contact_number']?.toString();
    final cleanSecond = _cleanValue(rawSecond);
    // Gene - Oct 13, 2026: Parsed username for dedicated RADIUS / Wi-Fi identity from API payload.
    final rawUsername = json['username']?.toString() ??
        json['Username']?.toString() ??
        json['user_name']?.toString();
    final cleanUsername = _cleanValue(rawUsername);
    // Gene - Oct 13, 2026: Parsed connectionType (Fiber, Local, Antenna) from payload.
    final rawConnType = json['connectionType']?.toString() ??
        json['ConnectionType']?.toString() ??
        json['connection_type']?.toString();
    final cleanConnType = _cleanValue(rawConnType);
    // Gene - Oct 13, 2026: Parsed visitBy and visitWith from payload.
    final rawVisitBy = json['visitBy']?.toString() ??
        json['VisitBy']?.toString() ??
        json['visit_by']?.toString();
    final cleanVisitBy = _cleanValue(rawVisitBy);
    final rawVisitWith = json['visitWith']?.toString() ??
        json['VisitWith']?.toString() ??
        json['visit_with']?.toString();
    final cleanVisitWith = _cleanValue(rawVisitWith);
    // Gene - Oct 13, 2026: Parsed addressCoordinates / coordinates from API payload.
    final rawCoords = json['addressCoordinates'] ??
        json['AddressCoordinates'] ??
        json['address_coordinates'] ??
        json['coordinates'] ??
        json['Coordinates'];
    final cleanCoords = _cleanValue(rawCoords?.toString());

    return JobOrderDto(
      id: id,
      ticketNumber: ticketNumber,
      customerName: customerName,
      contactNumber: (json['contactNumber'] ??
              json['ContactNumber'] ??
              json['mobileNumber'] ??
              json['MobileNumber'] ??
              json['contact_number'] ??
              json['mobile_number'])
          ?.toString(),
      address: address,
      barangay: (json['barangay'] ?? json['Barangay'])?.toString(),
      city: (json['city'] ?? json['City'])?.toString(),
      planName: json['plan']?.toString() ??
          json['Plan']?.toString() ??
          json['desiredPlan']?.toString() ??
          json['DesiredPlan']?.toString() ??
          (json['planId'] is String ? json['planId'] as String : null) ??
          json['choose_Plan']?.toString() ??
          '',
      planId: (json['planId'] ?? json['PlanId']) is int
          ? (json['planId'] ?? json['PlanId']) as int
          : int.tryParse((json['planId'] ?? json['PlanId'])?.toString() ?? '0'),
      subscriberEmail: cleanEmail,
      secondContactNumber: cleanSecond,
      username: cleanUsername,
      // Gene - Oct 13, 2026: Passed connectionType parameter to fromJson.
      connectionType: cleanConnType,
      // Gene - Oct 13, 2026: Passed visitBy and visitWith parameters to fromJson.
      visitBy: cleanVisitBy,
      visitWith: cleanVisitWith,
      // Gene - Oct 13, 2026: Passed addressCoordinates parameter to fromJson.
      addressCoordinates: cleanCoords,
      // Gene - Nov, 27, 2026: Populate Server v11 column backing fields from API JSON.
      installationLandmark: _cleanValue(
          (json['installationLandmark'] ?? json['installation_landmark'])
              ?.toString()),
      remarks: _cleanValue((json['remarks'] ?? json['Remarks'])?.toString()),
      joRemarks:
          _cleanValue((json['joRemarks'] ?? json['jo_remarks'])?.toString()),
      applicationId: _cleanValue((json['applicationId'] ??
              json['applicationIdValue'] ??
              json['application_id'])
          ?.toString()),
      visitWithOther: _cleanValue(
          (json['visitWithOther'] ?? json['visit_with_other'])?.toString()),
      duration: _cleanValue((json['duration'] ?? json['Duration'])?.toString()),
      // Preserved verbatim: the API's office-side vocabulary is 'Applied' /
      // 'Confirmed', and lowercasing it silently broke every status comparison.
      status: json['status']?.toString().trim() ?? 'pending',
      onsiteStatus: (json['onsiteStatus'] ?? json['OnsiteStatus'])?.toString(),
      rawJson: jsonEncode(json),
      onsiteRemarks: json['onsiteRemarks']?.toString(),
      statusRemarks: json['statusRemarks']?.toString(),
      opticalPower: json['opticalPower'] is num
          ? (json['opticalPower'] as num).toDouble()
          : double.tryParse(json['opticalPower']?.toString() ?? ''),
      modemRouterSN: json['modemRouterSN']?.toString() ??
          json['routerModemSn']?.toString(),
      routerModel: json['routerModel']?.toString(),
      lcpId: json['lcpId'] is int
          ? json['lcpId']
          : int.tryParse(json['lcpId']?.toString() ?? ''),
      napId: json['napId'] is int
          ? json['napId']
          : int.tryParse(json['napId']?.toString() ?? ''),
      nap: json['nap']?.toString() ??
          (json['napId'] is String ? json['napId'] as String : null),
      portId: json['portId']?.toString() ?? json['port']?.toString(),
      vlanId: json['vlanId'] is int
          ? json['vlanId']
          : int.tryParse(json['vlanId']?.toString() ?? ''),
      dateInstalled: json['dateInstalled'] != null
          ? DateTime.tryParse(json['dateInstalled'].toString())
          : null,
      boxReadingImage: json['boxReadingImage']?.toString(),
      routerReadingImage: json['routerReadingImage']?.toString(),
      clientSignature: json['clientSignature']?.toString(),
      setupImage: json['setupImage']?.toString(),
      speedtestImage: json['speedtestImage']?.toString(),
      portLabelImage: json['portLabelImage']?.toString(),
      signedContractImage: json['signedContractImage']?.toString(),
      houseFront: json['houseFront']?.toString(),
      materialsUsed: () {
        final materials = <String, int>{};
        if (json['materialsUsed'] is Map) {
          (json['materialsUsed'] as Map).forEach((k, v) {
            final qty = int.tryParse(v.toString()) ?? 0;
            if (qty > 0) materials[k.toString()] = qty;
          });
        }
        for (var i = 1; i <= 10; i++) {
          final name = json['itemName$i']?.toString().trim();
          final qtyRaw = json['itemQuantity$i'];
          if (name != null && name.isNotEmpty) {
            final qty = qtyRaw is int
                ? qtyRaw
                : int.tryParse(qtyRaw?.toString() ?? '0') ?? 0;
            if (qty > 0) materials[name] = qty;
          }
        }
        return materials;
      }(),
      assignedEmail: json['assignedEmail']?.toString(),
      modifiedDate: json['modifiedDate'] != null
          ? DateTime.tryParse(json['modifiedDate'].toString())
          : null,
      // Gene - Nov, 25, 2026: Hydrate Start/Finish timestamps from API JSON, filtering sentinel default dates.
      startTimeStamp: parseTimingTimestamp(
          json['startTimeStamp'] ?? json['startTimestamp']),
      endTimeStamp: parseTimingTimestamp(json['endTimeStamp'] ??
          json['endTimestamp'] ??
          json['stopTimestamp']),
      isSynced: true,
      updatedAt: DateTime.now(),
    );
  }

  /// Rebuilds a job from a `job_orders` row. Locally saved photo paths are
  /// resolved back to data URLs so the rest of the app never sees a path.
  factory JobOrderDto.fromRow(Map<String, Object?> row) {
    final rawJson = rowText(row['raw_json']);
    final materials = <String, int>{};
    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic>) {
          if (decoded['materialsUsed'] is Map) {
            (decoded['materialsUsed'] as Map).forEach((k, v) {
              final qty = int.tryParse(v.toString()) ?? 0;
              if (qty > 0) materials[k.toString()] = qty;
            });
          }
          for (var i = 1; i <= 10; i++) {
            final name = decoded['itemName$i']?.toString().trim();
            final qtyRaw = decoded['itemQuantity$i'];
            if (name != null && name.isNotEmpty) {
              final qty = qtyRaw is int
                  ? qtyRaw
                  : int.tryParse(qtyRaw?.toString() ?? '0') ?? 0;
              if (qty > 0) materials[name] = qty;
            }
          }
        }
      } catch (_) {}
    }

    // Gene - Nov, 27, 2026: Hydrate materials from row columns (item_name1..10 / item_name_1..10) when raw_json is absent (PowerSync replicated rows).
    if (materials.isEmpty) {
      for (var i = 1; i <= 10; i++) {
        final name =
            (rowText(row['item_name$i']) ?? rowText(row['item_name_$i']))
                ?.trim();
        final qtyRaw = row['item_quantity$i'] ?? row['item_quantity_$i'];
        if (name != null && name.isNotEmpty) {
          final qty = qtyRaw is int
              ? qtyRaw
              : int.tryParse(qtyRaw?.toString() ?? '0') ?? 0;
          if (qty > 0) materials[name] = qty;
        }
      }
    }

    final photos = PhotoStorageService.instance;
    String? photo(String column) => photos.resolveToDataUrlSync(
          rowText(row[column]),
        );

    // Gene - Oct 13, 2026: Extract connectionType from rawJson for JobOrderDto.fromRow.
    // Gene - Nov, 27, 2026: Prefer direct Server v11 columns before falling back to rawJson.
    final String? rowConnectionType = () {
      final direct = rowText(row['connection_type'])?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      if (rawJson != null && rawJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map<String, dynamic>) {
            final val = decoded['connectionType'] ??
                decoded['ConnectionType'] ??
                decoded['connection_type'];
            if (val != null && val.toString().trim().isNotEmpty) {
              return val.toString().trim();
            }
          }
        } catch (_) {}
      }
      return null;
    }();

    // Gene - Oct 13, 2026: Extract visitBy and visitWith from rawJson for JobOrderDto.fromRow.
    final String? rowVisitBy = () {
      final direct = rowText(row['visit_by'])?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      if (rawJson != null && rawJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map<String, dynamic>) {
            final val =
                decoded['visitBy'] ?? decoded['VisitBy'] ?? decoded['visit_by'];
            if (val != null && val.toString().trim().isNotEmpty) {
              return val.toString().trim();
            }
          }
        } catch (_) {}
      }
      return null;
    }();

    final String? rowVisitWith = () {
      final direct = rowText(row['visit_with'])?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      if (rawJson != null && rawJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson);
          if (decoded is Map<String, dynamic>) {
            final val = decoded['visitWith'] ??
                decoded['VisitWith'] ??
                decoded['visit_with'];
            if (val != null && val.toString().trim().isNotEmpty) {
              return val.toString().trim();
            }
          }
        } catch (_) {}
      }
      return null;
    }();

    return JobOrderDto(
      id: rowInt(row['id']),
      ticketNumber: rowText(row['ticket_number']) ?? '',
      customerName: rowText(row['customer_name']) ?? '',
      contactNumber: rowText(row['contact_number']),
      address: rowText(row['address']) ?? '',
      barangay: rowText(row['barangay']),
      city: rowText(row['city']),
      planName: rowText(row['plan_name']),
      planId: rowIntOrNull(row['plan_id']),
/*
      subscriberEmail: rowText(row['subscriber_email']),
      secondContactNumber: rowText(row['second_contact_number']),
      status: rowText(row['status']) ?? 'pending',
*/
      subscriberEmail:
          rowText(row['subscriber_email']) ?? rowText(row['applicant_email']),
      secondContactNumber: rowText(row['second_contact_number']),
      // Gene - Oct 13, 2026: Passed row username for subscriber PPPoE / RADIUS account.
      username: rowText(row['username']),
      // Gene - Oct 13, 2026: Passed connectionType, visitBy, and visitWith extracted from rawJson.
      connectionType: rowConnectionType,
      visitBy: rowVisitBy,
      visitWith: rowVisitWith,
      // Gene - Oct 13, 2026: Passed addressCoordinates parsed from table row.
      addressCoordinates:
          rowText(row['address_coordinates']) ?? rowText(row['coordinates']),
      installationLandmark: rowText(row['installation_landmark']),
      remarks: rowText(row['remarks']),
      joRemarks: rowText(row['jo_remarks']),
      applicationId: rowText(row['application_id']),
      visitWithOther: rowText(row['visit_with_other']),
      duration: rowText(row['duration']),
      status: rowText(row['status']) ?? 'pending',
      onsiteStatus: rowText(row['onsite_status']),
      rawJson: rawJson,
      onsiteRemarks: rowText(row['onsite_remarks']),
      statusRemarks: rowText(row['status_remarks']),
      opticalPower: rowDouble(row['optical_power']),
      modemRouterSN: rowText(row['modem_router_sn']),
      routerModel: rowText(row['router_model']),
      lcpId: rowIntOrNull(row['lcp_id']),
      napId: rowIntOrNull(row['nap_id']),
      nap: rowText(row['nap']),
      portId: rowText(row['port_id']),
      vlanId: rowIntOrNull(row['vlan_id']),
      dateInstalled: rowDate(row['date_installed']),
      boxReadingImage: photo('box_reading_image'),
      routerReadingImage: photo('router_reading_image'),
      clientSignature: photo('client_signature'),
      setupImage: photo('setup_image'),
      speedtestImage: photo('speedtest_image'),
      portLabelImage: photo('port_label_image'),
      signedContractImage: photo('signed_contract_image'),
      houseFront: photo('house_front'),
      materialsUsed: materials,
      assignedEmail: rowText(row['assigned_email']),
      modifiedDate: rowDate(row['modified_date']),
      // Gene - Nov, 25, 2026: Hydrate Start/Finish timestamps from SQLite columns.
      startTimeStamp: normalizeTimingTimestamp(rowDate(row['start_timestamp'])),
      endTimeStamp: normalizeTimingTimestamp(rowDate(row['end_timestamp'])),
      isSynced: rowBool(row['is_synced'], fallback: true),
      updatedAt: rowDate(row['updated_at']),
    );
  }

  /// The `job_orders` row for this job. Materials are folded into `raw_json`
  /// so they survive a round trip and reach the PUT body.
/*
  Map<String, Object?> toRow({bool synced = true}) {
    String? rawJsonWithMaterials = rawJson;
    if (materialsUsed.isNotEmpty) {
      Map<String, dynamic> rawMap = {};
      if (rawJson != null && rawJson!.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson!);
          if (decoded is Map<String, dynamic>) rawMap = decoded;
        } catch (_) {}
      }
      rawMap['materialsUsed'] = materialsUsed;
      int idx = 1;
      materialsUsed.forEach((name, qty) {
        if (idx <= 10) {
          rawMap['itemName$idx'] = name;
          rawMap['itemQuantity$idx'] = qty;
          idx++;
        }
      });
      for (int i = idx; i <= 10; i++) {
        rawMap['itemName$i'] = '';
        rawMap['itemQuantity$i'] = '';
      }
      rawJsonWithMaterials = jsonEncode(rawMap);
    }
*/
/*
  // Gene - Oct 13, 2026: Included connectionType in raw_json inside toRow so connection type persists in local database.
  Map<String, Object?> toRow({bool synced = true}) {
    String? rawJsonWithMaterials = rawJson;
    if (materialsUsed.isNotEmpty || _connectionType != null) {
      Map<String, dynamic> rawMap = {};
      if (rawJson != null && rawJson!.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson!);
          if (decoded is Map<String, dynamic>) rawMap = decoded;
        } catch (_) {}
      }
      if (_connectionType != null) {
        rawMap['connectionType'] = _connectionType;
        rawMap['connection_type'] = _connectionType;
      }
      if (materialsUsed.isNotEmpty) {
        rawMap['materialsUsed'] = materialsUsed;
        int idx = 1;
        materialsUsed.forEach((name, qty) {
          if (idx <= 10) {
            rawMap['itemName$idx'] = name;
            rawMap['itemQuantity$idx'] = qty;
            idx++;
          }
        });
        for (int i = idx; i <= 10; i++) {
          rawMap['itemName$i'] = '';
          rawMap['itemQuantity$i'] = '';
        }
      }
      rawJsonWithMaterials = jsonEncode(rawMap);
    }
*/
  // Gene - Oct 13, 2026: Included connectionType, visitBy, and visitWith in raw_json inside toRow.
  Map<String, Object?> toRow({bool synced = true}) {
    String? rawJsonWithMaterials = rawJson;
    if (materialsUsed.isNotEmpty ||
        _connectionType != null ||
        _visitBy != null ||
        _visitWith != null) {
      Map<String, dynamic> rawMap = {};
      if (rawJson != null && rawJson!.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson!);
          if (decoded is Map<String, dynamic>) rawMap = decoded;
        } catch (_) {}
      }
      if (_connectionType != null) {
        rawMap['connectionType'] = _connectionType;
        rawMap['connection_type'] = _connectionType;
      }
      if (_visitBy != null) {
        rawMap['visitBy'] = _visitBy;
        rawMap['visit_by'] = _visitBy;
      }
      if (_visitWith != null) {
        rawMap['visitWith'] = _visitWith;
        rawMap['visit_with'] = _visitWith;
      }
      if (materialsUsed.isNotEmpty) {
        rawMap['materialsUsed'] = materialsUsed;
        int idx = 1;
        materialsUsed.forEach((name, qty) {
          if (idx <= 10) {
            rawMap['itemName$idx'] = name;
            rawMap['itemQuantity$idx'] = qty;
            idx++;
          }
        });
        for (int i = idx; i <= 10; i++) {
          rawMap['itemName$i'] = '';
          rawMap['itemQuantity$i'] = '';
        }
      }
      rawJsonWithMaterials = jsonEncode(rawMap);
    }

    // Gene - Nov, 27, 2026: Include Server v11 columns and item_name1..10 / item_quantity1..10 in toRow().
    final materialRow = <String, Object?>{};
    if (materialsUsed.isNotEmpty) {
      int idx = 1;
      materialsUsed.forEach((name, qty) {
        if (idx <= 10) {
          materialRow['item_name$idx'] = name;
          materialRow['item_quantity$idx'] = qty.toString();
          idx++;
        }
      });
      for (int i = idx; i <= 10; i++) {
        materialRow['item_name$i'] = '';
        materialRow['item_quantity$i'] = '';
      }
    } else {
      for (int i = 1; i <= 10; i++) {
        materialRow['item_name$i'] = synced ? null : '';
        materialRow['item_quantity$i'] = synced ? null : '';
      }
    }

    return {
      'id': idText(id),
      'ticket_number': ticketNumber,
      'customer_name': customerName,
      'contact_number': contactNumber,
      'address': address,
      'barangay': barangay,
      'city': city,
      'plan_name': planName,
      'plan_id': planId,
      'subscriber_email': subscriberEmail,
      'applicant_email': subscriberEmail,
      'second_contact_number': secondContactNumber,
      'username': username,
      'connection_type': _connectionType ?? _rawText('connectionType'),
      'visit_by': _visitBy ?? _rawText('visitBy'),
      'visit_with': _visitWith ?? _rawText('visitWith'),
      'visit_with_other': visitWithOther,
      'address_coordinates': _addressCoordinates ??
          _rawText('addressCoordinates') ??
          _rawText('coordinates'),
      'installation_landmark':
          _installationLandmark ?? _rawText('installationLandmark'),
      'remarks': _remarks ?? _rawText('remarks'),
      'jo_remarks': _joRemarks ?? _rawText('joRemarks'),
      'application_id': applicationId,
      'duration': _duration ??
          ((startTimeStamp != null &&
                  endTimeStamp != null &&
                  endTimeStamp!.isAfter(startTimeStamp!))
              ? formatTimingDurationMinutes(startTimeStamp!, endTimeStamp!)
              : _rawText('duration')),
      ...materialRow,
      'status': status,
      'onsite_status': onsiteStatus,
      'onsite_remarks': onsiteRemarks,
      'status_remarks': statusRemarks,
      'optical_power': opticalPower,
      'modem_router_sn': modemRouterSN,
      'router_model': routerModel,
      'lcp_id': lcpId,
      'nap_id': napId,
      'nap': nap,
      'port_id': portId,
      'vlan_id': vlanId,
      'date_installed': dateText(dateInstalled),
      'box_reading_image': boxReadingImage,
      'router_reading_image': routerReadingImage,
      'client_signature': clientSignature,
      'setup_image': setupImage,
      'speedtest_image': speedtestImage,
      'port_label_image': portLabelImage,
      'signed_contract_image': signedContractImage,
      'house_front': houseFront,
      'assigned_email': assignedEmail,
      // Gene - Nov, 25, 2026: Persist Start/Finish timestamps to job_orders SQLite columns.
      'start_timestamp': dateText(startTimeStamp),
      'end_timestamp': dateText(endTimeStamp),
      'modified_date': dateText(modifiedDate),
      'raw_json': rawJsonWithMaterials,
      'is_synced': boolInt(synced),
      'updated_at': dateText(updatedAt ?? DateTime.now()),
    };
  }

  /// Merges a fresh server record into this local record, ensuring that
  /// non-empty local fields (customer name, address, photos, materials, plan)
  /// are not overwritten by empty strings or placeholder defaults from the server.
  JobOrderDto mergeWithServer(JobOrderDto server,
      {Map<String, dynamic>? freshJson}) {
    // 1. Customer Name
    final hasValidServerName = server.customerName.trim().isNotEmpty &&
        !server.customerName.startsWith('Subscriber #') &&
        server.customerName != 'N/A';
    final mergedCustomerName = hasValidServerName
        ? server.customerName
        : (customerName.trim().isNotEmpty &&
                !customerName.startsWith('Subscriber #')
            ? customerName
            : server.customerName);

    // 2. Address
    final hasValidServerAddress =
        server.address.trim().isNotEmpty && server.address != 'N/A';
    final mergedAddress = hasValidServerAddress
        ? server.address
        : (address.trim().isNotEmpty && address != 'N/A'
            ? address
            : server.address);

    // 3. Contact Numbers
    final mergedContactNumber = (server.contactNumber != null &&
            server.contactNumber!.trim().isNotEmpty)
        ? server.contactNumber
        : contactNumber;

    final mergedSecondContact = (server.secondContactNumber != null &&
            server.secondContactNumber!.trim().isNotEmpty)
        ? server.secondContactNumber
        : secondContactNumber;

    // 4. Subscriber Email
    final mergedEmail = (server.subscriberEmail != null &&
            server.subscriberEmail!.trim().isNotEmpty)
        ? server.subscriberEmail
        : subscriberEmail;

    // 5. Plan Name & Plan ID
    final mergedPlanName =
        (server.planName != null && server.planName!.trim().isNotEmpty)
            ? server.planName
            : planName;
    final mergedPlanId = server.planId ?? planId;

    // 6. Barangay & City
    final mergedBarangay =
        (server.barangay != null && server.barangay!.trim().isNotEmpty)
            ? server.barangay
            : barangay;
    final mergedCity = (server.city != null && server.city!.trim().isNotEmpty)
        ? server.city
        : city;

    // 7. Ticket Number
    final hasValidServerTicket = server.ticketNumber.trim().isNotEmpty &&
        !server.ticketNumber.startsWith('JO-');
    final mergedTicketNumber = hasValidServerTicket
        ? server.ticketNumber
        : (ticketNumber.trim().isNotEmpty && !ticketNumber.startsWith('JO-')
            ? ticketNumber
            : server.ticketNumber);

    // 8. Photos & Signature: keep local photos if server returns null/empty or placeholder
    String? mergePhoto(String? localPhoto, String? serverPhoto) {
      if (localPhoto == null || localPhoto.trim().isEmpty) return serverPhoto;
      if (serverPhoto == null ||
          serverPhoto.trim().isEmpty ||
          serverPhoto.contains('picsum.photos')) {
        return localPhoto;
      }
      return serverPhoto;
    }

    // 9. Materials Used
    final mergedMaterials =
        server.materialsUsed.isNotEmpty ? server.materialsUsed : materialsUsed;

    // 10. Raw JSON
    String? mergedRawJson = server.rawJson;
    if (freshJson != null || rawJson != null) {
      Map<String, dynamic> rawMap = {};
      if (rawJson != null && rawJson!.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawJson!);
          if (decoded is Map<String, dynamic>) rawMap.addAll(decoded);
        } catch (_) {}
      }
      if (freshJson != null) {
        rawMap.addAll(freshJson);
      }
      if (mergedMaterials.isNotEmpty) {
        rawMap['materialsUsed'] = mergedMaterials;
      }
      mergedRawJson = jsonEncode(rawMap);
    }

    return JobOrderDto(
      id: id,
      ticketNumber: mergedTicketNumber,
      customerName: mergedCustomerName,
      contactNumber: mergedContactNumber,
      address: mergedAddress,
      barangay: mergedBarangay,
      city: mergedCity,
      planName: mergedPlanName,
      planId: mergedPlanId,
/*
      subscriberEmail: mergedEmail,
      secondContactNumber: mergedSecondContact,
      status: server.status,
*/
      subscriberEmail: mergedEmail,
      secondContactNumber: mergedSecondContact,
      // Gene - Oct 13, 2026: Merged subscriber username preserving server or existing value.
      username: (server.username != null && server.username!.trim().isNotEmpty)
          ? server.username
          : username,
      // Gene - Oct 13, 2026: Merged connection type, visitBy, and visitWith preserving server or existing value.
      connectionType: (server._connectionType != null &&
              server._connectionType.trim().isNotEmpty)
          ? server._connectionType
          : _connectionType,
      visitBy: (server._visitBy != null && server._visitBy.trim().isNotEmpty)
          ? server._visitBy
          : _visitBy,
      visitWith:
          (server._visitWith != null && server._visitWith.trim().isNotEmpty)
              ? server._visitWith
              : _visitWith,
      addressCoordinates: (server._addressCoordinates != null &&
              server._addressCoordinates.trim().isNotEmpty)
          ? server._addressCoordinates
          : _addressCoordinates,
      installationLandmark: (server._installationLandmark != null &&
              server._installationLandmark.trim().isNotEmpty)
          ? server._installationLandmark
          : _installationLandmark,
      remarks: (server._remarks != null && server._remarks.trim().isNotEmpty)
          ? server._remarks
          : _remarks,
      joRemarks:
          (server._joRemarks != null && server._joRemarks.trim().isNotEmpty)
              ? server._joRemarks
              : _joRemarks,
      applicationId: (server._applicationId != null &&
              server._applicationId.trim().isNotEmpty)
          ? server._applicationId
          : _applicationId,
      visitWithOther: (server._visitWithOther != null &&
              server._visitWithOther.trim().isNotEmpty)
          ? server._visitWithOther
          : _visitWithOther,
      duration: (server._duration != null && server._duration.trim().isNotEmpty)
          ? server._duration
          : _duration,
      status: server.status,
      onsiteStatus: (server.onsiteStatus != null &&
              server.onsiteStatus!.trim().isNotEmpty)
          ? server.onsiteStatus
          : onsiteStatus,
      rawJson: mergedRawJson,
      onsiteRemarks: (server.onsiteRemarks != null &&
              server.onsiteRemarks!.trim().isNotEmpty)
          ? server.onsiteRemarks
          : onsiteRemarks,
      statusRemarks: (server.statusRemarks != null &&
              server.statusRemarks!.trim().isNotEmpty)
          ? server.statusRemarks
          : (server.status == status ? statusRemarks : server.statusRemarks),
      opticalPower: server.opticalPower ?? opticalPower,
      modemRouterSN: (server.modemRouterSN != null &&
              server.modemRouterSN!.trim().isNotEmpty)
          ? server.modemRouterSN
          : modemRouterSN,
      routerModel:
          (server.routerModel != null && server.routerModel!.trim().isNotEmpty)
              ? server.routerModel
              : routerModel,
      lcpId: server.lcpId ?? lcpId,
      napId: server.napId ?? napId,
      nap: (server.nap != null && server.nap!.trim().isNotEmpty)
          ? server.nap
          : nap,
      portId: (server.portId != null && server.portId!.trim().isNotEmpty)
          ? server.portId
          : portId,
      vlanId: server.vlanId ?? vlanId,
      dateInstalled: server.dateInstalled ?? dateInstalled,
      boxReadingImage: mergePhoto(boxReadingImage, server.boxReadingImage),
      routerReadingImage:
          mergePhoto(routerReadingImage, server.routerReadingImage),
      clientSignature: mergePhoto(clientSignature, server.clientSignature),
      setupImage: mergePhoto(setupImage, server.setupImage),
      speedtestImage: mergePhoto(speedtestImage, server.speedtestImage),
      portLabelImage: mergePhoto(portLabelImage, server.portLabelImage),
      signedContractImage:
          mergePhoto(signedContractImage, server.signedContractImage),
      houseFront: mergePhoto(houseFront, server.houseFront),
      materialsUsed: mergedMaterials,
      assignedEmail: (server.assignedEmail != null &&
              server.assignedEmail!.trim().isNotEmpty)
          ? server.assignedEmail
          : assignedEmail,
      modifiedDate: server.modifiedDate ?? modifiedDate,
      // Gene - Nov, 25, 2026: Preserve non-sentinel Start/Finish timestamps when merging server rows.
      /*
      startTimeStamp: normalizeTimingTimestamp(server.startTimeStamp) ??
          normalizeTimingTimestamp(startTimeStamp),
      endTimeStamp: () {
        final sStart = normalizeTimingTimestamp(server.startTimeStamp) ??
            normalizeTimingTimestamp(startTimeStamp);
        final sEnd = normalizeTimingTimestamp(server.endTimeStamp);
        final lEnd = normalizeTimingTimestamp(endTimeStamp);
        if (sStart != null && sEnd != null && sEnd.isAfter(sStart)) {
          return sEnd;
        }
        if (sStart != null && lEnd != null && lEnd.isAfter(sStart)) {
          return lEnd;
        }
        return sEnd ?? lEnd;
      }(),
      */
      // Gene - Nov, 26, 2026: Use mergeWorkTimingTimestamps so a locally restarted session is never overwritten by an older server session.
      startTimeStamp: mergeWorkTimingTimestamps(
        serverStart: server.startTimeStamp,
        serverEnd: server.endTimeStamp,
        localStart: startTimeStamp,
        localEnd: endTimeStamp,
      ).$1,
      endTimeStamp: mergeWorkTimingTimestamps(
        serverStart: server.startTimeStamp,
        serverEnd: server.endTimeStamp,
        localStart: startTimeStamp,
        localEnd: endTimeStamp,
      ).$2,
      isSynced: true,
      updatedAt: DateTime.now(),
    );
  }

  /// Every field of `UpdateJobOrderRequest`, exactly as the owner's working
  /// curl sends it. The PUT body is built from this list and nothing else.
  ///
  /// The GET returns 99 keys, a dozen of which (`id`, `timestamp`, `nap`,
  /// `lcp`, `vlan`, `choose_Plan`, …) are read-side echoes the request type
  /// does not declare. Replaying them was one more way for the update to
  /// fail without saying which field it disliked.
  static const List<String> apiRequestFields = [
    'emailAddress',
    'referredBy',
    'firstName',
    'middleInitial',
    'lastName',
    'contactNumber',
    'applicantEmailAddress',
    'address',
    'location',
    'barangay',
    'city',
    'region',
    'planId',
    'remarks',
    'installationFee',
    'contractTemplate',
    'billingDay',
    'preferredDay',
    'joRemarks',
    'status',
    'verifiedBy',
    'modemRouterSN',
    'provider',
    'lcpId',
    'napId',
    'portId',
    'vlanId',
    'username',
    'visitBy',
    'visitWith',
    'visitWithOther',
    'onsiteStatus',
    'onsiteRemarks',
    'modifiedBy',
    'modifiedDate',
    'contractLink',
    'connectionType',
    'assignedEmail',
    'setupImage',
    'speedtestImage',
    'startTimeStamp',
    'endTimeStamp',
    'duration',
    'externalId',
    'lcpnapId',
    'billingStatus',
    'routerModel',
    'dateInstalled',
    'clientSignature',
    'ip',
    'signedContractImage',
    'boxReadingImage',
    'routerReadingImage',
    'usernameStatus',
    'lcpnapportId',
    'itemName1',
    'itemQuantity1',
    'itemName2',
    'itemQuantity2',
    'itemName3',
    'itemQuantity3',
    'itemName4',
    'itemQuantity4',
    'itemName5',
    'itemQuantity5',
    'itemName6',
    'itemQuantity6',
    'itemName7',
    'itemQuantity7',
    'itemName8',
    'itemQuantity8',
    'itemName9',
    'itemQuantity9',
    'itemName10',
    'itemQuantity10',
    'usageType',
    'renter',
    'installationLandmark',
    'statusRemarks',
    'portLabelImage',
    'secondContactNumber',
    'accountNo',
    'addressCoordinates',
    'referrersAccountNumber',
    'applicationId',
    'houseFront',
    'createdBy',
    'createdDate',
  ];

  /// Fields `PUT /api/JobOrders/{id}` accepts as null.
  ///
  /// Everything else in UpdateJobOrderRequest is a non-nullable string, so a
  /// null fails validation where an empty string passes.
  static const Set<String> _nullableApiFields = {
    'modifiedDate',
    'startTimeStamp',
    'endTimeStamp',
    'dateInstalled',
    'createdBy',
    'createdDate',
  };

  /// Fields the PUT requires that the matching GET does not always return.
  ///
  /// The endpoint is not a clean round trip: `GET /api/JobOrders/{id}` hands
  /// back `duration`, `billingDay` and `installationFee` as null and omits
  /// `applicationId` entirely, then the PUT rejects the very record it just
  /// gave out with "The Duration field is required". Replaying the server's
  /// own response therefore fails with HTTP 400 unless these are filled in.
  /// These four hold numbers, so an empty string is not a safe filler: the
  /// endpoint accepted `""` past validation and then failed inside the update
  /// with `HTTP 500 An error occurred while updating job order with ID`,
  /// which is what a numeric parse of an empty string looks like from the
  /// outside. Each is given a numeric default instead.
  ///
  /// `duration` is null on every record on the server, so there is no
  /// populated example to copy a format from; zero is the neutral choice.
  /// `applicationId` is handled separately: it is the application's own
  /// number, which the record already carries as `accountNo`.
  static const Map<String, String> _requiredApiFields = {
    'duration': defaultDuration,
    'billingDay': defaultBillingDay,
    'installationFee': defaultInstallationFee,
  };

  /// Default duration set on job completion.
  static const String defaultDuration = '2';

  /// Billing day used when the record carries none.
  ///
  /// A subscriber that already has a billing day keeps it: overwriting one
  /// would change real billing data to satisfy a validator.
  static const String defaultBillingDay = '27';

  /// Installation fee used when the record carries none.
  ///
  /// A record that already has a fee keeps it, **including an explicit 0**.
  /// Most job orders on the server currently read 0, and a zero fee is a real
  /// value the office may have set on purpose; only a null or empty fee is
  /// treated as missing.
  static const String defaultInstallationFee = '1';

  /// Makes [body] satisfy UpdateJobOrderRequest without changing any value
  /// the server actually holds.
  ///
  /// Produces exactly the contract's fields, every value a string, in the
  /// shape the owner's own curl uses:
  ///
  /// - keys outside [apiRequestFields] are dropped;
  /// - the four numeric required fields get a numeric default when the record
  ///   has none, whether they arrived null or were missing entirely;
  /// - the six genuinely nullable fields stay null;
  /// - every other null becomes `""`, and every number (`0.0`, `22`) becomes
  ///   its string form, since the request type declares strings.
  static Map<String, dynamic> normalizeForApi(Map<String, dynamic> body) {
    final out = Map<String, dynamic>.from(body);

    for (final entry in _requiredApiFields.entries) {
      final current = out[entry.key];
      // Only a null or blank counts as missing. A value the office already
      // set is kept, including an explicit zero fee or a real billing day.
      if (current == null || current.toString().trim().isEmpty) {
        out[entry.key] = entry.value;
      }
    }

    // The GET never returns applicationId, but the PUT requires it.
    // Use the record's ID to satisfy the backend requirement.
    final applicationId = out['applicationId'];
    if (applicationId == null || applicationId.toString().trim().isEmpty) {
      final idVal = out['id']?.toString().trim() ?? '';
      out['applicationId'] = idVal.isNotEmpty
          ? idVal
          : (out['accountNo']?.toString().trim() ?? '0');
    }

    final result = <String, dynamic>{};
    for (final key in apiRequestFields) {
      final value = out[key];
      if (value == null) {
        result[key] = _nullableApiFields.contains(key) ? null : '';
      } else if (value is num) {
        // 22 -> "22", 0.0 -> "0", 799.5 -> "799.5".
        result[key] = value == value.truncateToDouble() && value.abs() < 1e15
            ? value.toInt().toString()
            : value.toString();
      } else {
        result[key] = value.toString();
      }
    }
    return result;
  }

  /// Fields the technician's app is allowed to change on the server.
  ///
  /// Everything else in the record is echoed back untouched.
  Map<String, dynamic> _technicianEdits() {
    final edits = <String, dynamic>{
      'status': status,
      'onsiteStatus': onsiteStatus ?? '',
      'onsiteRemarks': onsiteRemarks ?? '',
      // The reschedule reason. Left out when unknown so a cached row from
      // before this column existed never blanks what the office wrote.
      if (statusRemarks != null) 'statusRemarks': statusRemarks,
      'modemRouterSN': modemRouterSN ?? '',
      'routerModel': routerModel ?? '',
      // Gene - Oct 13, 2026: Include upgraded/changed planId in technician edits for server PUT sync.
      if (planId != null) 'planId': planId.toString(),
      if (nap != null) 'nap': nap,
      if (nap != null) 'napId': nap,
      'portId': portId ?? '',
      // Photos and the signature are sent only when the app holds a value
      // (an empty string clears one on purpose). A null means the column
      // was added after the row was cached, and the server's copy in
      // rawJson must win rather than be blanked.
      if (boxReadingImage != null) 'boxReadingImage': boxReadingImage,
      if (routerReadingImage != null) 'routerReadingImage': routerReadingImage,
      if (clientSignature != null) 'clientSignature': clientSignature,
      if (setupImage != null) 'setupImage': setupImage,
      if (speedtestImage != null) 'speedtestImage': speedtestImage,
      if (portLabelImage != null) 'portLabelImage': portLabelImage,
      if (signedContractImage != null)
        'signedContractImage': signedContractImage,
      if (houseFront != null) 'houseFront': houseFront,
      // Gene - Oct 13, 2026: Include connectionType, visitBy, and visitWith in technician edits for server PUT sync.
      if (connectionType.isNotEmpty) 'connectionType': connectionType,
      if (visitBy.isNotEmpty) 'visitBy': visitBy,
      if (visitWith.isNotEmpty) 'visitWith': visitWith,
      // Stamped on activation. Left out when unknown so a cached row from
      // before this column existed never blanks the office's assignment.
      if (assignedEmail != null) 'assignedEmail': assignedEmail,
      // Gene - Nov, 25, 2026: Include recorded Start/Finish timestamps in UpdateJobOrderRequest edits when present.
      if (startTimeStamp != null)
        'startTimeStamp': startTimeStamp!.toUtc().toIso8601String(),
      if (endTimeStamp != null)
        'endTimeStamp': endTimeStamp!.toUtc().toIso8601String(),
      // Gene - Nov, 26, 2026: Compute numeric whole-minute duration for UpdateJobOrderRequest when both Start and End timestamps are recorded.
      if (startTimeStamp != null &&
          endTimeStamp != null &&
          endTimeStamp!.isAfter(startTimeStamp!))
        'duration': formatTimingDurationMinutes(startTimeStamp!, endTimeStamp!),
    };

    if (materialsUsed.isNotEmpty) {
      int index = 1;
      materialsUsed.forEach((name, qty) {
        if (index <= 10) {
          edits['itemName$index'] = name;
          edits['itemQuantity$index'] = qty;
          index++;
        }
      });
      for (int i = index; i <= 10; i++) {
        edits['itemName$i'] = '';
        edits['itemQuantity$i'] = '';
      }
    }

    return edits;
  }

  /// Body for `PUT /api/JobOrders/{id}`.
  ///
  /// The endpoint's UpdateJobOrderRequest marks all 86 of its fields required,
  /// so a partial body is not an option: it would either fail validation or
  /// blank out every field the app does not model. The original record is
  /// therefore replayed in full with only the technician's edits applied on
  /// top.
  ///
  /// [rawJson] is absent only for locally seeded demo rows, which have no
  /// server record to preserve; those fall back to the modelled subset.
  Map<String, dynamic> toApiJson() {
    final original = rawJson;
    if (original == null || original.trim().isEmpty) {
      final fallback = <String, dynamic>{'id': id, ..._technicianEdits()};
      // Never send a null over a value the server may already hold.
      for (final e in <String, Object?>{
        'opticalPower': opticalPower,
        'lcpId': lcpId,
        'napId': napId,
        'vlanId': vlanId,
        'dateInstalled': dateInstalled?.toIso8601String(),
      }.entries) {
        if (e.value != null) fallback[e.key] = e.value;
      }
      _preserveVitalFields(fallback);
      return normalizeForApi(fallback);
    }

    final decoded = json.decode(original);
    if (decoded is! Map<String, dynamic>) {
      final fallback = <String, dynamic>{'id': id, ..._technicianEdits()};
      _preserveVitalFields(fallback);
      return normalizeForApi(fallback);
    }

    final payload = <String, dynamic>{
      'id': id,
      ...decoded,
      ..._technicianEdits(),
      if (dateInstalled != null)
        'dateInstalled': dateInstalled!.toIso8601String(),
      if (opticalPower != null) 'opticalPower': opticalPower,
    };
    _preserveVitalFields(payload);
    return normalizeForApi(payload);
  }

  /// Ensures vital identity fields (subscriber name, address, contact, plan,
  /// account number) are populated in the payload even if rawJson had different
  /// casing, alternative key names, or lacked split firstName/lastName fields.
  void _preserveVitalFields(Map<String, dynamic> payload) {
    // 1. First & Last Name
    final curFirst = payload['firstName']?.toString().trim() ?? '';
    final curLast = payload['lastName']?.toString().trim() ?? '';

    final altFirst = curFirst.isNotEmpty
        ? curFirst
        : (payload['FirstName'] ?? payload['first_name'])?.toString().trim() ??
            '';
    final altLast = curLast.isNotEmpty
        ? curLast
        : (payload['LastName'] ?? payload['last_name'])?.toString().trim() ??
            '';

    if (altFirst.isNotEmpty) payload['firstName'] = altFirst;
    if (altLast.isNotEmpty) payload['lastName'] = altLast;

    final firstEmpty = payload['firstName'] == null ||
        payload['firstName'].toString().trim().isEmpty;
    final lastEmpty = payload['lastName'] == null ||
        payload['lastName'].toString().trim().isEmpty;

    if (firstEmpty || lastEmpty) {
      final nameCandidates = [
        payload['fullName']?.toString(),
        payload['FullName']?.toString(),
        payload['customerName']?.toString(),
        payload['CustomerName']?.toString(),
        payload['name']?.toString(),
        payload['Name']?.toString(),
        customerName,
      ];
      String? bestName;
      for (final candidate in nameCandidates) {
        if (candidate != null &&
            candidate.trim().isNotEmpty &&
            !candidate.startsWith('Subscriber #') &&
            candidate != 'N/A') {
          bestName = candidate.trim();
          break;
        }
      }
      bestName ??= customerName.trim();

      if (bestName.isNotEmpty && !bestName.startsWith('Subscriber #')) {
        final parts = bestName.split(RegExp(r'\s+'));
        final derivedFirst = parts.length > 1
            ? parts.sublist(0, parts.length - 1).join(' ')
            : parts.first;
        final derivedLast = parts.length > 1 ? parts.last : parts.first;

        if (firstEmpty) {
          payload['firstName'] = derivedFirst;
        }
        if (lastEmpty) {
          payload['lastName'] = derivedLast;
        }
      }
    }

    // 2. Address
    if (payload['address'] == null ||
        payload['address'].toString().trim().isEmpty) {
      final addrCandidates = [
        payload['Address']?.toString(),
        payload['installationAddress']?.toString(),
        payload['InstallationAddress']?.toString(),
        payload['installation_address']?.toString(),
        address,
      ];
      for (final a in addrCandidates) {
        if (a != null && a.trim().isNotEmpty && a.trim() != 'N/A') {
          payload['address'] = a.trim();
          break;
        }
      }
    }

    // 3. Contact Number
    if (payload['contactNumber'] == null ||
        payload['contactNumber'].toString().trim().isEmpty) {
      final contactCandidates = [
        payload['ContactNumber']?.toString(),
        payload['mobileNumber']?.toString(),
        payload['MobileNumber']?.toString(),
        payload['contact_number']?.toString(),
        payload['mobile_number']?.toString(),
        contactNumber,
      ];
      for (final c in contactCandidates) {
        if (c != null && c.trim().isNotEmpty) {
          payload['contactNumber'] = c.trim();
          break;
        }
      }
    }

    // 4. Second Contact Number
    if (payload['secondContactNumber'] == null ||
        payload['secondContactNumber'].toString().trim().isEmpty) {
      final secCandidates = [
        payload['SecondContactNumber']?.toString(),
        payload['second_contact_number']?.toString(),
        secondContactNumber,
      ];
      for (final s in secCandidates) {
        if (s != null && s.trim().isNotEmpty) {
          payload['secondContactNumber'] = s.trim();
          break;
        }
      }
    }

    // 5. Applicant Email Address & Email Address
    if (payload['applicantEmailAddress'] == null ||
        payload['applicantEmailAddress'].toString().trim().isEmpty) {
      final emailCandidates = [
        payload['ApplicantEmailAddress']?.toString(),
        payload['emailAddress']?.toString(),
        payload['EmailAddress']?.toString(),
        payload['email']?.toString(),
        subscriberEmail,
      ];
      for (final e in emailCandidates) {
        if (e != null && e.trim().isNotEmpty) {
          payload['applicantEmailAddress'] = e.trim();
          break;
        }
      }
    }
    if (payload['emailAddress'] == null ||
        payload['emailAddress'].toString().trim().isEmpty) {
      final em =
          payload['applicantEmailAddress']?.toString() ?? subscriberEmail;
      if (em != null && em.trim().isNotEmpty) {
        payload['emailAddress'] = em.trim();
      }
    }

    // 6. Barangay
    if (payload['barangay'] == null ||
        payload['barangay'].toString().trim().isEmpty) {
      final bgy = payload['Barangay']?.toString() ?? barangay;
      if (bgy != null && bgy.trim().isNotEmpty) {
        payload['barangay'] = bgy.trim();
      }
    }

    // 7. City
    if (payload['city'] == null || payload['city'].toString().trim().isEmpty) {
      final c = payload['City']?.toString() ?? city;
      if (c != null && c.trim().isNotEmpty) {
        payload['city'] = c.trim();
      }
    }

    // 8. Plan ID
    if (payload['planId'] == null ||
        payload['planId'].toString().trim().isEmpty) {
      final p = payload['PlanId']?.toString() ?? planId?.toString() ?? planName;
      if (p != null && p.trim().isNotEmpty) {
        payload['planId'] = p.trim();
      }
    }

    // 9. Account No
    if (payload['accountNo'] == null ||
        payload['accountNo'].toString().trim().isEmpty) {
      final acc = payload['AccountNo']?.toString() ??
          payload['ticketNumber']?.toString() ??
          payload['TicketNumber']?.toString() ??
          ticketNumber;
      if (acc.trim().isNotEmpty) {
        payload['accountNo'] = acc.trim();
      }
    }

    // 10. Assigned Email
    if (payload['assignedEmail'] == null ||
        payload['assignedEmail'].toString().trim().isEmpty) {
      final ae = payload['AssignedEmail']?.toString() ?? assignedEmail;
      if (ae != null && ae.trim().isNotEmpty) {
        payload['assignedEmail'] = ae.trim();
      }
    }
  }

  /// Whether `PUT /api/JobOrders/{id}` can take an image inline.
  ///
  /// It cannot yet. Probed on 2026-09-05 against job order 3975:
  /// clientSignature, setupImage and houseFront accept 255 characters and
  /// answer HTTP 500 "An error occurred while updating job order" at 256, so
  /// any real image failed the whole completion. Until the backend takes
  /// uploads, each captured image is sent as the placeholder URL the owner
  /// asked for and the image itself stays on the phone. Flip this once the
  /// backend stores inline images.
  static const bool serverAcceptsInlineImages = false;

  /// Stand-ins sent while [serverAcceptsInlineImages] is false.
  static const String placeholderPhotoUrl = 'https://picsum.photos/200';
  static const String placeholderSignatureUrl =
      'https://picsum.photos/200/300?grayscale';

  /// The image fields of `UpdateJobOrderRequest`.
  static const List<String> imageFields = [
    'boxReadingImage',
    'routerReadingImage',
    'clientSignature',
    'setupImage',
    'speedtestImage',
    'portLabelImage',
    'signedContractImage',
    'houseFront',
  ];

  /// Converts fields to API JSON map. Captured photos and the signature go
  /// out as Base64 data URLs when [serverAcceptsInlineImages], otherwise as
  /// the placeholder URLs. A value the server itself holds (`image.jpeg`,
  /// `uploads/...`) or an empty field is echoed back unchanged.
  Future<Map<String, dynamic>> toApiJsonAsync() async {
    if (serverAcceptsInlineImages) return toApiJsonWithInlineImages();
    final map = toApiJson();
    final storage = PhotoStorageService.instance;
    for (final key in imageFields) {
      final value = map[key];
      if (value is! String || !storage.isCapturedImage(value)) continue;
      map[key] = key == 'clientSignature'
          ? placeholderSignatureUrl
          : placeholderPhotoUrl;
    }
    return map;
  }

  /// The old inline form, kept for the day the flag above flips.
  @visibleForTesting
  Future<Map<String, dynamic>> toApiJsonWithInlineImages() async {
    final map = toApiJson();
    final storage = PhotoStorageService.instance;
    const keys = [
      'boxReadingImage',
      'routerReadingImage',
      'clientSignature',
      'setupImage',
      'speedtestImage',
      'portLabelImage',
      'signedContractImage',
      'houseFront',
    ];
    for (final key in keys) {
      if (map.containsKey(key) && map[key] is String) {
        map[key] = await storage.resolveToDataUrl(map[key] as String);
      }
    }
    return map;
  }

  // Gene - Nov 5, 2026: Helper to detect if this job carries any locally captured photos or signatures that should be uploaded via multipart/form-data.
  bool get hasCapturedPhotos {
    final storage = PhotoStorageService.instance;
    return (setupImage != null && storage.isCapturedImage(setupImage!)) ||
        (routerReadingImage != null &&
            storage.isCapturedImage(routerReadingImage!)) ||
        (signedContractImage != null &&
            storage.isCapturedImage(signedContractImage!)) ||
        (boxReadingImage != null &&
            storage.isCapturedImage(boxReadingImage!)) ||
        (clientSignature != null &&
            storage.isCapturedImage(clientSignature!)) ||
        (houseFront != null && storage.isCapturedImage(houseFront!)) ||
        (portLabelImage != null && storage.isCapturedImage(portLabelImage!));
  }

  // Gene - Nov 5, 2026: Builds multipart FormData payload uploading real photo files and signature to PUT /api/JobOrders/{id}.
  Future<FormData> toMultipartFormData() async {
    final storage = PhotoStorageService.instance;
    final jsonMap = toApiJson();
    final formDataMap = <String, dynamic>{};

    // Mapping from DTO/API field keys to ASP.NET Core multipart parameter names
    const fileParamMap = {
      'setupImage': 'SetupImage',
      'routerReadingImage': 'RouterReadingImage',
      'signedContractImage': 'SignedContractImage',
      'clientSignature': 'ClientSignature',
      'houseFront': 'HouseFront',
      'boxReadingImage': 'BoxReadingImage',
      'portLabelImage': 'PortLabelImage',
    };

    for (final entry in jsonMap.entries) {
      final key = entry.key;
      final val = entry.value;
      if (val == null) continue;

      if (fileParamMap.containsKey(key)) {
        final paramName = fileParamMap[key]!;
        final valStr = val.toString().trim();
        if (storage.isCapturedImage(valStr)) {
          final bytes = storage.resolveBytes(valStr) ?? DataUrl.decode(valStr);
          if (bytes != null && bytes.isNotEmpty) {
            formDataMap[paramName] = MultipartFile.fromBytes(
              bytes,
              filename: '${paramName.toLowerCase()}.jpg',
            );
            continue;
          }
        }
        // If not a newly captured file, preserve the existing server path or URL string
        if (valStr.isNotEmpty) {
          formDataMap[key] = valStr;
        }
      } else {
        // Scalar text fields
        formDataMap[key] = val.toString();
      }
    }

    return FormData.fromMap(formDataMap);
  }
}
