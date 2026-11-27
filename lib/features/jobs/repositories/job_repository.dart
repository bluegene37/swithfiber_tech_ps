import 'dart:async';
import '../../../core/database/daos/job_orders_dao.dart';
import '../../../core/database/daos/sync_error_logs_dao.dart';
// Gene - Nov, 26, 2026: Added WorkTimingHistoryDao and WorkTimingEntry imports for recording restartable Job Order timing sessions.
import '../../../core/database/daos/work_timing_history_dao.dart';
import '../../../core/database/models/work_timing_entry.dart';
import '../../../core/services/photo_storage_service.dart';
// Gene - Nov, 27, 2026: Added PowerSyncService import to detect replicated PowerSync mode.
import '../../../core/sync/powersync_service.dart';
// Gene - Nov, 25, 2026: Added shared timing helpers for Job Order Start/Finish tracking.
import '../../../core/widgets/work_timing_bar.dart';
import '../models/job_order_images_model.dart';
import '../models/job_order_model.dart';
import '../services/job_orders_api.dart';
import '../services/sync_worker.dart';

/// Repository coordinating the local PowerSync cache and remote API operations.
class JobRepository {
  final JobOrdersDao _dao;
  final JobOrdersApi _api;
  late final SyncWorker syncWorker;

  /// The on-phone record of refused pushes, so the Settings screen can show
  /// it without reaching for a database singleton that does not exist.
  final SyncErrorLogsDao? errorLog;

  // Gene - Nov, 26, 2026: Optional WorkTimingHistoryDao to log every Start / Start Again / Finish session by userId and date.
  final WorkTimingHistoryDao? timingHistory;
  // Gene - Nov, 27, 2026: Flag callback indicating live PowerSync replication is active (skip legacy REST pull/push).
  final bool Function() _isReplicatedMode;

  /*
  JobRepository(this._dao, {JobOrdersApi? api, this.errorLog})
      : _api = api ?? DioJobOrdersApi() {
    syncWorker = SyncWorker(_dao, api: _api, errorLog: errorLog);
  }
  */
  JobRepository(
    this._dao, {
    JobOrdersApi? api,
    this.errorLog,
    this.timingHistory,
    bool Function()? isReplicatedMode,
  })  : _api = api ?? DioJobOrdersApi(),
        _isReplicatedMode = isReplicatedMode ??
            (() => PowerSyncService.instance.isReplicatedMode) {
    syncWorker = SyncWorker(_dao, api: _api, errorLog: errorLog);
  }

  // Gene - Nov 5, 2026: Cached Job Order site photo proofs and customer signature by job ID.
  final Map<int, JobOrderImagesDto> _imagesCache = {};

  /// Clear in-memory photos cache (useful for tests or refresh).
  void clearImagesCache([int? id]) {
    if (id != null) {
      _imagesCache.remove(id);
    } else {
      _imagesCache.clear();
    }
  }

  /// Fetches photo proofs and signature for a Job Order from GET /api/JobOrders/{id}/GetJobOrderImage.
  Future<JobOrderImagesDto?> getJobOrderImages(
    int jobId, {
    bool forceRefresh = false,
  }) async {
    /*
    if (!forceRefresh && _imagesCache.containsKey(jobId)) {
      return _imagesCache[jobId];
    }
    */
    // Gene - Nov, 8, 2026: Evict stale cached entry when forceRefresh is true so deleted/updated job photos are always refreshed.
    if (forceRefresh) {
      _imagesCache.remove(jobId);
    } else if (_imagesCache.containsKey(jobId)) {
      return _imagesCache[jobId];
    }

    try {
      final data = await _api.fetchImages(jobId);
      if (data != null) {
        final dto = JobOrderImagesDto.fromJson(data);
        _imagesCache[jobId] = dto;
        return dto;
      }
    } catch (_) {
      // Offline fallback or test mock
    }
    return _imagesCache[jobId];
  }

  /// Watch reactive stream of all jobs directly from the local database
  Stream<List<JobOrderDto>> watchJobs() => _dao.watchAllJobs();

  /// Pull the job orders the technician can act on or look back at, and
  /// bring the cache in line with them.
  ///
  /// Uses `GET /JobOrders/status-assigned` with `assignedEmail` so the server
  /// returns only this technician's jobs across `Scheduled`, `Activated`, and
  /// `Completed`.
  ///
  /// Without [technicianEmail] nothing is pulled and the cache is left as it
  /// is. The login response carries no email, so the first seconds of a
  /// session have none; pulling unscoped then fetched every technician's
  /// history (3,900 jobs) and, because that download outlived the scoped one
  /// that followed, left them on the phone.
  ///
  /// After a successful pull, synced rows the server no longer returned (a job
  /// cancelled or reassigned by the office) are dropped. Rows with local edits
  /// still waiting to sync are never touched: neither overwritten by the
  /// server's older copy nor dropped. They are replaced by the server's
  /// version once the edit has been delivered (see [SyncWorker]).
  Future<void> fetchRemoteJobs({String? technicianEmail}) async {
    // Gene - Nov, 27, 2026: Downstream rows arrive via PowerSync streaming when replicated mode is active.
    if (_isReplicatedMode()) {
      _imagesCache.clear();
      return;
    }

    // Purge test/sample demo jobs (IDs 101-106) permanently
    await _dao.deleteSampleJobs();

    final assignedEmail = technicianEmail?.trim();
    if (assignedEmail == null || assignedEmail.isEmpty) return;

    try {
      /*
      final scheduled = await _api.fetchByStatusAssigned(
        status: JobStatus.scheduled.wireValue,
        assignedEmail: assignedEmail,
      );
      final inProgress = await _api.fetchByStatusAssigned(
        status: JobStatus.inProgress.wireValue,
        assignedEmail: assignedEmail,
      );
      final activated = await _api.fetchByStatusAssigned(
        status: JobStatus.activated.wireValue,
        assignedEmail: assignedEmail,
      );
      final completed = await _api.fetchByStatusAssigned(
        status: JobStatus.completed.wireValue,
        assignedEmail: assignedEmail,
      );
      // Rescheduled jobs are still the technician's open work; without this
      // pull a job marked Rescheduled would vanish from the phone on the
      // next refresh once the server had it.
      final rescheduled = await _api.fetchByStatusAssigned(
        status: JobStatus.rescheduled.wireValue,
        assignedEmail: assignedEmail,
      );
      */
      // Gene - Oct 3, 2026: Fetch status-assigned endpoints concurrently with Future.wait to accelerate sync from ~1s to ~150ms.
      final results = await Future.wait([
        _api.fetchByStatusAssigned(
          status: JobStatus.scheduled.wireValue,
          assignedEmail: assignedEmail,
        ),
        _api.fetchByStatusAssigned(
          status: JobStatus.inProgress.wireValue,
          assignedEmail: assignedEmail,
        ),
        _api.fetchByStatusAssigned(
          status: JobStatus.activated.wireValue,
          assignedEmail: assignedEmail,
        ),
        _api.fetchByStatusAssigned(
          status: JobStatus.completed.wireValue,
          assignedEmail: assignedEmail,
        ),
        _api.fetchByStatusAssigned(
          status: JobStatus.rescheduled.wireValue,
          assignedEmail: assignedEmail,
        ),
      ]);
      final scheduled = results[0];
      final inProgress = results[1];
      final activated = results[2];
      final completed = results[3];
      final rescheduled = results[4];

      final pending = await _dao.getUnsyncedIds();
      final existingJobs = await _dao.getAllJobs();
      final existingMap = {for (final j in existingJobs) j.id: j};
      final fresh = <JobOrderDto>[];
      final keep = <int>{};

      void take(JobOrderDto dto, Map<String, dynamic> raw) {
        keep.add(dto.id);
        // A pending local edit is newer than anything the server has.
        if (pending.contains(dto.id)) return;
        final existing = existingMap[dto.id];
        if (existing != null) {
          fresh.add(existing.mergeWithServer(dto, freshJson: raw));
        } else {
          fresh.add(dto);
        }
      }

      for (final item in scheduled) {
        take(JobOrderDto.fromJson(item), item);
      }
      for (final item in inProgress) {
        take(JobOrderDto.fromJson(item), item);
      }
      for (final item in activated) {
        take(JobOrderDto.fromJson(item), item);
      }
      for (final item in completed) {
        take(JobOrderDto.fromJson(item), item);
      }
      for (final item in rescheduled) {
        take(JobOrderDto.fromJson(item), item);
      }

      if (fresh.isNotEmpty) {
        await _dao.insertAllJobs(fresh, synced: true);
      }
      /*
      if (keep.isNotEmpty) {
        await _dao.deleteSyncedJobsNotIn(keep);
      }
      */
      /*
      // Gene - Oct 3, 2026: Guard deleteSyncedJobsNotIn with keep.isNotEmpty to prevent accidental cache wipe when remote responses are empty.
      if (keep.isNotEmpty) {
        await _dao.deleteSyncedJobsNotIn(keep);
      }
      */
      // Gene - Nov, 13, 2026: Always prune synced jobs absent from verified 200 status-assigned responses (even when keep is empty) and evict stale photo cache for refreshed/deleted jobs.
      await _dao.deleteSyncedJobsNotIn(keep);
      _imagesCache.removeWhere(
        (id, _) => !pending.contains(id),
      );
    } catch (_) {
      // Offline fallback: do not re-seed test data
    }
  }

  /// Activate a job: Scheduled -> Activated, the only transition in the field.
  ///
  /// Complete a job: Scheduled -> Completed.
  ///
  /// The completing technician's email is stamped on the record so the job
  /// appears in their history, and the install date is set if it was not
  /// already. Queued for sync like every other edit.
  /// Returns the sync attempt's outcome so the caller can tell the technician
  /// whether the office actually has the completion, rather than reporting
  /// success off the local write alone.
  Future<SyncResult> completeJob(int id, {String? technicianEmail}) async {
    final existing = await _dao.getJobById(id);
    final email = technicianEmail?.trim();
    await _dao.completeJob(
      id,
      assignedEmail: (email == null || email.isEmpty) ? null : email,
      installedAt: existing?.dateInstalled ?? DateTime.now(),
      isSynced: false,
    );
    if (_isReplicatedMode()) {
      return SyncResult(
        success: true,
        syncedCount: 1,
        message: 'Queued via PowerSync sync.',
      );
    }
    await syncWorker.refreshPendingCount();
    return syncWorker.syncPendingJobs();
  }

  /// Activate a job: Scheduled -> Activated.
  Future<void> activateJob(int id, {String? technicianEmail}) async {
    final existing = await _dao.getJobById(id);
    final email = technicianEmail?.trim();
    await _dao.activateJob(
      id,
      assignedEmail: (email == null || email.isEmpty) ? null : email,
      installedAt: existing?.dateInstalled ?? DateTime.now(),
      isSynced: false,
    );
    if (_isReplicatedMode()) return;
    await syncWorker.refreshPendingCount();
    unawaited(syncWorker.syncPendingJobs());
  }

  /// Move an open job between Scheduled and Rescheduled. A Rescheduled job
  /// carries one of [RescheduleReasons] in `statusRemarks`; going back to
  /// Scheduled clears it. Written locally first and queued like every
  /// other edit.
  Future<void> changeStatus(
    int id, {
    required JobStatus status,
    String? statusRemarks,
  }) async {
    assert(status == JobStatus.scheduled || status == JobStatus.rescheduled,
        'changeStatus only moves between the open stages');
    await _dao.updateStatusWithRemarks(
      id,
      status: status.wireValue,
      statusRemarks: status == JobStatus.rescheduled ? statusRemarks : '',
      isSynced: false,
    );
    if (_isReplicatedMode()) return;
    await syncWorker.refreshPendingCount();
    unawaited(syncWorker.syncPendingJobs());
  }

  /// Update the technician's on-site status locally and queue it for sync.
  Future<void> updateFieldStatus(int id, String onsiteStatus) async {
    await _dao.updateFieldStatus(id, onsiteStatus, isSynced: false);
    if (_isReplicatedMode()) return;
    await syncWorker.refreshPendingCount();
    unawaited(syncWorker.syncPendingJobs());
  }

  /// Update job status locally and trigger offline sync worker
  Future<void> updateJobStatus(int id, String newStatus) async {
    // 1. Instant local optimistic update (isSynced = false)
    await _dao.updateJobStatus(id, newStatus, isSynced: false);
    if (_isReplicatedMode()) return;
    await syncWorker.refreshPendingCount();

    // 2. Proactively trigger background sync
    unawaited(syncWorker.syncPendingJobs());
  }

  // Gene - Nov, 25, 2026: Stamp local Job Order Start time and post POST /JobOrders/createtiming.
  /*
  Future<DateTime> startJobTiming(int id, {required String techId}) async {
    final now = DateTime.now().toUtc();
    await _dao.updateJobTiming(id, startTimeStamp: now);
    try {
      await _api.createTiming(
        joId: id,
        techId: techId,
        startTime: now,
        endTime: now,
      );
    } catch (_) {
      // Keep local unlock and queue via syncPendingJobs on failure.
      await _dao.updateJobTiming(id, startTimeStamp: now, isSynced: false);
      await syncWorker.refreshPendingCount();
      rethrow;
    }
    return now;
  }

  // Gene - Nov, 25, 2026: Stamp local Job Order Finish time and send PUT /JobOrders/updatetiming.
  Future<DateTime> finishJobTiming(
    JobOrderDto job, {
    required String techId,
  }) async {
    final start = normalizeTimingTimestamp(job.startTimeStamp) ??
        DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    var end = DateTime.now().toUtc();
    if (!end.isAfter(start)) {
      end = start.add(const Duration(seconds: 1));
    }
    await _dao.updateJobTiming(
      job.id,
      startTimeStamp: start,
      endTimeStamp: end,
    );
    try {
      await _api.updateTiming(
        joId: job.id,
        techId: techId,
        startTime: start,
        endTime: end,
      );
    } catch (_) {
      await _dao.updateJobTiming(
        job.id,
        startTimeStamp: start,
        endTimeStamp: end,
        isSynced: false,
      );
      await syncWorker.refreshPendingCount();
      rethrow;
    }
    return end;
  }
  */
  // Gene - Nov, 26, 2026: Support restarting finished Job Orders (resetting endTimeStamp to now) and log every Start/Finish session to WorkTimingHistoryDao.
  Future<DateTime> startJobTiming(
    int id, {
    required String techId,
    String? userName,
  }) async {
    final existing = await _dao.getJobById(id);
    var now = DateTime.now().toUtc();
    final prevStart = normalizeTimingTimestamp(existing?.startTimeStamp);
    final prevEnd = normalizeTimingTimestamp(existing?.endTimeStamp);
    for (final prev in [prevStart, prevEnd]) {
      if (prev != null && !now.isAfter(prev)) {
        now = prev.add(const Duration(seconds: 1));
      }
    }
    await _dao.updateJobTiming(id, startTimeStamp: now, endTimeStamp: now);
    final entryId = await timingHistory?.recordStart(
      orderType: WorkTimingEntry.orderTypeJobOrder,
      orderId: id,
      orderReference: existing?.ticketNumber ?? 'JO-$id',
      customerName: existing?.customerName ?? 'Job #$id',
      userId: techId,
      userName: userName,
      startTime: now,
      isSynced: false,
    );
    try {
      await _api.createTiming(
        joId: id,
        techId: techId,
        startTime: now,
        endTime: now,
      );
      if (entryId != null) {
        await timingHistory?.markSynced(entryId, isSynced: true);
      }
    } catch (_) {
      if (_isReplicatedMode()) {
        // start_timestamp is queued via PowerSync ps_crud on job_orders.
        return now;
      }
      // Keep local unlock and queue via syncPendingJobs on failure.
      await _dao.updateJobTiming(
        id,
        startTimeStamp: now,
        endTimeStamp: now,
        isSynced: false,
      );
      await syncWorker.refreshPendingCount();
      rethrow;
    }
    return now;
  }

  Future<DateTime> finishJobTiming(
    JobOrderDto job, {
    required String techId,
    String? userName,
  }) async {
    final start = normalizeTimingTimestamp(job.startTimeStamp) ??
        DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    var end = DateTime.now().toUtc();
    if (!end.isAfter(start)) {
      end = start.add(const Duration(seconds: 1));
    }
    await _dao.updateJobTiming(
      job.id,
      startTimeStamp: start,
      endTimeStamp: end,
    );
    final entryId = await timingHistory?.recordFinish(
      orderType: WorkTimingEntry.orderTypeJobOrder,
      orderId: job.id,
      orderReference: job.ticketNumber,
      customerName: job.customerName,
      userId: techId,
      userName: userName,
      startTime: start,
      endTime: end,
      isSynced: false,
    );
    try {
      await _api.updateTiming(
        joId: job.id,
        techId: techId,
        startTime: start,
        endTime: end,
      );
      if (entryId != null) {
        await timingHistory?.markSynced(entryId, isSynced: true);
      }
    } catch (_) {
      if (_isReplicatedMode()) {
        // end_timestamp is queued via PowerSync ps_crud on job_orders.
        return end;
      }
      await _dao.updateJobTiming(
        job.id,
        startTimeStamp: start,
        endTimeStamp: end,
        isSynced: false,
      );
      await syncWorker.refreshPendingCount();
      rethrow;
    }
    return end;
  }

  /// Save completion report details locally and queue for sync.
  /// Does not change the job order status unless [status] is explicitly provided.
  /*
  Future<void> saveCompletionReport({
    required int id,
    String? status,
    required String onsiteStatus,
    required String onsiteRemarks,
    double? opticalPower,
    String? modemRouterSN,
    String? routerModel,
    String? nap,
    String? boxReadingImage,
    String? routerReadingImage,
    String? clientSignature,
    String? setupImage,
    String? speedtestImage,
    String? portLabelImage,
    String? signedContractImage,
    String? houseFront,
    String? assignedEmail,
    Map<String, int>? materialsUsed,
  }) async {
  */
  /*
  // Gene - Oct 13, 2026: Added vlanId parameter to saveCompletionReport.
  Future<void> saveCompletionReport({
    required int id,
    String? status,
    required String onsiteStatus,
    required String onsiteRemarks,
    double? opticalPower,
    String? modemRouterSN,
    String? routerModel,
    String? nap,
    int? vlanId,
    String? boxReadingImage,
    String? routerReadingImage,
    String? clientSignature,
    String? setupImage,
    String? speedtestImage,
    String? portLabelImage,
    String? signedContractImage,
    String? houseFront,
    String? assignedEmail,
    Map<String, int>? materialsUsed,
  }) async {
  */
/*
  // Gene - Oct 13, 2026: Added planId and planName parameters to saveCompletionReport to support on-site plan upgrades.
  Future<void> saveCompletionReport({
    required int id,
    String? status,
    required String onsiteStatus,
    required String onsiteRemarks,
    double? opticalPower,
    String? modemRouterSN,
    String? routerModel,
    String? nap,
    int? vlanId,
    int? planId,
    String? planName,
    String? boxReadingImage,
    String? routerReadingImage,
    String? clientSignature,
    String? setupImage,
    String? speedtestImage,
    String? portLabelImage,
    String? signedContractImage,
    String? houseFront,
    String? assignedEmail,
    Map<String, int>? materialsUsed,
  }) async {
    final photoStorage = PhotoStorageService.instance;
    final savedBox = await photoStorage.savePhotoLocally(boxReadingImage,
        tag: 'box_reading', entityId: id);
    final savedRouter = await photoStorage.savePhotoLocally(routerReadingImage,
        tag: 'router_reading', entityId: id);
    final savedSig = await photoStorage.savePhotoLocally(clientSignature,
        tag: 'signature', entityId: id);
    final savedSetup = await photoStorage.savePhotoLocally(setupImage,
        tag: 'setup', entityId: id);
    final savedSpeed = await photoStorage.savePhotoLocally(speedtestImage,
        tag: 'speedtest', entityId: id);
    final savedPort = await photoStorage.savePhotoLocally(portLabelImage,
        tag: 'port_label', entityId: id);
    final savedContract = await photoStorage.savePhotoLocally(
        signedContractImage,
        tag: 'signed_contract',
        entityId: id);
    final savedHouse = await photoStorage.savePhotoLocally(houseFront,
        tag: 'house_front', entityId: id);

    await _dao.updateJobCompletion(
      id: id,
      status: status,
      onsiteStatus: onsiteStatus,
      onsiteRemarks: onsiteRemarks,
      opticalPower: opticalPower,
      modemRouterSN: modemRouterSN,
      routerModel: routerModel,
      nap: nap,
      vlanId: vlanId,
      // Gene - Oct 13, 2026: Pass planId and planName to updateJobCompletion.
      planId: planId,
      planName: planName,
      boxReadingImage: savedBox,
      routerReadingImage: savedRouter,
      clientSignature: savedSig,
      setupImage: savedSetup,
      speedtestImage: savedSpeed,
      portLabelImage: savedPort,
      signedContractImage: savedContract,
      houseFront: savedHouse,
      assignedEmail: assignedEmail,
      materialsUsed: materialsUsed,
      isSynced: false,
    );

    // Gene - Nov 5, 2026: Invalidate cached photos so subsequent views fetch fresh server uploads.
    _imagesCache.remove(id);

    await syncWorker.refreshPendingCount();
    unawaited(syncWorker.syncPendingJobs());
  }
*/
/*
  // Gene - Oct 13, 2026: Added connectionType parameter to saveCompletionReport to support on-site connection type selection.
  Future<void> saveCompletionReport({
    required int id,
    String? status,
    required String onsiteStatus,
    required String onsiteRemarks,
    double? opticalPower,
    String? modemRouterSN,
    String? routerModel,
    String? nap,
    int? vlanId,
    int? planId,
    String? planName,
    String? connectionType,
    String? boxReadingImage,
    String? routerReadingImage,
    String? clientSignature,
    String? setupImage,
    String? speedtestImage,
    String? portLabelImage,
    String? signedContractImage,
    String? houseFront,
    String? assignedEmail,
    Map<String, int>? materialsUsed,
  }) async {
    final photoStorage = PhotoStorageService.instance;
    final savedBox = await photoStorage.savePhotoLocally(boxReadingImage,
        tag: 'box_reading', entityId: id);
    final savedRouter = await photoStorage.savePhotoLocally(routerReadingImage,
        tag: 'router_reading', entityId: id);
    final savedSig = await photoStorage.savePhotoLocally(clientSignature,
        tag: 'signature', entityId: id);
    final savedSetup = await photoStorage.savePhotoLocally(setupImage,
        tag: 'setup', entityId: id);
    final savedSpeed = await photoStorage.savePhotoLocally(speedtestImage,
        tag: 'speedtest', entityId: id);
    final savedPort = await photoStorage.savePhotoLocally(portLabelImage,
        tag: 'port_label', entityId: id);
    final savedContract = await photoStorage.savePhotoLocally(
        signedContractImage,
        tag: 'signed_contract',
        entityId: id);
    final savedHouse = await photoStorage.savePhotoLocally(houseFront,
        tag: 'house_front', entityId: id);

    await _dao.updateJobCompletion(
      id: id,
      status: status,
      onsiteStatus: onsiteStatus,
      onsiteRemarks: onsiteRemarks,
      opticalPower: opticalPower,
      modemRouterSN: modemRouterSN,
      routerModel: routerModel,
      nap: nap,
      vlanId: vlanId,
      // Gene - Oct 13, 2026: Pass planId and planName to updateJobCompletion.
      planId: planId,
      planName: planName,
      connectionType: connectionType,
      boxReadingImage: savedBox,
      routerReadingImage: savedRouter,
      clientSignature: savedSig,
      setupImage: savedSetup,
      speedtestImage: savedSpeed,
      portLabelImage: savedPort,
      signedContractImage: savedContract,
      houseFront: savedHouse,
      assignedEmail: assignedEmail,
      materialsUsed: materialsUsed,
      isSynced: false,
    );

    // Gene - Nov 5, 2026: Invalidate cached photos so subsequent views fetch fresh server uploads.
    _imagesCache.remove(id);

    await syncWorker.refreshPendingCount();
    unawaited(syncWorker.syncPendingJobs());
  }
*/
  // Gene - Oct 13, 2026: Added visitBy and visitWith parameters to saveCompletionReport to support technician attendance tracking.
  Future<void> saveCompletionReport({
    required int id,
    String? status,
    required String onsiteStatus,
    required String onsiteRemarks,
    double? opticalPower,
    String? modemRouterSN,
    String? routerModel,
    String? nap,
    int? vlanId,
    int? planId,
    String? planName,
    String? connectionType,
    String? visitBy,
    String? visitWith,
    String? boxReadingImage,
    String? routerReadingImage,
    String? clientSignature,
    String? setupImage,
    String? speedtestImage,
    String? portLabelImage,
    String? signedContractImage,
    String? houseFront,
    String? assignedEmail,
    Map<String, int>? materialsUsed,
  }) async {
    final photoStorage = PhotoStorageService.instance;
    final savedBox = await photoStorage.savePhotoLocally(boxReadingImage,
        tag: 'box_reading', entityId: id);
    final savedRouter = await photoStorage.savePhotoLocally(routerReadingImage,
        tag: 'router_reading', entityId: id);
    final savedSig = await photoStorage.savePhotoLocally(clientSignature,
        tag: 'signature', entityId: id);
    final savedSetup = await photoStorage.savePhotoLocally(setupImage,
        tag: 'setup', entityId: id);
    final savedSpeed = await photoStorage.savePhotoLocally(speedtestImage,
        tag: 'speedtest', entityId: id);
    final savedPort = await photoStorage.savePhotoLocally(portLabelImage,
        tag: 'port_label', entityId: id);
    final savedContract = await photoStorage.savePhotoLocally(
        signedContractImage,
        tag: 'signed_contract',
        entityId: id);
    final savedHouse = await photoStorage.savePhotoLocally(houseFront,
        tag: 'house_front', entityId: id);

    await _dao.updateJobCompletion(
      id: id,
      status: status,
      onsiteStatus: onsiteStatus,
      onsiteRemarks: onsiteRemarks,
      opticalPower: opticalPower,
      modemRouterSN: modemRouterSN,
      routerModel: routerModel,
      nap: nap,
      vlanId: vlanId,
      planId: planId,
      planName: planName,
      connectionType: connectionType,
      visitBy: visitBy,
      visitWith: visitWith,
      boxReadingImage: savedBox,
      routerReadingImage: savedRouter,
      clientSignature: savedSig,
      setupImage: savedSetup,
      speedtestImage: savedSpeed,
      portLabelImage: savedPort,
      signedContractImage: savedContract,
      houseFront: savedHouse,
      assignedEmail: assignedEmail,
      materialsUsed: materialsUsed,
      isSynced: false,
    );

    // Gene - Nov 5, 2026: Invalidate cached photos so subsequent views fetch fresh server uploads.
    _imagesCache.remove(id);

    if (_isReplicatedMode()) return;
    await syncWorker.refreshPendingCount();
    unawaited(syncWorker.syncPendingJobs());
  }

  /// Seed realistic demo fiber installation and repair job orders
  Future<void> seedSampleJobs() async {
    final now = DateTime.now();
    /*
    final sampleJobs = [
      JobOrderDto(
        id: 101,
        ticketNumber: 'SF-2026-0801',
        customerName: 'Rosario Mendoza',
        contactNumber: '+63 917 555 1234',
        address: 'Blk 12 Lot 4, Redwood St., Villa Verde',
        barangay: 'San Roque',
        city: 'Antipolo',
        planName: 'Fiber Blast 100 Mbps',
        planId: 2,
        status: 'Scheduled',
        onsiteStatus: 'Scheduled',
        onsiteRemarks: 'Running drop cable from NAP 04 to subscriber home.',
        opticalPower: -19.5,
        modemRouterSN: 'HWTC8829104',
        routerModel: 'Huawei HG8145V5',
        lcpId: 1,
        napId: 4,
        portId: 'Port 2',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 102,
        ticketNumber: 'SF-2026-0802',
        customerName: 'Danilo Santos',
        contactNumber: '+63 928 444 8899',
        address: 'Unit 5B, Skyline Tower, Emerald Ave.',
        barangay: 'San Antonio',
        city: 'Pasig',
        planName: 'Fiber Giga 200 Mbps',
        planId: 3,
        status: 'Scheduled',
        onsiteStatus: 'Dispatched',
        onsiteRemarks: 'Scheduled morning installation dispatch.',
        lcpId: 2,
        napId: 8,
        portId: 'Port 6',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 103,
        ticketNumber: 'SF-2026-0803',
        customerName: 'Maria Elena Cruz',
        contactNumber: '+63 919 333 4567',
        address: '45 Jasmin St., Phase 2, Greenpark Village',
        barangay: 'Manggahan',
        city: 'Pasig',
        planName: 'Fiber Basic 50 Mbps',
        planId: 1,
        status: 'Activated',
        onsiteStatus: 'Done',
        onsiteRemarks: 'Fiber termination verified. Rx power: -18.2 dBm.',
        assignedEmail: 'technician@switchfiber.ph',
        opticalPower: -18.2,
        modemRouterSN: 'ZTE8839001',
        routerModel: 'ZTE F670L',
        lcpId: 1,
        napId: 3,
        portId: 'Port 1',
        dateInstalled: now.subtract(const Duration(days: 1)),
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 104,
        ticketNumber: 'SF-2026-0804',
        customerName: 'Eduardo Bautista',
        contactNumber: '+63 908 222 1100',
        address: '77 Katipunan Ave., Loyola Heights',
        barangay: 'Loyola Heights',
        city: 'Quezon City',
        planName: 'Fiber Blast 100 Mbps',
        planId: 2,
        status: 'Activated',
        onsiteStatus: 'Done',
        onsiteRemarks: 'Subscriber online. RADIUS account active.',
        assignedEmail: 'technician@switchfiber.ph',
        opticalPower: -17.8,
        modemRouterSN: 'HWTC4490123',
        routerModel: 'Huawei EG8145V5',
        lcpId: 3,
        napId: 12,
        portId: 'Port 5',
        dateInstalled: now.subtract(const Duration(days: 2)),
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 105,
        ticketNumber: 'SF-2026-0805',
        customerName: 'Jasmine Alcantara',
        contactNumber: '+63 918 777 3322',
        address: 'Blk 4 Lot 19, Camella Homes, Manila East Rd',
        barangay: 'San Juan',
        city: 'Taytay',
        planName: 'Fiber Blast 100 Mbps',
        planId: 2,
        status: 'Scheduled',
        onsiteStatus: 'Scheduled',
        onsiteRemarks: 'New installation scheduled. Near Guard House Gate 2.',
        lcpId: 1,
        napId: 2,
        portId: 'Port 3',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 106,
        ticketNumber: 'SF-2026-0806',
        customerName: 'Rafael De Silva',
        contactNumber: '+63 920 111 9988',
        address: 'Unit 1204, Mega Plaza, Ortigas Ave.',
        barangay: 'San Antonio',
        city: 'Pasig',
        planName: 'Fiber Giga 200 Mbps',
        planId: 3,
        status: 'Scheduled',
        onsiteStatus: 'Scheduled',
        onsiteRemarks:
            'Scheduled afternoon dispatch. Customer requested PM slot.',
        lcpId: 2,
        napId: 5,
        portId: 'Port 7',
        isSynced: true,
        updatedAt: now,
      ),
    ];
    */
    // Gene - Oct 13, 2026: Seeded GPS coordinates in rawJson for demo job orders to display location pins on map.
    final sampleJobs = [
      JobOrderDto(
        id: 101,
        ticketNumber: 'SF-2026-0801',
        customerName: 'Rosario Mendoza',
        contactNumber: '+63 917 555 1234',
        address: 'Blk 12 Lot 4, Redwood St., Villa Verde',
        barangay: 'San Roque',
        city: 'Antipolo',
        planName: 'Fiber Blast 100 Mbps',
        planId: 2,
        status: 'Scheduled',
        onsiteStatus: 'Scheduled',
        onsiteRemarks: 'Running drop cable from NAP 04 to subscriber home.',
        opticalPower: -19.5,
        modemRouterSN: 'HWTC8829104',
        routerModel: 'Huawei HG8145V5',
        lcpId: 1,
        napId: 4,
        portId: 'Port 2',
        rawJson: '{"coordinates": "14.6291, 121.1280"}',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 102,
        ticketNumber: 'SF-2026-0802',
        customerName: 'Danilo Santos',
        contactNumber: '+63 928 444 8899',
        address: 'Unit 5B, Skyline Tower, Emerald Ave.',
        barangay: 'San Antonio',
        city: 'Pasig',
        planName: 'Fiber Giga 200 Mbps',
        planId: 3,
        status: 'Scheduled',
        onsiteStatus: 'Dispatched',
        onsiteRemarks: 'Scheduled morning installation dispatch.',
        lcpId: 2,
        napId: 8,
        portId: 'Port 6',
        rawJson: '{"coordinates": "14.5868, 121.0625"}',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 103,
        ticketNumber: 'SF-2026-0803',
        customerName: 'Maria Elena Cruz',
        contactNumber: '+63 919 333 4567',
        address: '45 Jasmin St., Phase 2, Greenpark Village',
        barangay: 'Manggahan',
        city: 'Pasig',
        planName: 'Fiber Basic 50 Mbps',
        planId: 1,
        status: 'Activated',
        onsiteStatus: 'Done',
        onsiteRemarks: 'Fiber termination verified. Rx power: -18.2 dBm.',
        assignedEmail: 'technician@switchfiber.ph',
        opticalPower: -18.2,
        modemRouterSN: 'ZTE8839001',
        routerModel: 'ZTE F670L',
        lcpId: 1,
        napId: 3,
        portId: 'Port 1',
        dateInstalled: now.subtract(const Duration(days: 1)),
        rawJson: '{"coordinates": "14.5880, 121.0640"}',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 104,
        ticketNumber: 'SF-2026-0804',
        customerName: 'Eduardo Bautista',
        contactNumber: '+63 908 222 1100',
        address: '77 Katipunan Ave., Loyola Heights',
        barangay: 'Loyola Heights',
        city: 'Quezon City',
        planName: 'Fiber Blast 100 Mbps',
        planId: 2,
        status: 'Activated',
        onsiteStatus: 'Done',
        onsiteRemarks: 'Subscriber online. RADIUS account active.',
        assignedEmail: 'technician@switchfiber.ph',
        opticalPower: -17.8,
        modemRouterSN: 'HWTC4490123',
        routerModel: 'Huawei EG8145V5',
        lcpId: 3,
        napId: 12,
        portId: 'Port 5',
        dateInstalled: now.subtract(const Duration(days: 2)),
        rawJson: '{"coordinates": "14.6435, 121.0715"}',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 105,
        ticketNumber: 'SF-2026-0805',
        customerName: 'Jasmine Alcantara',
        contactNumber: '+63 918 777 3322',
        address: 'Blk 4 Lot 19, Camella Homes, Manila East Rd',
        barangay: 'San Juan',
        city: 'Taytay',
        planName: 'Fiber Blast 100 Mbps',
        planId: 2,
        status: 'Scheduled',
        onsiteStatus: 'Scheduled',
        onsiteRemarks: 'New installation scheduled. Near Guard House Gate 2.',
        lcpId: 1,
        napId: 2,
        portId: 'Port 3',
        rawJson: '{"coordinates": "14.5710, 121.1350"}',
        isSynced: true,
        updatedAt: now,
      ),
      JobOrderDto(
        id: 106,
        ticketNumber: 'SF-2026-0806',
        customerName: 'Rafael De Silva',
        contactNumber: '+63 920 111 9988',
        address: 'Unit 1204, Mega Plaza, Ortigas Ave.',
        barangay: 'San Antonio',
        city: 'Pasig',
        planName: 'Fiber Giga 200 Mbps',
        planId: 3,
        status: 'Scheduled',
        onsiteStatus: 'Scheduled',
        onsiteRemarks:
            'Scheduled afternoon dispatch. Customer requested PM slot.',
        lcpId: 2,
        napId: 5,
        portId: 'Port 7',
        rawJson: '{"coordinates": "14.5855, 121.0610"}',
        isSynced: true,
        updatedAt: now,
      ),
    ];

    await _dao.insertAllJobs(sampleJobs, synced: true);
  }
}
