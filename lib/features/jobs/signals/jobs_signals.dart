import 'dart:async';
// Gene - Oct 3, 2026: Commented out unused services.dart import now that sound and haptics are encapsulated in SoundService.
// import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
// Gene - Nov, 20, 2026: Added app_constants and secure_storage_service imports for persisting read job IDs.
import '../../../core/constants/app_constants.dart';
// Gene - Nov, 26, 2026: Added WorkTimingHistoryDao and work_timing_bar imports for timing history and user resolution.
import '../../../core/database/daos/work_timing_history_dao.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/storage/secure_storage_service.dart';
// Gene - Nov, 28, 2026: Import PowerSyncService so manual fetchRemote can trigger a live PowerSync reconnect in replicated mode.
import '../../../core/sync/powersync_service.dart';
import '../../../core/widgets/loading_states.dart';
import '../../../core/widgets/work_timing_bar.dart';
// Gene - Nov, 25, 2026: Added AuthSignals import to resolve technician ID for Start/Finish timing calls.
// Gene - Nov, 26, 2026: Commented out unused AuthSignals import after delegating user ID/name resolution to work_timing_bar.dart.
// import '../../auth/signals/auth_signals.dart';
// Gene - Nov, 28, 2026: Re-enabled AuthSignals import so REST-mode refresh retries fetchProfile when technicianEmail is missing.
import '../../auth/signals/auth_signals.dart';
import '../models/job_order_images_model.dart';
import '../models/job_order_model.dart';
import '../repositories/job_repository.dart';
import '../services/sync_worker.dart';

/// Which terminal status of the technician's job history is shown.
enum HistoryStatusFilter {
  all('All'),
  activated('Activated'),
  completed('Completed');

  const HistoryStatusFilter(this.label);

  final String label;
}

/// The date window applied to the technician's job history.
enum HistoryRange {
  all('All time'),
  today('Today'),
  week('This week'),
  custom('Pick dates');

  const HistoryRange(this.label);

  final String label;
}

/// Signals state layer for Job Orders.
/// Pipes the PowerSync reactive stream into Signals and provides instant UI computations.
class JobsSignals {
  final JobRepository repository;

  /// Source of "now" for the history date windows; injectable for tests.
  final DateTime Function() clock;

  /// Optional notification hook for audio/vibration; injectable for tests.
  final void Function(JobOrderDto job)? onNewJobAlert;

  StreamSubscription<List<JobOrderDto>>? _driftSubscription;
  // Gene - Nov, 20, 2026: Added storage dependency for persisting read job order IDs across restarts.
  final SecureStorageService _storage;

  /*
  JobsSignals(
    this.repository, {
    DateTime Function()? clock,
    this.onNewJobAlert,
  }) : clock = clock ?? DateTime.now {
    _initDriftStream();
  }
  */
  // Gene - Nov, 20, 2026: Added optional storage parameter to constructor for read/unread badge persistence and testing.
  JobsSignals(
    this.repository, {
    DateTime Function()? clock,
    this.onNewJobAlert,
    SecureStorageService? storage,
  })  : clock = clock ?? DateTime.now,
        _storage = storage ?? SecureStorageService.instance {
    _initDriftStream();
  }

  // Raw State Signals
  final allJobs = signal<List<JobOrderDto>>([]);
  // Defaults to 'scheduled' so technicians immediately see their scheduled work orders.
  final activeFilter = signal<String>(JobStatus.scheduled.name);
  final searchQuery = signal<String>('');
  final selectedJob = signal<JobOrderDto?>(null);
  final isRefreshing = signal<bool>(false);

  // Gene - Nov 5, 2026: Fetches site photo proofs and subscriber signature for a Job Order with optional force refresh.
  Future<JobOrderImagesDto?> getJobOrderImages(int jobId,
          {bool forceRefresh = false}) =>
      repository.getJobOrderImages(jobId, forceRefresh: forceRefresh);
  // First-load presentation: downloading -> skeleton -> ready. Stays ready for
  // pull-to-refresh and manual syncs so existing data is never hidden.
  final loadPhase = signal<DataLoadPhase>(DataLoadPhase.ready);

  /// Surfaced when a new open Job Order is synced or assigned to the technician.
  final newJobAlert = signal<JobOrderDto?>(null);

  bool _hasInitialSnapshot = false;
  final Set<int> _knownJobIds = <int>{};
  final Set<int> _myAssignedJobIds = <int>{};

  // Gene - Nov, 20, 2026: Track read job IDs per technician session so navigation bubbles only count unread dispatches.
  final readJobIds = signal<Set<int>>(<int>{});
  int _readLoadEpoch = 0;

  // Gene - Nov, 25, 2026: Track in-flight Start/Finish timing requests per Job Order ID.
  final busyTimingJobIds = signal<Set<int>>(<int>{});

  /*
  // Gene - Nov, 26, 2026: Expose currently started (in-progress) Job Order so other Job Orders and Service Orders hide Start.
  late final ReadonlySignal<JobOrderDto?> activeStartedJob = computed(() {
    final email = technicianEmail.value?.trim() ?? '';
    for (final job in allJobs.value) {
      if (!job.canActivate || !job.isTimingInProgress) continue;
      if (email.isNotEmpty &&
          (job.assignedEmail?.trim().isNotEmpty ?? false) &&
          !job.isAssignedTo(email)) {
        continue;
      }
      return job;
    }
    return null;
  });
  */
  // Gene - Nov, 28, 2026: Restrict activeStartedJob to visible open non-rescheduled Today jobs so hidden Inprogress rows cannot lock Start across other orders.
  late final ReadonlySignal<JobOrderDto?> activeStartedJob = computed(() {
    final email = technicianEmail.value?.trim() ?? '';
    for (final job in allJobs.value) {
      if (!job.isOpen ||
          !job.canActivate ||
          job.siteException == SiteException.reschedule ||
          !job.isTimingInProgress) {
        continue;
      }
      if (email.isNotEmpty &&
          (job.assignedEmail?.trim().isNotEmpty ?? false) &&
          !job.isAssignedTo(email)) {
        continue;
      }
      return job;
    }
    return null;
  });

  // Technician history: activated jobs whose assignedEmail matches the
  // signed-in technician, with their own date, area and search filters so the
  // history and the scheduled queue never fight over one query box.
  final technicianEmail = signal<String?>(null);
  final historyStatus = signal<HistoryStatusFilter>(HistoryStatusFilter.all);
  final historyRange = signal<HistoryRange>(HistoryRange.all);
  final historyRangeStart = signal<DateTime?>(null);
  final historyRangeEnd = signal<DateTime?>(null);
  final historyCity = signal<String?>(null);
  final historySearch = signal<String>('');

  // Computeds
  late final ReadonlySignal<List<JobOrderDto>> filteredJobs = computed(() {
    final jobs = allJobs.value;
    final query = searchQuery.value.trim().toLowerCase();

    return jobs.where((job) {
      // Only open work: Scheduled, or Rescheduled and waiting for a new
      // visit. Finished jobs live in the history.
      if (!job.isOpen) {
        return false;
      }

      // Search Query (Ticket #, Customer Name, Address, Barangay)
      if (query.isNotEmpty) {
        final matchesTicket = job.ticketNumber.toLowerCase().contains(query);
        final matchesCustomer = job.customerName.toLowerCase().contains(query);
        final matchesAddress = job.address.toLowerCase().contains(query);
        final matchesBarangay =
            (job.barangay ?? '').toLowerCase().contains(query);
        return matchesTicket ||
            matchesCustomer ||
            matchesAddress ||
            matchesBarangay;
      }

      return true;
    }).toList();
  });

  late final ReadonlySignal<int> totalCount =
      computed(() => allJobs.value.length);

  int _countOf(JobStatus s) =>
      allJobs.value.where((j) => j.jobStatus == s).length;

  /// Jobs marked Rescheduled and waiting for a new visit.
  late final ReadonlySignal<int> rescheduledCount =
      computed(() => _countOf(JobStatus.rescheduled));

  /*
  // Gene - Oct 3, 2026: Include inProgress in scheduledCount so the Today queue badge and summary line accurately reflect all open dispatch work.
  late final ReadonlySignal<int> scheduledCount = computed(
      () => _countOf(JobStatus.scheduled) + _countOf(JobStatus.inProgress));
  */
  // Gene - Oct 3, 2026: Exclude inProgress from scheduledCount per user request so only strictly scheduled jobs are counted in Today queue badge and summary.
  late final ReadonlySignal<int> scheduledCount =
      computed(() => _countOf(JobStatus.scheduled));

  // Gene - Nov, 20, 2026: Count only unread scheduled jobs for the Today navigation bubble and app launcher badge.
  late final ReadonlySignal<int> unreadScheduledCount = computed(() {
    final read = readJobIds.value;
    return allJobs.value
        .where(
            (j) => j.jobStatus == JobStatus.scheduled && !read.contains(j.id))
        .length;
  });

  // Gene - Nov, 20, 2026: Helpers to inspect, mutate, and persist read/unread status for scheduled job orders.
  String _readStorageKey([String? email]) {
    final normalized = (email ?? technicianEmail.value)?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return AppConstants.keyReadJobIds;
    }
    return '${AppConstants.keyReadJobIds}_$normalized';
  }

  bool isJobRead(int jobId) => readJobIds.value.contains(jobId);

  bool isJobReadPeek(int jobId) => readJobIds.peek().contains(jobId);

  bool isJobUnread(JobOrderDto job) =>
      job.jobStatus == JobStatus.scheduled &&
      !readJobIds.value.contains(job.id);

  void markJobAsRead(int jobId) {
    final current = readJobIds.peek();
    if (current.contains(jobId)) return;
    final updated = {...current, jobId};
    readJobIds.value = updated;
    unawaited(_storage.writeIntSet(_readStorageKey(), updated));
  }

  void markJobAsUnread(int jobId) {
    final current = readJobIds.peek();
    if (!current.contains(jobId)) return;
    final updated = {...current}..remove(jobId);
    readJobIds.value = updated;
    unawaited(_storage.writeIntSet(_readStorageKey(), updated));
  }

  Future<void> restoreReadIds() async {
    final epoch = ++_readLoadEpoch;
    final key = _readStorageKey();
    final stored = await _storage.readIntSet(key);
    if (epoch != _readLoadEpoch) return;
    if (stored.isEmpty) return;
    final current = readJobIds.peek();
    final merged = {...stored, ...current};
    if (merged.length != current.length) {
      readJobIds.value = merged;
    }
    if (current.any((id) => !stored.contains(id))) {
      unawaited(_storage.writeIntSet(key, merged));
    }
  }

  late final ReadonlySignal<int> activatedCount =
      computed(() => _countOf(JobStatus.activated));

  /// Jobs whose on-site visit failed or needs rescheduling. Not a tab, but
  /// surfaced so these stay visible rather than hiding under "All".
  late final ReadonlySignal<int> siteExceptionCount = computed(
    () => allJobs.value.where((j) => j.siteException != null).length,
  );

  late final ReadonlySignal<int> unsyncedCount = computed(
    () => allJobs.value.where((j) => !j.isSynced).length,
  );

  /// Every finished job (Activated or Completed) assigned to the signed-in
  /// technician, newest first.
  ///
  /// Once the email is known the list is scoped to it here as well as on the
  /// server, so rows another technician's pull left in the cache never show.
  /// While it is unknown everything cached is shown rather than nothing.
  late final ReadonlySignal<List<JobOrderDto>> assignedJobs = computed(() {
    final email = technicianEmail.value?.trim() ?? '';
    final history = allJobs.value
        .where((j) =>
            (j.isActivated || j.isCompleted) &&
            (email.isEmpty || j.isAssignedTo(email)))
        .toList();

    history.sort((a, b) {
      final ad = a.historyDate;
      final bd = b.historyDate;
      if (ad == null && bd == null) return b.id.compareTo(a.id);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final byDate = bd.compareTo(ad);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return history;
  });

  /// Distinct cities across the technician's history, for the area filter.
  late final ReadonlySignal<List<String>> historyCities = computed(() {
    final cities = <String>{
      for (final j in assignedJobs.value)
        if (j.city?.trim().isNotEmpty == true) j.city!.trim(),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return cities;
  });

  /// Half-open [start, end) window for [range], or nulls for all time.
  (DateTime?, DateTime?) _windowFor(HistoryRange range) {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    return switch (range) {
      HistoryRange.all => (null, null),
      HistoryRange.today => (today, today.add(const Duration(days: 1))),
      HistoryRange.week => (
          today.subtract(Duration(days: today.weekday - DateTime.monday)),
          today.add(const Duration(days: 1)),
        ),
      HistoryRange.custom => (
          historyRangeStart.value,
          historyRangeEnd.value?.add(const Duration(days: 1)),
        ),
    };
  }

  bool _inWindow(JobOrderDto job, (DateTime?, DateTime?) window) {
    final (start, end) = window;
    if (start == null && end == null) return true;
    final d = job.historyDate;
    if (d == null) return false;
    if (start != null && d.isBefore(start)) return false;
    if (end != null && !d.isBefore(end)) return false;
    return true;
  }

  /// [assignedJobs] narrowed by the status filter, date window, city and search box.
  late final ReadonlySignal<List<JobOrderDto>> historyJobs = computed(() {
    final status = historyStatus.value;
    final window = _windowFor(historyRange.value);
    final city = historyCity.value?.trim().toLowerCase();
    final query = historySearch.value.trim().toLowerCase();

    return assignedJobs.value.where((job) {
      if (status == HistoryStatusFilter.activated && !job.isActivated) {
        return false;
      }
      if (status == HistoryStatusFilter.completed && !job.isCompleted) {
        return false;
      }
      if (!_inWindow(job, window)) return false;
      if (city != null &&
          city.isNotEmpty &&
          (job.city ?? '').trim().toLowerCase() != city) {
        return false;
      }
      if (query.isEmpty) return true;
      return job.ticketNumber.toLowerCase().contains(query) ||
          job.customerName.toLowerCase().contains(query) ||
          job.address.toLowerCase().contains(query) ||
          (job.barangay ?? '').toLowerCase().contains(query) ||
          (job.city ?? '').toLowerCase().contains(query);
    }).toList();
  });

  late final ReadonlySignal<int> historyTotalCount =
      computed(() => assignedJobs.value.length);

  late final ReadonlySignal<int> historyActivatedCount = computed(
    () => assignedJobs.value.where((j) => j.isActivated).length,
  );

  late final ReadonlySignal<int> historyCompletedCount = computed(
    () => assignedJobs.value.where((j) => j.isCompleted).length,
  );

  int _historyCountIn(HistoryRange range) {
    final window = _windowFor(range);
    return assignedJobs.value.where((j) => _inWindow(j, window)).length;
  }

  late final ReadonlySignal<int> historyThisWeekCount =
      computed(() => _historyCountIn(HistoryRange.week));

  /// Pipe the PowerSync reactive stream into allJobs signal
  void _initDriftStream() {
    _driftSubscription?.cancel();
    _driftSubscription = repository.watchJobs().listen((jobs) {
      final email = technicianEmail.value?.trim();

      /*
      // Prune cached IDs if jobs were removed from local cache
      _knownJobIds.retainAll(jobs.map((j) => j.id));
      _myAssignedJobIds.retainAll(jobs.map((j) => j.id));
      */
      // Gene - Oct 3, 2026: Retain _knownJobIds cumulatively to eliminate phantom alert storms and haptic triggers when cached jobs re-emit.
      _myAssignedJobIds.retainAll(jobs.map((j) => j.id));

      if (!_hasInitialSnapshot ||
          loadPhase.value == DataLoadPhase.downloading ||
          loadPhase.value == DataLoadPhase.skeleton) {
        if (jobs.isNotEmpty || loadPhase.value == DataLoadPhase.ready) {
          _hasInitialSnapshot = true;
        }
        _knownJobIds.addAll(jobs.map((j) => j.id));
        for (final job in jobs) {
          final matchesTech =
              email == null || email.isEmpty || job.isAssignedTo(email);
          if (matchesTech) {
            _myAssignedJobIds.add(job.id);
          }
        }
        allJobs.value = jobs;
        return;
      }

      // Check for newly added open jobs or newly assigned jobs
      final newOpenJobs = <JobOrderDto>[];
      for (final job in jobs) {
        final matchesTech =
            email == null || email.isEmpty || job.isAssignedTo(email);
        final isNewSynced = !_knownJobIds.contains(job.id);
        final isNewlyAssigned = _knownJobIds.contains(job.id) &&
            !_myAssignedJobIds.contains(job.id) &&
            matchesTech;

        /*
        if (job.isOpen && matchesTech && (isNewSynced || isNewlyAssigned)) {
          newOpenJobs.add(job);
        }
        */
        // Gene - Nov, 20, 2026: Ensure newly reassigned open jobs reset back to unread (NEW) when re-entering the technician queue.
        if (job.isOpen && matchesTech && (isNewSynced || isNewlyAssigned)) {
          if (isNewlyAssigned) {
            markJobAsUnread(job.id);
          }
          newOpenJobs.add(job);
        }

        _knownJobIds.add(job.id);
        if (matchesTech) {
          _myAssignedJobIds.add(job.id);
        } else {
          _myAssignedJobIds.remove(job.id);
        }
      }

      allJobs.value = jobs;

      if (newOpenJobs.isNotEmpty) {
        _triggerAlert(newOpenJobs.last);
      }
    });
  }

  void _triggerAlert(JobOrderDto job) {
    newJobAlert.value = job;
    if (onNewJobAlert != null) {
      onNewJobAlert!(job);
    } else {
      /*
      try {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
      } catch (_) {
        // Ignored when platform channels are unavailable (e.g. headless tests)
      }
      */
      /*
      // Gene - Oct 3, 2026: Added .catchError to unawaited SystemSound and HapticFeedback calls to prevent unhandled async exceptions in headless test environments.
      try {
        SystemSound.play(SystemSoundType.alert).catchError((_) {});
        HapticFeedback.heavyImpact().catchError((_) {});
      } catch (_) {
        // Ignored when platform channels are unavailable (e.g. headless tests)
      }
      */
      // Gene - Oct 3, 2026: Trigger audible chime alert and haptics via SoundService for newly added or assigned job orders.
      SoundService.instance.playAlertSound().catchError((_) {});
    }
  }

  /// Dismisses active top banner alert
  void dismissAlert() {
    newJobAlert.value = null;
  }

  /// Pull scheduled jobs and the technician's activated history from the
  /// server and refresh the cache.
  ///
  /// With [initial] set, and only when the local database holds nothing yet, the screen is
  /// walked through the download indicator and a brief skeleton pass before
  /// the hydrated local rows are revealed.
  Future<void> fetchRemote({bool initial = false}) async {
    final showPhases = initial && allJobs.value.isEmpty;
    if (showPhases) loadPhase.value = DataLoadPhase.downloading;
    isRefreshing.value = true;
    try {
      // Gene - Nov, 28, 2026: In replicated mode, manual refresh reconnects PowerSync to force an immediate credential & stream pull; in REST mode, retry profile lookup if email is missing.
      if (PowerSyncService.instance.isInitialized &&
          PowerSyncService.instance.isReplicatedMode) {
        await PowerSyncService.instance.reconnect();
      } else {
        if ((technicianEmail.value?.trim().isEmpty ?? true)) {
          await AuthSignals.instance.refreshProfile();
          final refreshedEmail =
              AuthSignals.instance.currentUser.value?.email.trim() ?? '';
          if (refreshedEmail.isNotEmpty) {
            setTechnicianEmail(refreshedEmail);
          }
        }
        if (repository.syncWorker.pendingCount.value > 0) {
          await repository.syncWorker.syncPendingJobs();
        }
      }
      await repository.fetchRemoteJobs(technicianEmail: technicianEmail.value);
    } finally {
      isRefreshing.value = false;
      if (showPhases) {
        loadPhase.value = DataLoadPhase.skeleton;
        await Future<void>.delayed(const Duration(milliseconds: 900));
        loadPhase.value = DataLoadPhase.ready;
      }
    }
  }

  /// Mark a job Completed, stamping it with the signed-in technician so it
  /// appears in history. Already-completed jobs are left alone.
  Future<SyncResult?> completeJob(JobOrderDto job) async {
    if (job.isCompleted) return null;
    return repository.completeJob(job.id,
        technicianEmail: technicianEmail.value);
  }

  /// Mark a job Activated, stamping it with the signed-in technician so it
  /// appears in their history. Already-activated jobs are left alone.
  Future<void> activateJob(JobOrderDto job) async {
    if (job.isActivated) return;
    await repository.activateJob(job.id,
        technicianEmail: technicianEmail.value);
  }

  // Gene - Nov, 25, 2026: Start/Finish work timing actions on Job Orders; returns null when synced or a short warning when saved locally offline.
  // Gene - Nov, 26, 2026: Expose timingHistory DAO and resolve technician ID/name via shared helpers.
  WorkTimingHistoryDao? get timingHistory => repository.timingHistory;

  /*
  String _resolveTechId([String? override]) {
    final explicit = override?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final user = AuthSignals.instance.currentUser.value;
    if (user != null) {
      if (user.id > 0) return user.id.toString();
      if (user.email.trim().isNotEmpty) return user.email.trim();
    }
    final email = technicianEmail.value?.trim();
    if (email != null && email.isNotEmpty) return email;
    return '0';
  }
  */
  String _resolveTechId([String? override]) => resolveTimingUserId(
        override: override,
        fallbackEmail: technicianEmail.value,
      );

  String? _resolveTechName() =>
      resolveTimingUserName(fallbackEmail: technicianEmail.value);

  /*
  Future<String?> startJob(JobOrderDto job, {String? techId}) async {
    if (busyTimingJobIds.value.contains(job.id)) return null;
    busyTimingJobIds.value = {...busyTimingJobIds.value, job.id};
    try {
      await repository.startJobTiming(job.id, techId: _resolveTechId(techId));
      return null;
    } catch (e) {
      return 'Started locally · sync pending ($e)';
    } finally {
      busyTimingJobIds.value = {...busyTimingJobIds.value}..remove(job.id);
    }
  }
  */
  // Gene - Nov, 26, 2026: Guard startJob against starting a second Job Order while another Job Order or Service Order is already active.
  Future<String?> startJob(
    JobOrderDto job, {
    String? techId,
    bool hasOtherActiveOrder = false,
  }) async {
    if (busyTimingJobIds.value.contains(job.id)) return null;
    final currentActive = activeStartedJob.value;
    /*
    if (hasOtherActiveOrder ||
        (currentActive != null && currentActive.id != job.id)) {
      return 'Finish the active order before starting another.';
    }
    */
    // Gene - Nov, 28, 2026: Also block rapid concurrent Start taps on another Job Order while an in-flight startJob DAO write is still pending.
    final hasOtherBusyStart = busyTimingJobIds.value.any((id) => id != job.id);
    if (hasOtherActiveOrder ||
        hasOtherBusyStart ||
        (currentActive != null && currentActive.id != job.id)) {
      return 'Finish the active order before starting another.';
    }
    busyTimingJobIds.value = {...busyTimingJobIds.value, job.id};
    try {
      /*
      await repository.startJobTiming(job.id, techId: _resolveTechId(techId));
      */
      // Gene - Nov, 26, 2026: Forward userName to startJobTiming for timing history attribution.
      await repository.startJobTiming(
        job.id,
        techId: _resolveTechId(techId),
        userName: _resolveTechName(),
      );
      return null;
    } catch (e) {
      return 'Started locally · sync pending ($e)';
    } finally {
      busyTimingJobIds.value = {...busyTimingJobIds.value}..remove(job.id);
    }
  }

  Future<String?> finishJob(JobOrderDto job, {String? techId}) async {
    if (busyTimingJobIds.value.contains(job.id)) return null;
    busyTimingJobIds.value = {...busyTimingJobIds.value, job.id};
    try {
      /*
      await repository.finishJobTiming(job, techId: _resolveTechId(techId));
      */
      // Gene - Nov, 26, 2026: Forward userName to finishJobTiming for timing history attribution.
      await repository.finishJobTiming(
        job,
        techId: _resolveTechId(techId),
        userName: _resolveTechName(),
      );
      return null;
    } catch (e) {
      return 'Finished locally · sync pending ($e)';
    } finally {
      busyTimingJobIds.value = {...busyTimingJobIds.value}..remove(job.id);
    }
  }

  /// Update tab filter
  void setFilter(String filter) {
    activeFilter.value = filter;
  }

  /// Update search keyword
  void setSearch(String query) {
    searchQuery.value = query;
  }

  /// The signed-in technician's email, which scopes the job history.
  /*
  void setTechnicianEmail(String? email) {
    if (technicianEmail.value != email) {
      _hasInitialSnapshot = false;
      _knownJobIds.clear();
      _myAssignedJobIds.clear();
      newJobAlert.value = null;
    }
    technicianEmail.value = email;
  }
  */
  // Gene - Nov, 20, 2026: Restore and scope persisted read job IDs whenever the normalized technician email changes.
  void setTechnicianEmail(String? email) {
    final previousNormalized = technicianEmail.value?.trim().toLowerCase();
    final nextNormalized = email?.trim().toLowerCase();
    if (technicianEmail.value != email) {
      _hasInitialSnapshot = false;
      _knownJobIds.clear();
      _myAssignedJobIds.clear();
      newJobAlert.value = null;
    }
    technicianEmail.value = email;
    if (previousNormalized != nextNormalized) {
      if (previousNormalized != null && previousNormalized.isNotEmpty) {
        readJobIds.value = <int>{};
      }
      if (nextNormalized == null || nextNormalized.isEmpty) {
        _readLoadEpoch++;
      } else {
        unawaited(restoreReadIds());
      }
    }
  }

  /// Apply a date window. [start] and [end] (inclusive dates) are only used
  /// for [HistoryRange.custom].
  void setHistoryRange(HistoryRange range, {DateTime? start, DateTime? end}) {
    if (range == HistoryRange.custom) {
      historyRangeStart.value =
          start == null ? null : DateTime(start.year, start.month, start.day);
      historyRangeEnd.value =
          end == null ? null : DateTime(end.year, end.month, end.day);
    }
    historyRange.value = range;
  }

  /// Restrict the history to one city, or null for every area.
  void setHistoryCity(String? city) {
    historyCity.value = (city == null || city.trim().isEmpty) ? null : city;
  }

  /// Restrict the history to one status, or all history.
  void setHistoryStatus(HistoryStatusFilter status) {
    historyStatus.value = status;
  }

  void clearHistoryFilters() {
    historyStatus.value = HistoryStatusFilter.all;
    historyRange.value = HistoryRange.all;
    historyRangeStart.value = null;
    historyRangeEnd.value = null;
    historyCity.value = null;
    historySearch.value = '';
  }

  void setHistorySearch(String query) {
    historySearch.value = query;
  }

  /// Must be awaited: the database stream subscription has to be fully torn down
  /// before the database can be closed, otherwise close() blocks forever.
  Future<void> dispose() async {
    await _driftSubscription?.cancel();
    _driftSubscription = null;
  }
}
