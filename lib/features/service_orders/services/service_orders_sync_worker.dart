import 'dart:async';
import 'dart:convert';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/database/daos/service_orders_dao.dart';
import '../../../core/database/daos/sync_error_logs_dao.dart';
import '../../../core/network/network_exceptions.dart';
import '../../../core/network/request_snapshot.dart';
import '../models/service_order_model.dart';
import 'service_orders_api.dart';

/// Background worker that synchronizes offline-edited service orders with the backend API.
class ServiceOrdersSyncWorker {
  final ServiceOrdersDao _dao;
  final ServiceOrdersApi _api;
  // Gene - Nov, 23, 2026: Added optional SyncErrorLogsDao to record refused repair pushes with payload metrics.
  final SyncErrorLogsDao? _errorLog;
  // Gene - Nov, 25, 2026: Optional callback to invalidate cached ServiceOrderImagesDto after a successful push.
  final void Function(int orderId)? _onOrderSynced;

  /*
  ServiceOrdersSyncWorker(this._dao, {ServiceOrdersApi? api})
      : _api = api ?? ServiceOrdersApi();
  */
  /*
  ServiceOrdersSyncWorker(
    this._dao, {
    ServiceOrdersApi? api,
    SyncErrorLogsDao? errorLog,
  })  : _api = api ?? ServiceOrdersApi(),
        _errorLog = errorLog;
  */
  ServiceOrdersSyncWorker(
    this._dao, {
    ServiceOrdersApi? api,
    SyncErrorLogsDao? errorLog,
    void Function(int orderId)? onOrderSynced,
  })  : _api = api ?? ServiceOrdersApi(),
        _errorLog = errorLog,
        _onOrderSynced = onOrderSynced;

  // Reactive state
  final isSyncing = signal<bool>(false);
  final pendingCount = signal<int>(0);
  final lastSyncTime = signal<DateTime?>(null);
  final syncError = signal<String?>(null);

  /// Refresh pending count from the local database
  Future<int> refreshPendingCount() async {
    final count = await _dao.countUnsynced();
    pendingCount.value = count;
    return count;
  }

  /// Run sync process for all pending unsynced records
  Future<ServiceOrdersSyncResult> syncPendingOrders() async {
    if (isSyncing.value) {
      return ServiceOrdersSyncResult(
        success: false,
        message: 'Sync already in progress',
      );
    }

    isSyncing.value = true;
    syncError.value = null;

    int syncedSuccess = 0;
    int syncedFailed = 0;
    int removed = 0;

    try {
      final unsynced = await _dao.getUnsyncedOrders();
      pendingCount.value = unsynced.length;

      if (unsynced.isEmpty) {
        lastSyncTime.value = DateTime.now();
        return ServiceOrdersSyncResult(
          success: true,
          syncedCount: 0,
          message: 'All service orders are up to date.',
        );
      }

      /*
      for (final dto in unsynced) {
        try {
          final payload = await dto.toApiJsonAsync();
          final ok = await _api.updateServiceOrder(dto.id, payload);
          if (ok) {
            await _dao.markAsSynced(dto.id);
            syncedSuccess++;
          } else {
            syncedFailed++;
          }
        } on ApiException catch (err) {
          if (err.statusCode == 404) {
            await _dao.deleteOrder(dto.id);
            removed++;
          } else {
            syncedFailed++;
          }
        } catch (_) {
          syncedFailed++;
        }
      }

      final remaining = await _dao.countUnsynced();
      pendingCount.value = remaining;
      lastSyncTime.value = DateTime.now();

      final parts = <String>[
        if (syncedSuccess > 0) 'Synced $syncedSuccess service order(s).',
        if (removed > 0)
          '$removed service order(s) no longer exist on the server and were removed.',
        if (syncedFailed > 0) '$syncedFailed remaining offline.',
      ];

      return ServiceOrdersSyncResult(
        success: syncedFailed == 0,
        syncedCount: syncedSuccess,
        failedCount: syncedFailed,
        removedCount: removed,
        message: parts.join(' '),
      );
    } catch (e) {
      syncError.value = e.toString();
      return ServiceOrdersSyncResult(
        success: false,
        message: 'Sync failed: $e',
      );
    } finally {
      isSyncing.value = false;
    }
    */
      // Gene - Nov, 23, 2026: Record refused repair pushes to SyncErrorLogsDao, resolve on success, and surface friendly error text.
      final failures = <String>[];
      for (final dto in unsynced) {
        final outcome = await _pushOrder(dto, failures: failures);
        switch (outcome) {
          case _OrderPushOutcome.synced:
            syncedSuccess++;
          case _OrderPushOutcome.removed:
            removed++;
          case _OrderPushOutcome.failed:
            syncedFailed++;
        }
      }

      final remaining = await _dao.countUnsynced();
      pendingCount.value = remaining;
      lastSyncTime.value = DateTime.now();

      final parts = <String>[
        if (syncedSuccess > 0) 'Synced $syncedSuccess service order(s).',
        if (removed > 0)
          '$removed service order(s) no longer exist on the server and were removed.',
        if (syncedFailed > 0) '$syncedFailed remaining offline.',
      ];

      syncError.value = failures.isEmpty ? null : failures.join('\n');

      return ServiceOrdersSyncResult(
        success: syncedFailed == 0,
        syncedCount: syncedSuccess,
        failedCount: syncedFailed,
        removedCount: removed,
        message: parts.join(' '),
      );
    } catch (e) {
      final friendly = _friendlyErrorMessage(e);
      syncError.value = friendly;
      return ServiceOrdersSyncResult(
        success: false,
        message: friendly,
      );
    } finally {
      isSyncing.value = false;
    }
  }

  /// Sync a single unsynced service order by [orderId].
  Future<bool> syncSingleOrder(int orderId) async {
    if (isSyncing.value) return false;
    isSyncing.value = true;
    syncError.value = null;
    try {
      final dto = await _dao.getOrderById(orderId);
      if (dto == null) {
        await refreshPendingCount();
        return false;
      }
      final failures = <String>[];
      final outcome = await _pushOrder(dto, failures: failures);
      await refreshPendingCount();
      lastSyncTime.value = DateTime.now();
      if (failures.isNotEmpty) {
        syncError.value = failures.join('\n');
      }
      return outcome == _OrderPushOutcome.synced ||
          outcome == _OrderPushOutcome.removed;
    } catch (e) {
      syncError.value = _friendlyErrorMessage(e);
      return false;
    } finally {
      isSyncing.value = false;
    }
  }

  Future<_OrderPushOutcome> _pushOrder(
    ServiceOrderDto dto, {
    required List<String> failures,
  }) async {
    var payloadBytes = 0;
    Map<String, dynamic>? payload;
    final reference = 'SO-${dto.id.toString().padLeft(4, '0')}';
    try {
      payload = await dto.toApiJsonAsync();
      payloadBytes = utf8.encode(json.encode(payload)).length;
      final ok = await _api.updateServiceOrder(dto.id, payload);
      if (ok) {
        /*
        await _dao.markAsSynced(dto.id);
        await _errorLog?.markResolved('SERVICE_ORDER', dto.id);
        return _OrderPushOutcome.synced;
        */
        // Gene - Nov, 25, 2026: Refresh local row from server copy after successful push (falling back to markAsSynced) and notify image cache.
        await _replaceWithServerCopy(dto.id);
        _onOrderSynced?.call(dto.id);
        await _errorLog?.markResolved('SERVICE_ORDER', dto.id);
        return _OrderPushOutcome.synced;
      }
      const msg = 'Server rejected repair update without a detailed message.';
      failures.add('$reference: $msg');
      await _record(
        dto,
        reference: reference,
        statusCode: null,
        message: msg,
        payloadBytes: payloadBytes,
        body: payload,
      );
      return _OrderPushOutcome.failed;
    } on ApiException catch (err) {
      if (err.statusCode == 404) {
        await _dao.deleteOrder(dto.id);
        await _errorLog?.markResolved('SERVICE_ORDER', dto.id);
        return _OrderPushOutcome.removed;
      }
      failures.add('$reference: HTTP ${err.statusCode ?? "?"} ${err.message}');
      await _record(
        dto,
        reference: reference,
        statusCode: err.statusCode,
        message: err.message,
        payloadBytes: payloadBytes,
        body: payload,
        method: err.requestMethod,
        url: err.requestUrl,
        response: err.details,
      );
      return _OrderPushOutcome.failed;
    } catch (e) {
      final friendly = _friendlyErrorMessage(e);
      failures.add('$reference: $friendly');
      await _record(
        dto,
        reference: reference,
        statusCode: null,
        message: e.toString(),
        payloadBytes: payloadBytes,
        body: payload,
      );
      return _OrderPushOutcome.failed;
    }
  }

  String _friendlyErrorMessage(Object error) {
    if (error is ApiException) {
      return error.statusCode != null
          ? 'Server returned HTTP ${error.statusCode}: ${error.message}'
          : error.message;
    }
    final raw = error.toString().toLowerCase();
    if (raw.contains('socket') ||
        raw.contains('timeout') ||
        raw.contains('connection') ||
        raw.contains('network')) {
      return 'Could not reach server. Changes stay saved on this phone.';
    }
    return 'Sync paused. Changes stay saved on this phone and will retry automatically.';
  }

  Future<void> _record(
    ServiceOrderDto dto, {
    required String reference,
    required int? statusCode,
    required String message,
    required int payloadBytes,
    Map<String, dynamic>? body,
    String? method,
    String? url,
    dynamic response,
  }) async {
    try {
      await _errorLog?.log(
        entityType: 'SERVICE_ORDER',
        entityId: dto.id,
        reference: reference,
        operation: 'repair',
        statusCode: statusCode,
        message: message,
        payloadBytes: payloadBytes,
        requestMethod: method ?? 'PUT',
        requestUrl: url ?? '/api/ServiceOrders/${dto.id}',
        requestBody: body == null ? null : RequestSnapshot.body(body),
        responseBody: RequestSnapshot.response(response),
      );
    } catch (_) {}
  }

  // Gene - Nov, 25, 2026: Swap local row with server copy after push, falling back to markAsSynced if offline/unavailable.
  Future<void> _replaceWithServerCopy(int id) async {
    try {
      final fresh = await _api.fetchServiceOrderById(id);
      if (fresh != null) {
        await _dao.insertOrUpdateOrder(fresh, synced: true);
        return;
      }
    } catch (_) {}
    await _dao.markAsSynced(id);
  }
}

enum _OrderPushOutcome { synced, removed, failed }

class ServiceOrdersSyncResult {
  final bool success;
  final int syncedCount;
  final int failedCount;
  final int removedCount;
  final String message;

  const ServiceOrdersSyncResult({
    required this.success,
    this.syncedCount = 0,
    this.failedCount = 0,
    this.removedCount = 0,
    required this.message,
  });
}
