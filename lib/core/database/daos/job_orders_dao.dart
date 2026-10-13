import 'dart:convert';

import '../../../features/jobs/models/job_order_model.dart';
import '../app_database.dart';
import '../sql_values.dart';

/// Reads and writes the `job_orders` table through PowerSync.
///
/// Every method takes and returns [JobOrderDto]; the column mapping lives in
/// [JobOrderDto.fromRow] and [JobOrderDto.toRow].
class JobOrdersDao {
  final AppDatabase _db;

  JobOrdersDao(this._db);

  static const String table = 'job_orders';

  /// Ids are stored as text, so numeric order needs the cast.
  static const String _byIdDesc = 'ORDER BY CAST(id AS INTEGER) DESC';

  static List<JobOrderDto> _map(Iterable<Map<String, Object?>> rows) =>
      [for (final r in rows) JobOrderDto.fromRow(r)];

  /// Watch all cached job orders sorted by ID descending
  Stream<List<JobOrderDto>> watchAllJobs() =>
      _db.watch('SELECT * FROM $table $_byIdDesc').map(_map);

  /// Watch job orders filtered by status
  Stream<List<JobOrderDto>> watchJobsByStatus(String status) {
    if (status.isEmpty) return watchAllJobs();
    return _db.watch(
      'SELECT * FROM $table WHERE status = ? $_byIdDesc',
      parameters: [status.toLowerCase()],
    ).map(_map);
  }

  /// Get all job orders once
  Future<List<JobOrderDto>> getAllJobs() async =>
      _map(await _db.getAll('SELECT * FROM $table $_byIdDesc'));

  /// Get single job by id
  Future<JobOrderDto?> getJobById(int id) async {
    final row = await _db.getOptional(
      'SELECT * FROM $table WHERE id = ?',
      [idText(id)],
    );
    return row == null ? null : JobOrderDto.fromRow(row);
  }

  /// Insert or update single job.
  ///
  /// [synced] false marks the row as a local edit still waiting for the
  /// server, which a refresh must not overwrite.
  Future<void> insertOrUpdateJob(JobOrderDto job, {bool synced = true}) =>
      insertAllJobs([job], synced: synced);

  /// Batch insert / cache job list from API
  Future<void> insertAllJobs(List<JobOrderDto> jobs,
      {bool synced = true}) async {
    if (jobs.isEmpty) return;
    final rows = [for (final j in jobs) j.toRow(synced: synced)];
    final columns = rows.first.keys.toList();
    final sql = insertOrReplaceSql(table, columns);
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < rows.length; i += 100) {
        final chunk =
            rows.sublist(i, (i + 100 > rows.length) ? rows.length : i + 100);
        await tx.executeBatch(sql, [
          for (final r in chunk) [for (final c in columns) r[c]],
        ]);
      }
    });
  }

  /// Apply [changes] (column -> value) to one row, stamping `updated_at`.
  Future<void> _patch(int id, Map<String, Object?> changes) async {
    final fields = {...changes, 'updated_at': dateText(DateTime.now())};
    final sets = fields.keys.map((k) => '$k = ?').join(', ');
    await _db.execute(
      'UPDATE $table SET $sets WHERE id = ?',
      [...fields.values, idText(id)],
    );
  }

  /// Update the technician's on-site status, leaving the office-side `status`
  /// column untouched.
  Future<void> updateFieldStatus(int id, String onsiteStatus,
          {bool isSynced = false}) =>
      _patch(id, {
        'onsite_status': onsiteStatus,
        'is_synced': boolInt(isSynced),
      });

  /// Move an open job between Scheduled and Rescheduled, with the reason
  /// (or null to clear it), and queue the edit for sync.
  Future<void> updateStatusWithRemarks(
    int id, {
    required String status,
    required String? statusRemarks,
    bool isSynced = false,
  }) =>
      _patch(id, {
        'status': status,
        'status_remarks': statusRemarks,
        'is_synced': boolInt(isSynced),
      });

  Future<void> updateJobStatus(int id, String newStatus,
          {bool isSynced = false}) =>
      _patch(id, {'status': newStatus, 'is_synced': boolInt(isSynced)});

  /// Complete a job: sets status to 'Completed', onsiteStatus to 'Done',
  /// updates dateInstalled, and marks isSynced = false for sync.
  Future<void> completeJob(
    int id, {
    String? assignedEmail,
    required DateTime installedAt,
    bool isSynced = false,
  }) =>
      _patch(id, {
        'status': 'Completed',
        'onsite_status': 'Done',
        if (assignedEmail != null) 'assigned_email': assignedEmail,
        'date_installed': dateText(installedAt),
        'is_synced': boolInt(isSynced),
      });

  /// Mark a job Activated: the technician's terminal stage.
  ///
  /// Records who activated it in [assignedEmail] (kept as-is when null) and
  /// the install date, so the job lands in that technician's history.
  Future<void> activateJob(
    int id, {
    String? assignedEmail,
    required DateTime installedAt,
    bool isSynced = false,
  }) =>
      _patch(id, {
        'status': 'Activated',
        'onsite_status': 'Done',
        if (assignedEmail != null) 'assigned_email': assignedEmail,
        'date_installed': dateText(installedAt),
        'is_synced': boolInt(isSynced),
      });

  /// Update completion report details locally
  /*
  Future<void> updateJobCompletion({
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
    bool isSynced = false,
  }) async {
  */
  /*
  // Gene - Oct 13, 2026: Added vlanId parameter to persist VLAN selection on report completion.
  Future<void> updateJobCompletion({
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
    bool isSynced = false,
  }) async {
  */
  // Gene - Oct 13, 2026: Added planId and planName parameters to updateJobCompletion to persist on-site plan upgrades.
  Future<void> updateJobCompletion({
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
    bool isSynced = false,
  }) async {
    String? updatedRawJson;
    if (materialsUsed != null || vlanId != null || planId != null || planName != null) {
      final existing = await getJobById(id);
      Map<String, dynamic> rawMap = {};
      final raw = existing?.rawJson;
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) rawMap = decoded;
        } catch (_) {}
      }
      if (materialsUsed != null) {
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
      if (vlanId != null) {
        rawMap['vlanId'] = vlanId;
        rawMap['vlan'] = vlanId.toString();
      }
      if (planId != null) {
        rawMap['planId'] = planId;
        rawMap['PlanId'] = planId;
      }
      if (planName != null) {
        rawMap['plan'] = planName;
        rawMap['planName'] = planName;
      }
      updatedRawJson = jsonEncode(rawMap);
    }

    await _patch(id, {
      if (status != null) 'status': status,
      'onsite_status': onsiteStatus,
      if (assignedEmail != null) 'assigned_email': assignedEmail,
      'onsite_remarks': onsiteRemarks,
      'optical_power': opticalPower,
      'modem_router_sn': modemRouterSN,
      'router_model': routerModel,
      if (nap != null) 'nap': nap,
      if (vlanId != null) 'vlan_id': vlanId,
      if (planId != null) 'plan_id': planId,
      if (planName != null) 'plan_name': planName,
      'date_installed': dateText(DateTime.now()),
      'box_reading_image': boxReadingImage,
      'router_reading_image': routerReadingImage,
      'client_signature': clientSignature,
      'setup_image': setupImage,
      'speedtest_image': speedtestImage,
      'port_label_image': portLabelImage,
      'signed_contract_image': signedContractImage,
      'house_front': houseFront,
      if (updatedRawJson != null) 'raw_json': updatedRawJson,
      'is_synced': boolInt(isSynced),
    });
  }

  /// Get all pending unsynced records
  Future<List<JobOrderDto>> getUnsyncedJobs() async =>
      _map(await _db.getAll('SELECT * FROM $table WHERE is_synced = 0'));

  /// Ids of rows carrying a local edit that has not reached the server.
  Future<Set<int>> getUnsyncedIds() async {
    final rows = await _db.getAll('SELECT id FROM $table WHERE is_synced = 0');
    return {for (final r in rows) rowInt(r['id'])};
  }

  /// Count unsynced items
  Future<int> countUnsynced() async {
    final row =
        await _db.get('SELECT count(*) AS c FROM $table WHERE is_synced = 0');
    return rowInt(row['c']);
  }

  /// Mark job as synced
  Future<void> markAsSynced(int id) => _patch(id, {'is_synced': 1});

  /// Drop cached rows the server no longer returns, keeping any row with a
  /// local edit still waiting to sync so nothing the technician did is lost.
  /*
  Future<int> deleteSyncedJobsNotIn(Set<int> keepIds) async {
    final synced =
        await _db.getAll('SELECT id FROM $table WHERE is_synced = 1');
    final toDelete = [
      for (final r in synced)
        if (!keepIds.contains(rowInt(r['id']))) r['id'],
    ];
    if (toDelete.isEmpty) return 0;
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < toDelete.length; i += 200) {
        final chunk = toDelete.sublist(
            i, (i + 200 > toDelete.length) ? toDelete.length : i + 200);
        await tx.execute(
          'DELETE FROM $table WHERE id IN (${placeholders(chunk.length)})',
          chunk,
        );
      }
    });
    return toDelete.length;
  }
  */
  // Gene - Oct 3, 2026: Guard deleteSyncedJobsNotIn against empty keepIds to prevent accidental full cache wipes when remote calls return empty.
  Future<int> deleteSyncedJobsNotIn(Set<int> keepIds) async {
    if (keepIds.isEmpty) return 0;
    final synced =
        await _db.getAll('SELECT id FROM $table WHERE is_synced = 1');
    final toDelete = [
      for (final r in synced)
        if (!keepIds.contains(rowInt(r['id']))) r['id'],
    ];
    if (toDelete.isEmpty) return 0;
    await _db.writeTransaction((tx) async {
      for (var i = 0; i < toDelete.length; i += 200) {
        final chunk = toDelete.sublist(
            i, (i + 200 > toDelete.length) ? toDelete.length : i + 200);
        await tx.execute(
          'DELETE FROM $table WHERE id IN (${placeholders(chunk.length)})',
          chunk,
        );
      }
    });
    return toDelete.length;
  }

  /// Delete a job
  Future<void> deleteJob(int id) =>
      _db.execute('DELETE FROM $table WHERE id = ?', [idText(id)]);

  /// Clear table (e.g. on full resync or logout)
  Future<void> clearAllJobs() => _db.execute('DELETE FROM $table');

  /// Delete test/sample demo jobs (IDs 101 to 106)
  Future<int> deleteSampleJobs() async {
    const where = 'CAST(id AS INTEGER) BETWEEN 101 AND 106';
    final row = await _db.get('SELECT count(*) AS c FROM $table WHERE $where');
    final count = rowInt(row['c']);
    if (count > 0) await _db.execute('DELETE FROM $table WHERE $where');
    return count;
  }
}
