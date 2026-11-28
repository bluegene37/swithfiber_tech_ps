// Gene - Nov, 28, 2026: End-to-end verification tests for PowerSync v12 coalesced uploads, non-blocking 409 conflicts, ETag lookups sync, offline UUID local_id_map, 401 reauth preservation, and 200% text-scale UI.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart' hide Column;
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/lookups_sync_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_gateway_client.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/auth/widgets/reauth_dialog.dart';
import 'package:swithfiber_tech_ps/features/catalogs/services/catalog_service.dart';
import 'package:swithfiber_tech_ps/features/diagnostics/screens/sync_conflicts_screen.dart';
import 'package:swithfiber_tech_ps/features/diagnostics/signals/sync_conflicts_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_history_view.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/widgets/service_order_history_view.dart';

class _CapturedRequest {
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final String rawText;

  const _CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.rawText,
  });
}

class _MockV12Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(_CapturedRequest req) handler;
  final List<_CapturedRequest> requests = [];

  _MockV12Adapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final chunks = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
    }
    final rawText =
        chunks.isEmpty ? '' : utf8.decode(chunks, allowMalformed: true);
    final req = _CapturedRequest(
      method: options.method.toUpperCase(),
      uri: options.uri,
      headers: options.headers,
      rawText: rawText,
    );
    requests.add(req);
    return handler(req);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResp(
  dynamic data, {
  int statusCode = 200,
  Map<String, List<String>> headers = const {},
}) {
  return ResponseBody.fromString(
    data == null ? '' : jsonEncode(data),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
      ...headers,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    ApiClient.blockNetworkForTesting = true;
    tempDir = Directory.systemTemp.createTempSync('sf_v12_sync_test_');
    FlutterSecureStorage.setMockInitialValues({});
    PhotoStorageService.instance.setDirectoryForTesting(tempDir);
  });

  tearDown(() async {
    ApiClient.blockNetworkForTesting = false;
    PhotoStorageService.instance.setDirectoryForTesting(null);
    CatalogService.instance.attachLookupsDao(null);
    CatalogService.instance.invalidateCache();
    AuthSignals.instance.currentUser.value = null;
    AuthSignals.instance.clearReauthPrompt();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<PowerSyncDatabase> openReplicatedDb() async {
    final db = PowerSyncDatabase(
      schema: powerSyncReplicatedSchema,
      path: p.join(
        tempDir.path,
        'rep_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await db.initialize();
    return db;
  }

  Future<PowerSyncDatabase> openLocalDb() async {
    final db = PowerSyncDatabase(
      schema: powerSyncSchema,
      path: p.join(
        tempDir.path,
        'loc_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await db.initialize();
    return db;
  }

  group('PowerSync v12 Sync Layer Verification', () {
    test(
        '1. Coalesces multiple ps_crud writes + pending_attachments into 1 multipart PATCH with cleanup and scalar speedtest_image',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final adapter = _MockV12Adapter((_) async => _jsonResp({'ok': true}));

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-rs256-session',
        });

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status, setup_image, box_reading_image) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            '4328',
            'T-4328',
            'Juan Dela Cruz',
            '123 Main St',
            'Scheduled',
            'server/old_setup.jpg',
            'server/old_box.jpg',
          ],
        );
        // Clear initial seed ps_crud entry so we strictly test the 2 completion/patch mutations below.
        final seedTx = await db.getNextCrudTransaction();
        await seedTx?.complete();

        final repo = JobRepository(
          appDb.jobOrdersDao,
          isReplicatedMode: () => true,
          pendingAttachments: appDb.pendingAttachmentsDao,
          runInTransaction: db.writeTransaction,
        );

        final tinyJpgBytes =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
        final pendingJpgPath = await PhotoStorageService.instance
            .savePendingMediaBytes(tinyJpgBytes, extension: 'jpg');
        expect(File(pendingJpgPath).existsSync(), isTrue);

        // Mutation 1: saveCompletionReport with a captured file path, explicit delete, and scalar speedtest_image.
        await repo.saveCompletionReport(
          id: 4328,
          onsiteStatus: 'Done',
          onsiteRemarks: 'Initial remark',
          setupImage: pendingJpgPath,
          boxReadingImage: '',
          speedtestImage: 'https://cdn.example.com/speed_4328.png',
          materialsUsed: const {'Drop Cable (m)': 50},
        );

        // Mutation 2: follow-up scalar update on the same job order before upload drains.
        await db.execute(
          'UPDATE job_orders SET onsite_remarks = ? WHERE id = ?',
          ['Updated remark after walktest', '4328'],
        );

        final queuedRows = await appDb.pendingAttachmentsDao
            .getPendingForEntity('job_orders', '4328');
        expect(queuedRows.length, 2);

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          syncConflicts: appDb.syncConflictsDao,
          localIdMap: appDb.localIdMapDao,
          errorLog: appDb.syncErrorLogsDao,
        );

        await connector.uploadData(db);

        expect(adapter.requests.length, 1);
        final req = adapter.requests.single;
        expect(req.method, 'PATCH');
        expect(req.uri.path, '/api/JobOrders/4328');
        expect(req.headers['Authorization'], 'Bearer gw-rs256-session');
        expect((req.headers['Idempotency-Key'] ?? '').toString(), isNotEmpty);

        // Scalar latest remarks, canonical item_name_1, and scalar speedtest_image included.
        expect(req.rawText, contains('Updated remark after walktest'));
        expect(req.rawText, contains('name="speedtest_image"'));
        expect(req.rawText, contains('https://cdn.example.com/speed_4328.png'));
        expect(req.rawText, contains('name="item_name_1"'));
        expect(req.rawText, contains('Drop Cable (m)'));

        // Canonical multipart slots + delete flags, no legacy client columns.
        expect(req.rawText, contains('name="setup_image"'));
        expect(req.rawText, contains('name="delete_box_reading_image"'));
        expect(req.rawText, isNot(contains('name="item_name1"')));
        expect(req.rawText, isNot(contains('name="optical_power"')));
        expect(req.rawText, isNot(contains('name="is_synced"')));

        // ps_crud, pending_attachments, and pending_media temp file all cleaned up.
        expect(await db.getNextCrudTransaction(), isNull);
        expect(await appDb.pendingAttachmentsDao.countPending(), 0);
        expect(File(pendingJpgPath).existsSync(), isFalse);
      } finally {
        await appDb.close();
      }
    });

    test(
        '2. Non-blocking 409 REASSIGNED / CANCELLED inserts into sync_conflicts, keeps queue moving, and dismisses cleanly',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final adapter = _MockV12Adapter((req) async {
        if (req.uri.path == '/api/JobOrders/101') {
          return _jsonResp({
            'error': 'Job order reassigned to another technician.',
            'code': 'REASSIGNED',
            'assignedEmail': 'other.tech@switchfiber.ph',
            'serverRecord': {
              'id': 101,
              'assigned_email': 'other.tech@switchfiber.ph',
              'status': 'Scheduled',
            },
          }, statusCode: 409);
        }
        if (req.uri.path == '/api/ServiceOrders/202') {
          return _jsonResp({
            'error': 'Ticket was cancelled by dispatch.',
            'code': 'CANCELLED',
            'serverStatus': 'Cancelled',
            'serverRecord': {'id': 202, 'support_status': 'Cancelled'},
          }, statusCode: 409);
        }
        return _jsonResp({'ok': true});
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-rs256',
        });

        final conflictPhotoPath =
            await PhotoStorageService.instance.savePendingMediaBytes(
          Uint8List.fromList([1, 2, 3, 4]),
          extension: 'jpg',
        );

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['101', 'T-101', 'Alice', 'Addr 1', 'In Progress'],
        );
        await appDb.pendingAttachmentsDao.upsert(
          entityType: 'job_orders',
          entityId: '101',
          slotName: 'setup_image',
          filePath: conflictPhotoPath,
        );
        await db.execute(
          'INSERT INTO service_orders (id, account_number, full_name, support_status) '
          'VALUES (?, ?, ?, ?)',
          ['202', 'ACC-202', 'Bob', 'In Progress'],
        );
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['102', 'T-102', 'Charlie', 'Addr 2', 'In Progress'],
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          syncConflicts: appDb.syncConflictsDao,
          errorLog: appDb.syncErrorLogsDao,
        );

        // Must NOT throw on 409; must process order 102 in the same batch!
        await expectLater(connector.uploadData(db), completes);
        expect(adapter.requests.map((r) => r.uri.path).toList(), [
          '/api/JobOrders/101',
          '/api/ServiceOrders/202',
          '/api/JobOrders/102',
        ]);
        expect(await db.getNextCrudTransaction(), isNull);

        final conflicts = await appDb.syncConflictsDao.getUnresolved();
        expect(conflicts.length, 2);
        expect(
            conflicts
                .any((c) => c.entityId == '101' && c.reason == 'REASSIGNED'),
            isTrue);
        expect(
            conflicts
                .any((c) => c.entityId == '202' && c.reason == 'CANCELLED'),
            isTrue);

        // Blocked attachment on conflicted entity is cleaned up immediately, not stalling pending queue.
        expect(await appDb.pendingAttachmentsDao.countPending(), 0);
        final attRows = await appDb.pendingAttachmentsDao
            .getAllForEntity('job_orders', '101');
        expect(attRows, isEmpty);
        expect(File(conflictPhotoPath).existsSync(), isFalse);

        // Dismiss first conflict leaves second conflict unresolved.
        final firstId = conflicts.firstWhere((c) => c.entityId == '101').id;
        await appDb.syncConflictsDao.markResolved(
          firstId,
          pendingAttachmentsDao: appDb.pendingAttachmentsDao,
        );
        expect(await appDb.syncConflictsDao.countUnresolved(), 1);
      } finally {
        await appDb.close();
      }
    });

    test(
        '3. GET /api/sync/lookups replaces all 11 localOnly tables atomically on 200, respects 304 Not Modified, and serves CatalogService offline',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      var callCount = 0;

      final adapter = _MockV12Adapter((req) async {
        expect(req.uri.path, '/api/sync/lookups');
        expect(req.headers['Authorization'], 'Bearer gw-rs256');
        callCount++;
        if (callCount == 1) {
          return _jsonResp({
            'etag': '"lookups-v12-abc"',
            'fetchedAt': '2026-11-28T10:00:00Z',
            'tableEtags': {'plans': '"p1"'},
            'tables': {
              'inventory_items': [
                {
                  'id': 1,
                  'item_id': 'ITEM-01',
                  'name': 'Drop Cable',
                  'description': 'Outdoor fiber drop',
                  'category': 'Cables',
                  'supplier': 'SwitchFiber Supply',
                  'quantity': 200,
                },
              ],
              'inventory_categories': [
                {'id': 1, 'name': 'Cables', 'description': 'Fiber cables'},
              ],
              'inventory_logs': [
                {
                  'id': 10,
                  'item_id': 'ITEM-01',
                  'quantity': 5,
                  'requested_by': 'Tech',
                  'status': 'Approved',
                },
              ],
              'plans': [
                {
                  'id': 5,
                  'name': 'Fiber 1500',
                  'description': '100 Mbps',
                  'amount': 1500,
                  'discount_id': 0,
                },
              ],
              'lcp': [
                {'id': 2, 'name': 'LCP-01', 'description': 'Main Cabinet'},
              ],
              'nap': [
                {'id': 3, 'name': 'NAP-04', 'description': 'Pole 4'},
              ],
              'vlans': [
                {'id': 1000, 'name': '1000', 'description': 'Data VLAN'},
              ],
              'lcpnap': [
                {'id': 7, 'name': 'LCP-01 NAP-04', 'description': 'Merged'},
              ],
              'ports': [
                {'id': 8, 'name': 'P1', 'description': 'Port 1'},
              ],
              'lcpnap_ports': [
                {'id': 9, 'name': 'L1-P1', 'description': 'Box Port 1'},
              ],
              'routers': [
                {
                  'id': 11,
                  'name': 'ONT HG8145V5',
                  'description': 'Dual-band ONT',
                  'brand': 'Huawei',
                  'model': 'HG8145V5',
                },
              ],
            },
          });
        }

        expect(req.headers['If-None-Match'], '"lookups-v12-abc"');
        return _jsonResp(null, statusCode: 304);
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-rs256',
        });

        final service = LookupsSyncService(
          lookupsDao: appDb.lookupsDao,
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
        );

        final firstSynced = await service.sync();
        expect(firstSynced, isTrue);
        expect(
          await SecureStorageService.instance.read(AppConstants.keyLookupsEtag),
          '"lookups-v12-abc"',
        );

        // CatalogService reads offline SQLite lookup tables directly without REST.
        CatalogService.instance.attachLookupsDao(appDb.lookupsDao);
        final plans = await CatalogService.instance.getPlans();
        final routers = await CatalogService.instance.getRouters();
        final lcps = await CatalogService.instance.getLcps();
        final naps = await CatalogService.instance.getNaps();
        final ports = await CatalogService.instance.getPorts();
        final vlans = await CatalogService.instance.getVlans();
        final lcpNaps = await CatalogService.instance.getLcpNaps();
        final lcpNapPorts = await CatalogService.instance.getLcpNapPorts();
        final items = await CatalogService.instance.getInventoryItems();
        final categories =
            await CatalogService.instance.getInventoryCategories();
        final logs = await CatalogService.instance.getInventoryLogs();

        expect(plans.single.name, 'Fiber 1500');
        expect(routers.single.model, 'HG8145V5');
        expect(lcps.single.name, 'LCP-01');
        expect(naps.single.name, 'NAP-04');
        expect(ports.single.name, 'P1');
        expect(vlans.single['name'], '1000');
        expect(lcpNaps.single['name'], 'LCP-01 NAP-04');
        expect(lcpNapPorts.single['name'], 'L1-P1');
        expect(items.single.name, 'Drop Cable');
        expect(categories.single['name'], 'Cables');
        expect(logs.single['item_id'], 'ITEM-01');

        // Second sync triggers 304 Not Modified and preserves existing rows.
        final secondSynced = await service.sync();
        expect(secondSynced, isFalse);
        expect((await appDb.lookupsDao.getPlans()).length, 1);
      } finally {
        await appDb.close();
      }
    });

    test(
        '4. Offline LCPNapLocation UUID creation -> POST with Idempotency-Key -> local_id_map -> subsequent PATCH uses server ID',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final adapter = _MockV12Adapter((req) async {
        if (req.method == 'POST' && req.uri.path == '/api/LCPNapLocations') {
          return _jsonResp({'id': 8842});
        }
        return _jsonResp({'ok': true});
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-rs256',
        });

        final lcpRepo = LcpNapRepository(
          appDb.lcpNapLocationsDao,
          null,
          () => true,
          appDb.pendingAttachmentsDao,
          db.writeTransaction,
        );

        final created = await lcpRepo.createLocation(
          lcp: 'LCP 99',
          nap: 'NAP 05',
          coordinates: '14.6100, 121.0500',
          imageBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 8]),
        );
        expect(created, isNotNull);
        final localUuid = created!.rowId;
        expect(int.tryParse(localUuid), isNull);

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          localIdMap: appDb.localIdMapDao,
          syncConflicts: appDb.syncConflictsDao,
          errorLog: appDb.syncErrorLogsDao,
        );

        // Batch 1: POST /api/LCPNapLocations with Idempotency-Key: <localUuid>
        await connector.uploadData(db);
        expect(adapter.requests.length, 1);
        final postReq = adapter.requests[0];
        expect(postReq.method, 'POST');
        expect(postReq.uri.path, '/api/LCPNapLocations');
        expect(postReq.headers['Idempotency-Key'], localUuid);
        expect(postReq.rawText, contains('name="image"'));

        expect(
          await appDb.localIdMapDao.resolveServerId(
            entityType: 'lcp_nap_locations',
            localId: localUuid,
          ),
          '8842',
        );

        // Follow-up offline edit referencing the same UUID row.
        await db.execute(
          'UPDATE lcp_nap_locations SET street = ? WHERE id = ?',
          ['42 Fiber Ave', localUuid],
        );

        // Batch 2: PATCH /api/LCPNapLocations/8842 via local_id_map resolution
        await connector.uploadData(db);
        expect(adapter.requests.length, 2);
        final patchReq = adapter.requests[1];
        expect(patchReq.method, 'PATCH');
        expect(patchReq.uri.path, '/api/LCPNapLocations/8842');
        expect(patchReq.rawText, contains('42 Fiber Ave'));
      } finally {
        await appDb.close();
      }
    });

    test(
        '5. Auth 401 refresh failure preserves ps_crud, pending_attachments, and user_session until re-login',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      var rejectAuth = true;

      final adapter = _MockV12Adapter((req) async {
        if (rejectAuth) {
          return _jsonResp({'message': 'Token expired'}, statusCode: 401);
        }
        return _jsonResp({'ok': true});
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'expired-gw',
          AppConstants.keyJwtToken: 'expired-gw',
          AppConstants.keyUserSession:
              '{"id":7,"username":"tech7","fname":"Juan","lname":"Cruz","email":"juan@example.com","accessLevelId":2,"active":true}',
        });
        AuthSignals.instance.currentUser.value = UserModel(
          id: 7,
          username: 'tech7',
          fname: 'Juan',
          lname: 'Cruz',
          email: 'juan@example.com',
          accessLevelId: 2,
          active: true,
        );

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['777', 'T-777', 'Offline Sub', 'Addr 7', 'Done'],
        );
        final savedPath =
            await PhotoStorageService.instance.savePendingMediaBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 4, 5]),
        );
        await appDb.pendingAttachmentsDao.upsert(
          entityType: 'job_orders',
          entityId: '777',
          slotName: 'house_front',
          filePath: savedPath,
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          errorLog: appDb.syncErrorLogsDao,
          onUnauthorized: () => AuthSignals.instance.requireReauth(
            reason: 'Token expired. Please re-enter password.',
          ),
        );

        // Fails with 401: must trigger reauthRequired, clear ONLY tokens, and NEVER clear ps_crud/attachments/user_session.
        await expectLater(connector.uploadData(db), throwsException);

        expect(AuthSignals.instance.reauthRequired.value, isTrue);
        expect(await SecureStorageService.instance.getUserSession(), isNotNull);
        expect(await SecureStorageService.instance.getToken(), isNull);
        expect(await db.getNextCrudTransaction(), isNotNull);
        expect(await appDb.pendingAttachmentsDao.countPending(), 1);
        expect((await appDb.jobOrdersDao.getJobById(777))?.customerName,
            'Offline Sub');

        // Simulate in-place re-login supplying a fresh token, then drain queue.
        await SecureStorageService.instance
            .write(AppConstants.keyPowerSyncGatewayToken, 'fresh-gw-rs256');
        AuthSignals.instance.clearReauthPrompt();
        rejectAuth = false;

        await connector.uploadData(db);
        expect(await db.getNextCrudTransaction(), isNull);
        expect(await appDb.pendingAttachmentsDao.countPending(), 0);
      } finally {
        await appDb.close();
      }
    });

    testWidgets(
        '6. SyncConflictsScreen, ReauthDialog, JobHistoryView, and ServiceOrderHistoryView render at 200% text scale and dismiss conflict',
        (tester) async {
      late PowerSyncDatabase db;
      late AppDatabase appDb;
      late SyncConflictsSignals signals;
      late JobsSignals jobsSignals;
      late ServiceOrdersSignals soSignals;
      late String conflictId;

      await tester.runAsync(() async {
        db = await openLocalDb();
        appDb = AppDatabase(db);
        signals = SyncConflictsSignals(
          appDb.syncConflictsDao,
          pendingAttachmentsDao: appDb.pendingAttachmentsDao,
        );
        jobsSignals = JobsSignals(JobRepository(appDb.jobOrdersDao));
        soSignals = ServiceOrdersSignals(dao: appDb.serviceOrdersDao);

        await appDb.syncConflictsDao.recordConflict(
          entityType: 'job_orders',
          entityId: '501',
          reason: 'REASSIGNED',
          message: 'Order reassigned on dispatch portal.',
          serverSnapshot: jsonEncode({
            'assigned_email': 'dispatch.tech@switchfiber.ph',
            'status': 'Scheduled',
          }),
          localPayload: jsonEncode({'onsite_status': 'Done'}),
        );
        await signals.refresh();
        conflictId = signals.unresolvedConflicts.value.single.id;
      });

      try {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: SyncConflictsScreen(signals: signals),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        expect(find.text('JO #501'), findsOneWidget);
        expect(find.text('REASSIGNED'), findsOneWidget);

        final dismissBtn = find.byKey(ValueKey('dismiss_conflict_$conflictId'));
        await tester.ensureVisible(dismissBtn);
        await tester.pump();
        await tester.tap(dismissBtn);
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 100));

        final unresolvedCount = await tester.runAsync(
          () => appDb.syncConflictsDao.countUnresolved(),
        );
        expect(unresolvedCount, 0);
        expect(find.text('All Clear'), findsOneWidget);

        AuthSignals.instance.currentUser.value = UserModel(
          id: 7,
          username: 'tech7',
          fname: 'Juan',
          lname: 'Cruz',
          email: 'juan@example.com',
          accessLevelId: 2,
          active: true,
        );
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: JobHistoryView(jobsSignals: jobsSignals),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: ServiceOrderHistoryView(signals: soSignals),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ReauthDialog(authSignals: AuthSignals.instance),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(() async {
          await signals.dispose();
          jobsSignals.dispose();
          soSignals.dispose();
          await appDb.close();
        });
      }
    });
  });
}
