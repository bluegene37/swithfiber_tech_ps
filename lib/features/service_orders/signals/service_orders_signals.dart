import 'dart:async';
// Gene - Oct 3, 2026: Commented out unused services.dart import now that sound and haptics are encapsulated in SoundService.
// import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/services/sound_service.dart';
import '../../../core/database/daos/service_orders_dao.dart';
import '../../../core/services/photo_storage_service.dart';
import '../models/service_order_model.dart';
import '../services/service_orders_api.dart';
import '../services/service_orders_sync_worker.dart';

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

  /// Surfaced when a new open Service Order is synced or assigned to the technician.
  final newOrderAlert = signal<ServiceOrderDto?>(null);

  bool _hasInitialSnapshot = false;
  final Set<int> _knownOrderIds = <int>{};
  final Set<int> _myAssignedOrderIds = <int>{};

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

        if (order.isOpen && matchesTech && (isNewSynced || isNewlyAssigned)) {
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
  void setTechnicianEmail(String? email) {
    if (technicianEmail.value != email) {
      _hasInitialSnapshot = false;
      _knownOrderIds.clear();
      _myAssignedOrderIds.clear();
      newOrderAlert.value = null;
    }
    technicianEmail.value = email;
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

  /// Total count of service orders visible to technician
  late final ReadonlySignal<int> totalCount =
      computed(() => filteredOrders.value.length);

  /// Urgent service orders count
  late final ReadonlySignal<int> urgentCount =
      computed(() => filteredOrders.value.where((o) => o.isUrgent).length);

  /// Filtered and sorted service orders
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

  /// Fetch latest service orders from the server scoped to the logged-in technician
  Future<void> fetchRemote({String? technicianEmail}) async {
    final effectiveEmail =
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
    isSyncing.value = true;
    syncError.value = null;

    try {
      if (syncWorker != null && syncWorker!.pendingCount.value > 0) {
        await syncWorker!.syncPendingOrders();
      }
      final remoteList = await api.fetchServiceOrders();
      final scopedList = (effectiveEmail != null && effectiveEmail.isNotEmpty)
          ? remoteList.where((dto) => dto.isAssignedTo(effectiveEmail)).toList()
          : remoteList;

      if (dao != null) {
        final pending = await dao!.getUnsyncedIds();
        final fresh = <ServiceOrderDto>[];
        final keep = <int>{};
        for (final dto in scopedList) {
          keep.add(dto.id);
          if (pending.contains(dto.id)) continue;
          fresh.add(dto);
        }
        if (fresh.isNotEmpty) {
          await dao!.insertAllOrders(fresh, synced: true);
        }
        /*
        await dao!.deleteSyncedOrdersNotIn(keep);
        */
        // Gene - Oct 3, 2026: Guard deleteSyncedOrdersNotIn with keep.isNotEmpty to prevent wiping all service orders on empty responses.
        if (keep.isNotEmpty) {
          await dao!.deleteSyncedOrdersNotIn(keep);
        }
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

    if (dao != null) {
      // Optimistic local persist; the sync worker pushes it to the API.
      await dao!.insertOrUpdateOrder(prepared, synced: false);
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
}
