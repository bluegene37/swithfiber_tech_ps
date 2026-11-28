import 'dart:async';
// Gene - Nov, 28, 2026: Added convert/io, sqlite_async, PendingAttachmentsDao, and RemotePhotoCacheService for PowerSync v12 disk-backed photos.
import 'dart:convert';
import 'dart:io';
// Gene - Oct 3, 2026: Commented out unused services.dart import now that sound and haptics are encapsulated in SoundService.
// import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:sqlite_async/sqlite_async.dart' show SqliteWriteContext;
// Gene - Nov, 20, 2026: Added app_constants and secure_storage_service imports for persisting read service order IDs.
import '../../../core/constants/app_constants.dart';
// Gene - Nov, 28, 2026: Added NetworkExceptions import for 403 NOT_ASSIGNED handling.
import '../../../core/network/network_exceptions.dart';
// Gene - Nov, 23, 2026: Added LocationService for Nearest-first repair sorting.
import '../../../core/services/location_service.dart';
import '../../../core/services/remote_photo_cache_service.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/database/daos/pending_attachments_dao.dart';
import '../../../core/database/daos/service_orders_dao.dart';
import '../../../core/database/daos/sync_error_logs_dao.dart';
// Gene - Nov, 26, 2026: Added WorkTimingHistoryDao and WorkTimingEntry imports for logging Service Order Start/Stop sessions.
import '../../../core/database/daos/work_timing_history_dao.dart';
import '../../../core/database/models/pending_attachment.dart';
import '../../../core/database/models/work_timing_entry.dart';
import '../../../core/services/photo_storage_service.dart';
import '../../../core/storage/secure_storage_service.dart';
// Gene - Nov, 27, 2026: Added PowerSyncService import for replicated mode awareness.
import '../../../core/sync/powersync_service.dart';
// Gene - Nov, 25, 2026: Added shared work timing helpers and AuthSignals for Start/Finish timing tracking.
import '../../../core/widgets/work_timing_bar.dart';
import '../../auth/signals/auth_signals.dart';
import '../models/service_order_images_model.dart';
import '../models/service_order_model.dart';
import '../services/service_orders_api.dart';
import '../services/service_orders_sync_worker.dart';

// Gene - Nov, 23, 2026: Added sort mode for Repairs queue (Priority vs Nearest GPS).
enum ServiceOrderSort { priority, nearest }

/// Signals state container for Service Orders (repairs, maintenance, swaps).
/// Connects reactive local persistence and the background sync worker.
/*
class ServiceOrdersSignals {
  final ServiceOrdersApi api;
  final ServiceOrdersDao? dao;
  late final ServiceOrdersSyncWorker? syncWorker;
  StreamSubscription<List<ServiceOrderDto>>? _driftSubscription;

  ServiceOrdersSignals({
    ServiceOrdersApi? api,
    this.dao,
  }) : api = api ?? ServiceOrdersApi() {
    if (dao != null) {
      syncWorker = ServiceOrdersSyncWorker(dao!, api: this.api);
      _initDriftStream();
    } else {
      syncWorker = null;
    }
  }

  void _initDriftStream() {
    if (dao == null) return;
    _driftSubscription?.cancel();
    _driftSubscription = dao!.watchAllOrders().listen((rows) {
      allOrders.value = rows;
    });
  }
*/
// Gene - Oct, 1, 2026: Added onNewOrderAlert callback, newOrderAlert signal, and reactive new service order detection with sound/haptic triggers.
class ServiceOrdersSignals {
  final ServiceOrdersApi api;
  final ServiceOrdersDao? dao;
  late final ServiceOrdersSyncWorker? syncWorker;

  /// Optional notification hook for audio/vibration; injectable for tests.
  final void Function(ServiceOrderDto order)? onNewOrderAlert;

  StreamSubscription<List<ServiceOrderDto>>? _driftSubscription;
  // Gene - Nov, 20, 2026: Added storage dependency for persisting read service order IDs across restarts.
  final SecureStorageService _storage;

  /*
  ServiceOrdersSignals({
    ServiceOrdersApi? api,
    this.dao,
    this.onNewOrderAlert,
  }) : api = api ?? ServiceOrdersApi() {
    if (dao != null) {
      syncWorker = ServiceOrdersSyncWorker(dao!, api: this.api);
      _initDriftStream();
    } else {
      syncWorker = null;
    }
  }
  */
  /*
  // Gene - Nov, 20, 2026: Added optional storage parameter to constructor for read/unread badge persistence and testing.
  ServiceOrdersSignals({
    ServiceOrdersApi? api,
    this.dao,
    this.onNewOrderAlert,
    SecureStorageService? storage,
  })  : api = api ?? ServiceOrdersApi(),
        _storage = storage ?? SecureStorageService.instance {
    if (dao != null) {
      syncWorker = ServiceOrdersSyncWorker(dao!, api: this.api);
      _initDriftStream();
    } else {
      syncWorker = null;
    }
  }
  */
  // Gene - Nov, 23, 2026: Added optional errorLog parameter passed into ServiceOrdersSyncWorker.
  // Gene - Nov, 26, 2026: Added optional timingHistory parameter for recording Start/Stop sessions.
  final WorkTimingHistoryDao? timingHistory;
  final PendingAttachmentsDao? pendingAttachments;
  final Future<T> Function<T>(Future<T> Function(SqliteWriteContext tx))?
      runInTransaction;
  // Gene - Nov, 27, 2026: Flag callback indicating live PowerSync replication is active.
  final bool Function() _isReplicatedMode;

  // Gene - Nov, 28, 2026: Accept optional PendingAttachmentsDao and transaction runner for atomic photo queuing.
  ServiceOrdersSignals({
    ServiceOrdersApi? api,
    this.dao,
    this.onNewOrderAlert,
    SecureStorageService? storage,
    SyncErrorLogsDao? errorLog,
    this.timingHistory,
    this.pendingAttachments,
    this.runInTransaction,
    bool Function()? isReplicatedMode,
  })  : api = api ?? ServiceOrdersApi(),
        _storage = storage ?? SecureStorageService.instance,
        _isReplicatedMode = isReplicatedMode ??
            (() => PowerSyncService.instance.isReplicatedMode) {
    if (dao != null) {
      /*
      syncWorker = ServiceOrdersSyncWorker(
        dao!,
        api: this.api,
        errorLog: errorLog,
      );
      */
      // Gene - Nov, 25, 2026: Pass clearImagesCache callback so synced repairs invalidate stale cached photos.
      syncWorker = ServiceOrdersSyncWorker(
        dao!,
        api: this.api,
        errorLog: errorLog,
        onOrderSynced: clearImagesCache,
      );
      _initDriftStream();
    } else {
      syncWorker = null;
    }
  }

  // Gene - Nov, 25, 2026: In-memory cache and fetch helper for GET /api/ServiceOrders/{id}/GetServiceOrderImage.
  final Map<int, ServiceOrderImagesDto> _imagesCache = {};
  // Gene - Nov, 28, 2026: Track 403 NOT_ASSIGNED service order IDs reactively and expose paginated local history query.
  final notAssignedOrderIds = signal<Set<int>>(<int>{});

  bool isOrderNotAssigned(int orderId) =>
      notAssignedOrderIds.value.contains(orderId);

  void _markOrderNotAssigned(int orderId) {
    if (!notAssignedOrderIds.peek().contains(orderId)) {
      notAssignedOrderIds.value = {...notAssignedOrderIds.peek(), orderId};
    }
  }

  Future<ServiceOrderDto?> fetchRemoteOrderById(int orderId) async {
    if (isOrderNotAssigned(orderId)) return null;
    try {
      return await api.fetchServiceOrderById(orderId);
    } on ApiException catch (e) {
      if (e.isNotAssigned) {
        clearImagesCache(orderId);
        _markOrderNotAssigned(orderId);
        return null;
      }
      rethrow;
    }
  }

  Future<List<ServiceOrderDto>> getHistoryOrdersPage({
    int limit = 50,
    int offset = 0,
    String? technicianEmail,
  }) async {
    final activeDao = dao;
    if (activeDao == null) return const [];
    return activeDao.getHistoryOrdersPage(
      limit: limit,
      offset: offset,
      technicianEmail: technicianEmail ?? this.technicianEmail.value,
    );
  }

  /// Clear in-memory and disk service order photo caches (for tests, sync, or manual refresh).
  void clearImagesCache([int? id]) {
    if (id != null) {
      _imagesCache.remove(id);
    } else {
      _imagesCache.clear();
    }
    unawaited(
      RemotePhotoCacheService.instance.invalidate('service_orders', id),
    );
  }

  /// Fetches photo proofs and signature for a Service Order from GET /api/ServiceOrders/{id}/GetServiceOrderImage.
  Future<ServiceOrderImagesDto?> getServiceOrderImages(
    int orderId, {
    bool forceRefresh = false,
  }) async {
    if (isOrderNotAssigned(orderId) && !forceRefresh) {
      return null;
    }
    // Gene - Nov, 28, 2026: Lazy disk cache + pending_attachments overlay for offline Service Order photo previews.
    ServiceOrderImagesDto? baseDto;
    if (forceRefresh) {
      _imagesCache.remove(orderId);
      if (notAssignedOrderIds.peek().contains(orderId)) {
        notAssignedOrderIds.value = {...notAssignedOrderIds.peek()}
          ..remove(orderId);
      }
    } else if (_imagesCache.containsKey(orderId)) {
      baseDto = _imagesCache[orderId];
    } else {
      final diskJson = await RemotePhotoCacheService.instance
          .readCachedJson('service_orders', orderId);
      if (diskJson != null) {
        baseDto = ServiceOrderImagesDto.fromJson(diskJson);
        _imagesCache[orderId] = baseDto;
      }
    }

    if (baseDto == null || forceRefresh) {
      try {
        final data = await api.fetchServiceOrderImages(orderId);
        if (data != null) {
          final dto = ServiceOrderImagesDto.fromJson(data);
          baseDto = dto;
          _imagesCache[orderId] = dto;
          unawaited(
            RemotePhotoCacheService.instance
                .writeCachedJson('service_orders', orderId, dto.toJson()),
          );
        }
      } on ApiException catch (e) {
        if (e.isNotAssigned) {
          clearImagesCache(orderId);
          _markOrderNotAssigned(orderId);
          return null;
        }
        if (baseDto == null) {
          final diskJson = await RemotePhotoCacheService.instance
              .readCachedJson('service_orders', orderId);
          if (diskJson != null) {
            baseDto = ServiceOrderImagesDto.fromJson(diskJson);
          }
        }
      } catch (_) {
        if (baseDto == null) {
          final diskJson = await RemotePhotoCacheService.instance
              .readCachedJson('service_orders', orderId);
          if (diskJson != null) {
            baseDto = ServiceOrderImagesDto.fromJson(diskJson);
          }
        }
      }
    }

    final merged = await _overlayPendingServiceOrderImages(orderId, baseDto);
    if (merged != null) {
      _imagesCache[orderId] = merged;
    }
    return merged;
  }

  Future<ServiceOrderImagesDto?> _overlayPendingServiceOrderImages(
    int orderId,
    ServiceOrderImagesDto? baseDto,
  ) async {
    final attDao = pendingAttachments;
    if (attDao == null) return baseDto;
    final items = await attDao.getAllForEntity('service_orders', '$orderId');
    if (items.isEmpty) return baseDto;

    var sig = baseDto?.clientSignature;
    var img1 = baseDto?.image1;
    var img2 = baseDto?.image2;
    var img3 = baseDto?.image3;
    var hf = baseDto?.houseFrontPicture;

    Future<ServiceOrderImageFileDto?> decodeAttachment(
      PendingAttachment att,
    ) async {
      if (att.deleteFlag) return null;
      final path = att.filePath?.trim();
      if (path == null || path.isEmpty) return null;
      try {
        final f = File(path);
        if (!await f.exists()) return null;
        final bytes = await f.readAsBytes();
        if (bytes.isEmpty) return null;
        final isPng = path.toLowerCase().endsWith('.png') ||
            att.slotName == 'client_signature';
        return ServiceOrderImageFileDto(
          fileContents: base64Encode(bytes),
          contentType: isPng ? 'image/png' : 'image/jpeg',
          fileDownloadName: '${att.slotName}.${isPng ? 'png' : 'jpg'}',
        );
      } catch (_) {
        return null;
      }
    }

    for (final att in items) {
      final overrideFile = await decodeAttachment(att);
      switch (att.slotName) {
        case 'client_signature':
          sig = att.deleteFlag ? null : (overrideFile ?? sig);
          break;
        case 'image1':
          img1 = att.deleteFlag ? null : (overrideFile ?? img1);
          break;
        case 'image2':
          img2 = att.deleteFlag ? null : (overrideFile ?? img2);
          break;
        case 'image3':
          img3 = att.deleteFlag ? null : (overrideFile ?? img3);
          break;
        case 'house_front_picture':
          hf = att.deleteFlag ? null : (overrideFile ?? hf);
          break;
      }
    }

    return ServiceOrderImagesDto(
      clientSignature: sig,
      image1: img1,
      image2: img2,
      image3: img3,
      houseFrontPicture: hf,
    );
  }

  /// Surfaced when a new open Service Order is synced or assigned to the technician.
  final newOrderAlert = signal<ServiceOrderDto?>(null);

  bool _hasInitialSnapshot = false;
  final Set<int> _knownOrderIds = <int>{};
  final Set<int> _myAssignedOrderIds = <int>{};

  // Gene - Nov, 20, 2026: Track read service order IDs per technician session so Repairs bubble only counts unread tickets.
  final readOrderIds = signal<Set<int>>(<int>{});
  int _readLoadEpoch = 0;

  void _initDriftStream() {
    if (dao == null) return;
    _driftSubscription?.cancel();
    _driftSubscription = dao!.watchAllOrders().listen((rows) {
      final email = technicianEmail.value?.trim();

      /*
      // Prune cached IDs if orders were removed from local cache
      _knownOrderIds.retainAll(rows.map((o) => o.id));
      _myAssignedOrderIds.retainAll(rows.map((o) => o.id));
      */
      // Gene - Oct 3, 2026: Retain _knownOrderIds cumulatively to eliminate phantom alert storms when cached repair orders re-emit.
      _myAssignedOrderIds.retainAll(rows.map((o) => o.id));

      if (!_hasInitialSnapshot) {
        _hasInitialSnapshot = true;
        _knownOrderIds.addAll(rows.map((o) => o.id));
        for (final order in rows) {
          final matchesTech =
              email == null || email.isEmpty || order.isAssignedTo(email);
          if (matchesTech) {
            _myAssignedOrderIds.add(order.id);
          }
        }
        allOrders.value = rows;
        return;
      }

      // Check for newly added open orders or newly assigned orders
      final newOpenOrders = <ServiceOrderDto>[];
      for (final order in rows) {
        final matchesTech =
            email == null || email.isEmpty || order.isAssignedTo(email);
        final isNewSynced = !_knownOrderIds.contains(order.id);
        final isNewlyAssigned = _knownOrderIds.contains(order.id) &&
            !_myAssignedOrderIds.contains(order.id) &&
            matchesTech;

        /*
        if (order.isOpen && matchesTech && (isNewSynced || isNewlyAssigned)) {
          newOpenOrders.add(order);
        }
        */
        // Gene - Nov, 20, 2026: Ensure newly reassigned open service orders reset back to unread (NEW) when re-entering the technician queue.
        if (order.isOpen && matchesTech && (isNewSynced || isNewlyAssigned)) {
          if (isNewlyAssigned) {
            markOrderAsUnread(order.id);
          }
          newOpenOrders.add(order);
        }

        _knownOrderIds.add(order.id);
        if (matchesTech) {
          _myAssignedOrderIds.add(order.id);
        } else {
          _myAssignedOrderIds.remove(order.id);
        }
      }

      allOrders.value = rows;

      if (newOpenOrders.isNotEmpty) {
        _triggerAlert(newOpenOrders.last);
      }
    });
  }

  void _triggerAlert(ServiceOrderDto order) {
    newOrderAlert.value = order;
    if (onNewOrderAlert != null) {
      onNewOrderAlert!(order);
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
      // Gene - Oct 3, 2026: Added .catchError to unawaited SystemSound and HapticFeedback futures to prevent unhandled async exceptions in headless test environments.
      try {
        SystemSound.play(SystemSoundType.alert).catchError((_) {});
        HapticFeedback.heavyImpact().catchError((_) {});
      } catch (_) {
        // Ignored when platform channels are unavailable (e.g. headless tests)
      }
      */
      // Gene - Oct 3, 2026: Trigger audible chime alert and haptics via SoundService for newly added or assigned service orders.
      SoundService.instance.playAlertSound().catchError((_) {});
    }
  }

  /// Dismisses active top banner alert
  void dismissAlert() {
    newOrderAlert.value = null;
  }

  /// Scopes the service orders to technician and resets alert snapshot caches if changed
  /*
  void setTechnicianEmail(String? email) {
    if (technicianEmail.value != email) {
      _hasInitialSnapshot = false;
      _knownOrderIds.clear();
      _myAssignedOrderIds.clear();
      newOrderAlert.value = null;
    }
    technicianEmail.value = email;
  }
  */
  // Gene - Nov, 20, 2026: Restore and scope persisted read service order IDs whenever the normalized technician email changes.
  void setTechnicianEmail(String? email) {
    final previousNormalized = technicianEmail.value?.trim().toLowerCase();
    final nextNormalized = email?.trim().toLowerCase();
    if (technicianEmail.value != email) {
      _hasInitialSnapshot = false;
      _knownOrderIds.clear();
      _myAssignedOrderIds.clear();
      newOrderAlert.value = null;
    }
    technicianEmail.value = email;
    if (previousNormalized != nextNormalized) {
      if (previousNormalized != null && previousNormalized.isNotEmpty) {
        readOrderIds.value = <int>{};
      }
      if (nextNormalized == null || nextNormalized.isEmpty) {
        _readLoadEpoch++;
      } else {
        unawaited(restoreReadIds());
      }
    }
  }

  void dispose() {
    _driftSubscription?.cancel();
  }

  /// All service orders currently loaded
  final allOrders = signal<List<ServiceOrderDto>>([]);

  /// Whether a sync request is in-flight
  final isSyncing = signal<bool>(false);

  /// Error message from last sync attempt if any
  final syncError = signal<String?>(null);

  /// Search query (subscriber name, account number, address)
  final searchQuery = signal<String>('');

  /// Filter by priority ('All', 'Urgent', 'High', 'Normal')
  final priorityFilter = signal<String>('All');

  /// Filter by concern ('All', 'Pullout', 'No Connection', 'High Loss', 'Relocation')
  final concernFilter = signal<String>('All');

  /// Filter to only tickets assigned to the logged-in technician
  final onlyAssignedToMe = signal<bool>(true);

  /// Logged-in technician email for matching
  final technicianEmail = signal<String?>(null);

  // Gene - Nov, 23, 2026: Sort mode signal (Priority vs Nearest) and base count before filters.
  final sortMode = signal<ServiceOrderSort>(ServiceOrderSort.priority);

  void setSortMode(ServiceOrderSort mode) => sortMode.value = mode;

  /*
  late final ReadonlySignal<int> baseOrdersCount = computed(() {
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();
    if (!onlyMe || email == null || email.isEmpty) {
      return allOrders.value.length;
    }
    return allOrders.value.where((o) => o.isAssignedTo(email)).length;
  });
  */
  // Gene - Nov, 28, 2026: Exclude closed/completed Service Orders from baseOrdersCount so active Repairs counts match filteredOrders.
  late final ReadonlySignal<int> baseOrdersCount = computed(() {
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();
    return allOrders.value.where((o) {
      if (!o.isOpen) return false;
      if (onlyMe &&
          email != null &&
          email.isNotEmpty &&
          !o.isAssignedTo(email)) {
        return false;
      }
      return true;
    }).length;
  });

  /// Total count of service orders visible to technician
  late final ReadonlySignal<int> totalCount =
      computed(() => filteredOrders.value.length);

  // Gene - Nov, 20, 2026: Count only unread open service orders scoped to the technician for the Repairs navigation bubble and launcher badge.
  late final ReadonlySignal<int> unreadCount = computed(() {
    final read = readOrderIds.value;
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();
    return allOrders.value.where((order) {
      if (!order.isOpen) return false;
      if (onlyMe &&
          (email != null && email.isNotEmpty) &&
          !order.isAssignedTo(email)) {
        return false;
      }
      return !read.contains(order.id);
    }).length;
  });

  // Gene - Nov, 20, 2026: Helpers to inspect, mutate, and persist read/unread status for service orders.
  String _readStorageKey([String? email]) {
    final normalized = (email ?? technicianEmail.value)?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return AppConstants.keyReadServiceOrderIds;
    }
    return '${AppConstants.keyReadServiceOrderIds}_$normalized';
  }

  bool isOrderRead(int orderId) => readOrderIds.value.contains(orderId);

  bool isOrderReadPeek(int orderId) => readOrderIds.peek().contains(orderId);

  bool isOrderUnread(ServiceOrderDto order) =>
      order.isOpen && !readOrderIds.value.contains(order.id);

  void markOrderAsRead(int orderId) {
    final current = readOrderIds.peek();
    if (current.contains(orderId)) return;
    final updated = {...current, orderId};
    readOrderIds.value = updated;
    unawaited(_storage.writeIntSet(_readStorageKey(), updated));
  }

  void markOrderAsUnread(int orderId) {
    final current = readOrderIds.peek();
    if (!current.contains(orderId)) return;
    final updated = {...current}..remove(orderId);
    readOrderIds.value = updated;
    unawaited(_storage.writeIntSet(_readStorageKey(), updated));
  }

  Future<void> restoreReadIds() async {
    final epoch = ++_readLoadEpoch;
    final key = _readStorageKey();
    final stored = await _storage.readIntSet(key);
    if (epoch != _readLoadEpoch) return;
    if (stored.isEmpty) return;
    final current = readOrderIds.peek();
    final merged = {...stored, ...current};
    if (merged.length != current.length) {
      readOrderIds.value = merged;
    }
    if (current.any((id) => !stored.contains(id))) {
      unawaited(_storage.writeIntSet(key, merged));
    }
  }

  // Gene - Nov, 28, 2026: Expose completed/closed Service Orders for the on-demand assigned_service_orders_history view.
  late final ReadonlySignal<List<ServiceOrderDto>> completedOrders =
      computed(() {
    final query = searchQuery.value.trim().toLowerCase();
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();
    return allOrders.value.where((order) {
      if (order.isOpen) return false;
      if (onlyMe &&
          (email != null && email.isNotEmpty) &&
          !order.isAssignedTo(email)) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchAccount = order.accountNumber.toLowerCase().contains(query);
        final matchName = order.fullName.toLowerCase().contains(query);
        final matchAddress = order.address.toLowerCase().contains(query);
        final matchConcern = order.concern.toLowerCase().contains(query);
        if (!matchAccount && !matchName && !matchAddress && !matchConcern) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.id.compareTo(a.id));
  });

  /// Urgent service orders count
  late final ReadonlySignal<int> urgentCount =
      computed(() => filteredOrders.value.where((o) => o.isUrgent).length);

  /// Filtered and sorted service orders
  /*
  late final ReadonlySignal<List<ServiceOrderDto>> filteredOrders =
      computed(() {
    final query = searchQuery.value.trim().toLowerCase();
    final priority = priorityFilter.value.trim().toLowerCase();
    final concern = concernFilter.value.trim().toLowerCase();
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();

    return allOrders.value.where((order) {
      if (onlyMe &&
          (email != null && email.isNotEmpty) &&
          !order.isAssignedTo(email)) {
        return false;
      }

      if (priority != 'all') {
        final orderPriority = (order.priorityLevel ?? '').toLowerCase();
        if (!orderPriority.contains(priority)) {
          return false;
        }
      }

      if (concern != 'all') {
        final orderConcern = order.concern.toLowerCase();
        if (!orderConcern.contains(concern)) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final matchAccount = order.accountNumber.toLowerCase().contains(query);
        final matchName = order.fullName.toLowerCase().contains(query);
        final matchAddress = order.address.toLowerCase().contains(query);
        final matchConcern = order.concern.toLowerCase().contains(query);
        if (!matchAccount && !matchName && !matchAddress && !matchConcern) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        // Urgent first, then by ID descending
        if (a.isUrgent && !b.isUrgent) return -1;
        if (!a.isUrgent && b.isUrgent) return 1;
        return b.id.compareTo(a.id);
      });
  });
  */
  // Gene - Nov, 23, 2026: Support Nearest-first GPS sorting alongside Priority sorting in filteredOrders.
  late final ReadonlySignal<List<ServiceOrderDto>> filteredOrders =
      computed(() {
    final query = searchQuery.value.trim().toLowerCase();
    final priority = priorityFilter.value.trim().toLowerCase();
    final concern = concernFilter.value.trim().toLowerCase();
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();
    final mode = sortMode.value;
    final myPos = LocationService.instance.lastKnownPosition;

    /*
    return allOrders.value.where((order) {
    */
    // Gene - Nov, 28, 2026: Exclude closed/completed orders synced via history streams from the active Repairs queue.
    return allOrders.value.where((order) {
      if (!order.isOpen) return false;
      if (onlyMe &&
          (email != null && email.isNotEmpty) &&
          !order.isAssignedTo(email)) {
        return false;
      }

      if (priority != 'all') {
        final orderPriority = (order.priorityLevel ?? '').toLowerCase();
        if (!orderPriority.contains(priority)) {
          return false;
        }
      }

      if (concern != 'all') {
        final orderConcern = order.concern.toLowerCase();
        if (!orderConcern.contains(concern)) {
          return false;
        }
      }

      if (query.isNotEmpty) {
        final matchAccount = order.accountNumber.toLowerCase().contains(query);
        final matchName = order.fullName.toLowerCase().contains(query);
        final matchAddress = order.address.toLowerCase().contains(query);
        final matchConcern = order.concern.toLowerCase().contains(query);
        if (!matchAccount && !matchName && !matchAddress && !matchConcern) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((a, b) {
        // Gene - Nov, 28, 2026: Group Rescheduled repair tickets at the bottom of the queue in all sort modes.
        if (a.isRescheduled != b.isRescheduled) {
          return a.isRescheduled ? 1 : -1;
        }
        if (mode == ServiceOrderSort.nearest && myPos != null) {
          final aPos = a.latLng;
          final bPos = b.latLng;
          if (aPos != null && bPos != null) {
            final dA = LocationService.instance.distanceBetween(
              startLat: myPos.latitude,
              startLng: myPos.longitude,
              endLat: aPos.latitude,
              endLng: aPos.longitude,
            );
            final dB = LocationService.instance.distanceBetween(
              startLat: myPos.latitude,
              startLng: myPos.longitude,
              endLat: bPos.latitude,
              endLng: bPos.longitude,
            );
            final cmp = dA.compareTo(dB);
            if (cmp != 0) return cmp;
          } else if (aPos != null) {
            return -1;
          } else if (bPos != null) {
            return 1;
          }
        }
        // Urgent first, then by ID descending
        if (a.isUrgent && !b.isUrgent) return -1;
        if (!a.isUrgent && b.isUrgent) return 1;
        return b.id.compareTo(a.id);
      });
  });

  /// Fetch latest service orders from the server scoped to the logged-in technician
  Future<void> fetchRemote({String? technicianEmail}) async {
    /*
    final effectiveEmail =
        (technicianEmail ?? this.technicianEmail.value)?.trim();
    */
    // Gene - Nov, 28, 2026: Retry profile refresh when technicianEmail is missing in REST mode and reconnect PowerSync when manually refreshing in replicated mode.
    var effectiveEmail =
        (technicianEmail ?? this.technicianEmail.value)?.trim();
    /*
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      this.technicianEmail.value = effectiveEmail;
    }
    */
    // Gene - Oct 3, 2026: Used setTechnicianEmail to reset snapshot and assigned caches when scoping to an email on fetch.
    if (effectiveEmail != null && effectiveEmail.isNotEmpty) {
      setTechnicianEmail(effectiveEmail);
    }
    // Gene - Nov, 27, 2026: Downstream rows arrive via PowerSync streaming when replicated mode is active.
    if (_isReplicatedMode()) {
      _imagesCache.clear();
      if (PowerSyncService.instance.isInitialized) {
        await PowerSyncService.instance.reconnect();
      }
      return;
    }
    if (effectiveEmail == null || effectiveEmail.isEmpty) {
      await AuthSignals.instance.refreshProfile();
      final refreshedEmail =
          AuthSignals.instance.currentUser.value?.email.trim() ?? '';
      if (refreshedEmail.isNotEmpty) {
        effectiveEmail = refreshedEmail;
        setTechnicianEmail(refreshedEmail);
      }
    }
    isSyncing.value = true;
    syncError.value = null;

    try {
      /*
      if (syncWorker != null && syncWorker!.pendingCount.value > 0) {
        await syncWorker!.syncPendingOrders();
      }
      */
      // Gene - Nov, 8, 2026: Refresh pendingCount from SQLite before checking so offline-queued service orders always flush on startup/sync.
      if (syncWorker != null) {
        await syncWorker!.refreshPendingCount();
        if (syncWorker!.pendingCount.value > 0) {
          await syncWorker!.syncPendingOrders();
        }
      }
      final remoteList = await api.fetchServiceOrders();
      final scopedList = (effectiveEmail != null && effectiveEmail.isNotEmpty)
          ? remoteList.where((dto) => dto.isAssignedTo(effectiveEmail)).toList()
          : remoteList;

      if (dao != null) {
        final pending = await dao!.getUnsyncedIds();
        // Gene - Nov, 25, 2026: Preserve local Start/Stop timestamps when server GET rows omit them.
        final existingOrders = await dao!.getAllOrders();
        final existingMap = {for (final o in existingOrders) o.id: o};
        final fresh = <ServiceOrderDto>[];
        final keep = <int>{};
        for (final dto in scopedList) {
          keep.add(dto.id);
          if (pending.contains(dto.id)) continue;
          final existing = existingMap[dto.id];
          if (existing != null) {
            /*
            final mergedStart = normalizeTimingTimestamp(dto.startTimestamp) ??
                normalizeTimingTimestamp(existing.startTimestamp);
            final serverStop = normalizeTimingTimestamp(dto.stopTimestamp);
            final localStop = normalizeTimingTimestamp(existing.stopTimestamp);
            final mergedStop = (mergedStart != null &&
                    serverStop != null &&
                    serverStop.isAfter(mergedStart))
                ? serverStop
                : (mergedStart != null &&
                        localStop != null &&
                        localStop.isAfter(mergedStart))
                    ? localStop
                    : (serverStop ?? localStop);
            */
            // Gene - Nov, 26, 2026: Use mergeWorkTimingTimestamps so a restarted local session is never reverted by an older server session.
            final (mergedStart, mergedStop) = mergeWorkTimingTimestamps(
              serverStart: dto.startTimestamp,
              serverEnd: dto.stopTimestamp,
              localStart: existing.startTimestamp,
              localEnd: existing.stopTimestamp,
            );
            fresh.add(dto.copyWith(
              startTimestamp: mergedStart,
              stopTimestamp: mergedStop,
            ));
          } else {
            fresh.add(dto);
          }
        }
        if (fresh.isNotEmpty) {
          await dao!.insertAllOrders(fresh, synced: true);
        }
        /*
        await dao!.deleteSyncedOrdersNotIn(keep);
        */
        /*
        // Gene - Oct 3, 2026: Guard deleteSyncedOrdersNotIn with keep.isNotEmpty to prevent wiping all service orders on empty responses.
        if (keep.isNotEmpty) {
          await dao!.deleteSyncedOrdersNotIn(keep);
        }
        */
        // Gene - Nov, 13, 2026: Always prune synced service orders absent from verified remote list responses (even when keep is empty).
        await dao!.deleteSyncedOrdersNotIn(keep);
        // Gene - Nov, 25, 2026: Evict stale photo cache for refreshed/deleted service orders.
        _imagesCache.removeWhere((id, _) => !pending.contains(id));
      } else {
        allOrders.value = scopedList;
      }
    } catch (e) {
      syncError.value = 'Failed to load service orders: $e';
    } finally {
      isSyncing.value = false;
    }
  }

  /// Update single service order locally and remotely
  Future<bool> submitCompletion(ServiceOrderDto updated) async {
    isSyncing.value = true;
    syncError.value = null;

    // Offload Base64 photos & signatures to disk files before SQLite write
    final photoStorage = PhotoStorageService.instance;
    /*
    final savedSig = await photoStorage.savePhotoLocally(
      updated.clientSignature,
      tag: 'sig',
      entityId: updated.id,
    );
    final savedImg1 = await photoStorage.savePhotoLocally(
      updated.image1,
      tag: 'img1',
      entityId: updated.id,
    );
    final savedImg2 = await photoStorage.savePhotoLocally(
      updated.image2,
      tag: 'img2',
      entityId: updated.id,
    );
    final savedImg3 = await photoStorage.savePhotoLocally(
      updated.image3,
      tag: 'img3',
      entityId: updated.id,
    );
    final savedHf = await photoStorage.savePhotoLocally(
      updated.houseFrontPicture,
      tag: 'house_front',
      entityId: updated.id,
    );

    final prepared = updated.copyWith(
      clientSignature: savedSig,
      image1: savedImg1,
      image2: savedImg2,
      image3: savedImg3,
      houseFrontPicture: savedHf,
      isSynced: false,
      updatedAt: DateTime.now(),
    );
    // Gene - Nov, 25, 2026: Invalidate cached remote photos for this order so UI reflects local edits/clears immediately.
    _imagesCache.remove(updated.id);

    if (dao != null) {
      // Optimistic local persist; PowerSync or the sync worker pushes it to the server.
      await dao!.insertOrUpdateOrder(prepared, synced: false);
      if (_isReplicatedMode()) {
        isSyncing.value = false;
        return true;
      }
      // Gene - Nov, 8, 2026: Update pendingCount before triggering background sync worker.
      await syncWorker?.refreshPendingCount();
      // Proactively trigger background sync
      unawaited(syncWorker?.syncPendingOrders());
      isSyncing.value = false;
      return true;
    }
    */
    // Gene - Nov, 28, 2026: In replicated PowerSync v12 mode, stage compressed photos strictly in pending_attachments atomically inside the same writeTransaction as scalar fields.
    if (dao != null && _isReplicatedMode() && pendingAttachments != null) {
      final existing = await dao!.getOrderById(updated.id);
      final stagedAttachments =
          <({String slotName, String? filePath, bool deleteFlag})>[];

      Future<void> stageSlot(
        String slotName,
        String? incoming,
        String? previous,
      ) async {
        if (incoming == null) return;
        final clean = incoming.trim();
        if (clean.isEmpty) {
          if (previous != null && previous.trim().isNotEmpty) {
            stagedAttachments
                .add((slotName: slotName, filePath: null, deleteFlag: true));
          }
          return;
        }
        if (previous != null && clean == previous.trim()) return;
        final savedPath = await photoStorage.savePendingMediaFromValue(
          clean,
          isSignature: slotName == 'client_signature',
        );
        if (savedPath != null && savedPath.isNotEmpty) {
          stagedAttachments.add(
            (slotName: slotName, filePath: savedPath, deleteFlag: false),
          );
        }
      }

      await stageSlot('client_signature', updated.clientSignature,
          existing?.clientSignature);
      await stageSlot('image1', updated.image1, existing?.image1);
      await stageSlot('image2', updated.image2, existing?.image2);
      await stageSlot('image3', updated.image3, existing?.image3);
      await stageSlot('house_front_picture', updated.houseFrontPicture,
          existing?.houseFrontPicture);

      final prepared = updated.copyWith(
        isSynced: false,
        updatedAt: DateTime.now(),
      );

      Future<void> writeAtomic(SqliteWriteContext? tx) async {
        if (tx != null) {
          await dao!.insertOrUpdateOrderInTx(
            tx,
            prepared,
            synced: false,
            omitPhotoColumns: true,
          );
          for (final item in stagedAttachments) {
            await pendingAttachments!.upsertInTx(
              tx,
              entityType: 'service_orders',
              entityId: '${updated.id}',
              slotName: item.slotName,
              filePath: item.filePath,
              deleteFlag: item.deleteFlag,
            );
          }
        } else {
          await dao!.insertOrUpdateOrder(
            prepared,
            synced: false,
            omitPhotoColumns: true,
          );
          for (final item in stagedAttachments) {
            await pendingAttachments!.upsert(
              entityType: 'service_orders',
              entityId: '${updated.id}',
              slotName: item.slotName,
              filePath: item.filePath,
              deleteFlag: item.deleteFlag,
            );
          }
        }
      }

      if (runInTransaction != null) {
        await runInTransaction!((tx) => writeAtomic(tx));
      } else {
        await writeAtomic(null);
      }
      _imagesCache.remove(updated.id);
      isSyncing.value = false;
      return true;
    }

    final savedSig = await photoStorage.savePhotoLocally(
      updated.clientSignature,
      tag: 'sig',
      entityId: updated.id,
    );
    final savedImg1 = await photoStorage.savePhotoLocally(
      updated.image1,
      tag: 'img1',
      entityId: updated.id,
    );
    final savedImg2 = await photoStorage.savePhotoLocally(
      updated.image2,
      tag: 'img2',
      entityId: updated.id,
    );
    final savedImg3 = await photoStorage.savePhotoLocally(
      updated.image3,
      tag: 'img3',
      entityId: updated.id,
    );
    final savedHf = await photoStorage.savePhotoLocally(
      updated.houseFrontPicture,
      tag: 'house_front',
      entityId: updated.id,
    );

    final prepared = updated.copyWith(
      clientSignature: savedSig,
      image1: savedImg1,
      image2: savedImg2,
      image3: savedImg3,
      houseFrontPicture: savedHf,
      isSynced: false,
      updatedAt: DateTime.now(),
    );
    // Gene - Nov, 25, 2026: Invalidate cached remote photos for this order so UI reflects local edits/clears immediately.
    _imagesCache.remove(updated.id);

    if (dao != null) {
      // Optimistic local persist; PowerSync or the sync worker pushes it to the server.
      await dao!.insertOrUpdateOrder(prepared, synced: false);
      if (_isReplicatedMode()) {
        isSyncing.value = false;
        return true;
      }
      // Gene - Nov, 8, 2026: Update pendingCount before triggering background sync worker.
      await syncWorker?.refreshPendingCount();
      // Proactively trigger background sync
      unawaited(syncWorker?.syncPendingOrders());
      isSyncing.value = false;
      return true;
    }

    try {
      final payload = await prepared.toApiJsonAsync();
      final ok = await api.updateServiceOrder(prepared.id, payload);
      if (ok) {
        // Update in-memory list
        final list = List<ServiceOrderDto>.from(allOrders.value);
        final idx = list.indexWhere((o) => o.id == prepared.id);
        if (idx != -1) {
          list[idx] = prepared.copyWith(isSynced: true);
        } else {
          list.insert(0, prepared.copyWith(isSynced: true));
        }
        allOrders.value = list;
        return true;
      }
    } catch (e) {
      syncError.value = 'Failed to update service order: $e';
    } finally {
      isSyncing.value = false;
    }
    return false;
  }

  // Gene - Nov, 25, 2026: Track in-flight Start/Finish timing calls and persist/sync Service Order work timing.
  final busyTimingOrderIds = signal<Set<int>>(<int>{});

  // Gene - Nov, 26, 2026: Expose currently started (in-progress) Service Order so other Service Orders and Job Orders hide Start.
  late final ReadonlySignal<ServiceOrderDto?> activeStartedOrder = computed(() {
    final onlyMe = onlyAssignedToMe.value;
    final email = technicianEmail.value?.trim();
    for (final order in allOrders.value) {
      /*
      if (!order.isOpen || !order.isTimingInProgress) continue;
      */
      // Gene - Nov, 28, 2026: Exclude Rescheduled orders from locking Start across active repairs.
      if (!order.isOpen || order.isRescheduled || !order.isTimingInProgress) {
        continue;
      }
      if (onlyMe &&
          email != null &&
          email.isNotEmpty &&
          !order.isAssignedTo(email)) {
        continue;
      }
      return order;
    }
    return null;
  });

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
  // Gene - Nov, 26, 2026: Use shared resolveTimingUserId so Service Order timing and history share the exact same userId.
  String _resolveTechId([String? override]) => resolveTimingUserId(
        override: override,
        fallbackEmail: technicianEmail.value,
      );

  // Gene - Nov, 26, 2026: Helpers to resolve technician identity/email metadata for Service Order audit fields.
  String? _resolveModifiedBy(ServiceOrderDto order) {
    final fullName = AuthSignals.instance.currentUser.value?.fullName.trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;
    final email = technicianEmail.value?.trim();
    if (email != null && email.isNotEmpty) return email;
    return order.modifiedBy;
  }

  String? _resolveUserEmail(ServiceOrderDto order) {
    final authEmail = AuthSignals.instance.currentUser.value?.email.trim();
    if (authEmail != null && authEmail.isNotEmpty) return authEmail;
    final email = technicianEmail.value?.trim();
    if (email != null && email.isNotEmpty) return email;
    return order.userEmail;
  }

  void _upsertInMemoryOrder(ServiceOrderDto order) {
    final list = List<ServiceOrderDto>.from(allOrders.value);
    final idx = list.indexWhere((o) => o.id == order.id);
    if (idx != -1) {
      list[idx] = order;
    } else {
      list.insert(0, order);
    }
    allOrders.value = list;
  }

  /*
  Future<String?> startOrder(ServiceOrderDto order, {String? techId}) async {
    if (busyTimingOrderIds.value.contains(order.id)) return null;
    busyTimingOrderIds.value = {...busyTimingOrderIds.value, order.id};
    final now = DateTime.now().toUtc();
    final updated = order.copyWith(
      startTimestamp: now,
      updatedAt: now,
    );
    _upsertInMemoryOrder(updated);
    if (dao != null) {
      await dao!.insertOrUpdateOrder(updated, synced: true);
    }
    try {
      await api.createTiming(
        joId: order.id,
        techId: _resolveTechId(techId),
        startTime: now,
        endTime: now,
      );
      return null;
    } catch (e) {
      final unsynced = updated.copyWith(isSynced: false);
      _upsertInMemoryOrder(unsynced);
      if (dao != null) {
        await dao!.insertOrUpdateOrder(unsynced, synced: false);
        await syncWorker?.refreshPendingCount();
      }
      return 'Started locally · sync pending ($e)';
    } finally {
      busyTimingOrderIds.value = {...busyTimingOrderIds.value}
        ..remove(order.id);
    }
  }

  Future<String?> finishOrder(ServiceOrderDto order, {String? techId}) async {
    if (busyTimingOrderIds.value.contains(order.id)) return null;
    busyTimingOrderIds.value = {...busyTimingOrderIds.value, order.id};
    final start = normalizeTimingTimestamp(order.startTimestamp) ??
        DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    var end = DateTime.now().toUtc();
    if (!end.isAfter(start)) {
      end = start.add(const Duration(seconds: 1));
    }
    final updated = order.copyWith(
      startTimestamp: start,
      stopTimestamp: end,
      updatedAt: end,
    );
    _upsertInMemoryOrder(updated);
    if (dao != null) {
      await dao!.insertOrUpdateOrder(updated, synced: true);
    }
    try {
      await api.updateTiming(
        joId: order.id,
        techId: _resolveTechId(techId),
        startTime: start,
        endTime: end,
      );
      return null;
    } catch (e) {
      final unsynced = updated.copyWith(isSynced: false);
      _upsertInMemoryOrder(unsynced);
      if (dao != null) {
        await dao!.insertOrUpdateOrder(unsynced, synced: false);
        await syncWorker?.refreshPendingCount();
      }
      return 'Finished locally · sync pending ($e)';
    } finally {
      busyTimingOrderIds.value = {...busyTimingOrderIds.value}
        ..remove(order.id);
    }
  }
  */
  // Gene - Nov, 26, 2026: Enforce single active order guard in startOrder, support restarting stopped orders (resetting stopTimestamp = now), and record Start/Stop history.
  Future<String?> startOrder(
    ServiceOrderDto order, {
    String? techId,
    bool hasOtherActiveOrder = false,
  }) async {
    if (busyTimingOrderIds.value.contains(order.id)) return null;
    final currentActive = activeStartedOrder.value;
    /*
    if (hasOtherActiveOrder ||
        (currentActive != null && currentActive.id != order.id)) {
      return 'Finish the active order before starting another.';
    }
    */
    // Gene - Nov, 28, 2026: Also block concurrent Start taps on another Service Order while an in-flight startOrder write is pending.
    final hasOtherBusyStart =
        busyTimingOrderIds.value.any((id) => id != order.id);
    if (hasOtherActiveOrder ||
        hasOtherBusyStart ||
        (currentActive != null && currentActive.id != order.id)) {
      return 'Finish the active order before starting another.';
    }
    busyTimingOrderIds.value = {...busyTimingOrderIds.value, order.id};
    var now = DateTime.now().toUtc();
    final prevStart = normalizeTimingTimestamp(order.startTimestamp);
    final prevStop = normalizeTimingTimestamp(order.stopTimestamp);
    for (final prev in [prevStart, prevStop]) {
      if (prev != null && !now.isAfter(prev)) {
        now = prev.add(const Duration(seconds: 1));
      }
    }
    final resolvedTechId = _resolveTechId(techId);
    final resolvedUserName = _resolveModifiedBy(order);
    final updated = order.copyWith(
      startTimestamp: now,
      stopTimestamp: now,
      modifiedBy: resolvedUserName,
      modifiedDate: now,
      techModifiedDate: now,
      userEmail: _resolveUserEmail(order),
      updatedAt: now,
    );
    _upsertInMemoryOrder(updated);
    final replicated = _isReplicatedMode();
    if (dao != null) {
      await dao!.insertOrUpdateOrder(updated, synced: !replicated);
    }
    final entryId = await timingHistory?.recordStart(
      orderType: WorkTimingEntry.orderTypeServiceOrder,
      orderId: order.id,
      orderReference: 'SO-${order.id.toString().padLeft(4, '0')}',
      customerName: order.fullName,
      userId: resolvedTechId,
      userName: resolvedUserName,
      startTime: now,
      isSynced: false,
    );
    try {
      await api.createTiming(
        joId: order.id,
        techId: resolvedTechId,
        startTime: now,
        endTime: now,
        idempotencyKey:
            'so_${order.id}_create_${now.toUtc().millisecondsSinceEpoch}',
      );
      if (entryId != null) {
        await timingHistory?.markSynced(entryId, isSynced: true);
      }
      return null;
    } catch (e) {
      if (replicated) {
        // start_timestamp & audit fields are queued via PowerSync ps_crud on service_orders.
        return null;
      }
      final unsynced = updated.copyWith(isSynced: false);
      _upsertInMemoryOrder(unsynced);
      if (dao != null) {
        await dao!.insertOrUpdateOrder(unsynced, synced: false);
        await syncWorker?.refreshPendingCount();
      }
      return 'Started locally · sync pending ($e)';
    } finally {
      busyTimingOrderIds.value = {...busyTimingOrderIds.value}
        ..remove(order.id);
    }
  }

  Future<String?> finishOrder(ServiceOrderDto order, {String? techId}) async {
    if (busyTimingOrderIds.value.contains(order.id)) return null;
    busyTimingOrderIds.value = {...busyTimingOrderIds.value, order.id};
    final start = normalizeTimingTimestamp(order.startTimestamp) ??
        DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    var end = DateTime.now().toUtc();
    if (!end.isAfter(start)) {
      end = start.add(const Duration(seconds: 1));
    }
    final resolvedTechId = _resolveTechId(techId);
    final resolvedUserName = _resolveModifiedBy(order);
    final updated = order.copyWith(
      startTimestamp: start,
      stopTimestamp: end,
      modifiedBy: resolvedUserName,
      modifiedDate: end,
      techModifiedDate: end,
      userEmail: _resolveUserEmail(order),
      updatedAt: end,
    );
    _upsertInMemoryOrder(updated);
    final replicated = _isReplicatedMode();
    if (dao != null) {
      await dao!.insertOrUpdateOrder(updated, synced: !replicated);
    }
    final entryId = await timingHistory?.recordFinish(
      orderType: WorkTimingEntry.orderTypeServiceOrder,
      orderId: order.id,
      orderReference: 'SO-${order.id.toString().padLeft(4, '0')}',
      customerName: order.fullName,
      userId: resolvedTechId,
      userName: resolvedUserName,
      startTime: start,
      endTime: end,
      isSynced: false,
    );
    try {
      await api.updateTiming(
        joId: order.id,
        techId: resolvedTechId,
        startTime: start,
        endTime: end,
        idempotencyKey:
            'so_${order.id}_update_${end.toUtc().millisecondsSinceEpoch}',
      );
      if (entryId != null) {
        await timingHistory?.markSynced(entryId, isSynced: true);
      }
      return null;
    } catch (e) {
      if (replicated) {
        // stop_timestamp & duration are queued via PowerSync ps_crud on service_orders.
        return null;
      }
      final unsynced = updated.copyWith(isSynced: false);
      _upsertInMemoryOrder(unsynced);
      if (dao != null) {
        await dao!.insertOrUpdateOrder(unsynced, synced: false);
        await syncWorker?.refreshPendingCount();
      }
      return 'Finished locally · sync pending ($e)';
    } finally {
      busyTimingOrderIds.value = {...busyTimingOrderIds.value}
        ..remove(order.id);
    }
  }
}
