// Gene - Nov, 28, 2026: Signals state container for non-blocking 409 REASSIGNED/CANCELLED sync conflicts surfaced in Needs Review.
import 'dart:async';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/database/daos/pending_attachments_dao.dart';
import '../../../core/database/daos/sync_conflicts_dao.dart';
import '../../../core/database/models/sync_conflict.dart';

class SyncConflictsSignals {
  final SyncConflictsDao _dao;
  final PendingAttachmentsDao? _pendingAttachmentsDao;
  StreamSubscription<List<SyncConflict>>? _sub;

  final unresolvedConflicts = signal<List<SyncConflict>>([]);

  // Gene - Nov, 28, 2026: Guard SyncConflictsSignals async operations against disposal/database close so late refresh() after teardown never throws StateError.
  bool _disposed = false;

  late final ReadonlySignal<int> unresolvedCount =
      computed(() => unresolvedConflicts.value.length);

  SyncConflictsSignals(
    this._dao, {
    PendingAttachmentsDao? pendingAttachmentsDao,
  }) : _pendingAttachmentsDao = pendingAttachmentsDao {
    /*
    _sub = _dao.watchUnresolved().listen((list) {
      unresolvedConflicts.value = list;
    });
    */
    _sub = _dao.watchUnresolved().listen((list) {
      if (!_disposed) {
        unresolvedConflicts.value = list;
      }
    });
  }

  /*
  Future<void> refresh() async {
    unresolvedConflicts.value = await _dao.getUnresolved();
  }

  Future<void> dismissConflict(String id) async {
    await _dao.markResolved(
      id,
      pendingAttachmentsDao: _pendingAttachmentsDao,
    );
    await refresh();
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
  */
  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final list = await _dao.getUnresolved();
      if (!_disposed) {
        unresolvedConflicts.value = list;
      }
    } on StateError {
      if (!_disposed) rethrow;
    }
  }

  Future<void> dismissConflict(String id) async {
    if (_disposed) return;
    try {
      await _dao.markResolved(
        id,
        pendingAttachmentsDao: _pendingAttachmentsDao,
      );
      if (_disposed) return;
      await refresh();
    } on StateError {
      if (!_disposed) rethrow;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
  }
}
