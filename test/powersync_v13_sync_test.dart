// Gene - Nov, 28, 2026: Comprehensive verification suite for PowerSync v13 & hardened gateway (coalesced batches, 409 serverRecord + cleanup + non-blocking loop, ETag lookups + Manila timestamps, 403 NOT_ASSIGNED, 429 RATE_LIMITED cooldown, offline UUID -> local_id_map, 401 preservation, and paginated history).
import 'dart:async';
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
import 'package:swithfiber_tech_ps/core/database/sql_values.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/lookups_sync_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_gateway_client.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/auth/screens/login_screen.dart';
import 'package:swithfiber_tech_ps/features/auth/services/auth_service.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/widgets/job_history_view.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';

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

class _MockV13Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(_CapturedRequest req) handler;
  final List<_CapturedRequest> requests = [];

  _MockV13Adapter(this.handler);

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
  var dbSeq = 0;

  setUp(() async {
    ApiClient.blockNetworkForTesting = true;
    tempDir = Directory.systemTemp.createTempSync('sf_v13_sync_test_');
    FlutterSecureStorage.setMockInitialValues({});
    PhotoStorageService.instance.setDirectoryForTesting(tempDir);
  });

  tearDown(() async {
    ApiClient.blockNetworkForTesting = false;
    PhotoStorageService.instance.setDirectoryForTesting(null);
    AuthSignals.instance.currentUser.value = null;
    AuthSignals.instance.clearReauthPrompt();
    AuthSignals.instance.rateLimitUntil.value = null;
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<PowerSyncDatabase> openReplicatedDb() async {
    final db = Zone.root.run(
      () => PowerSyncDatabase(
        schema: powerSyncReplicatedSchema,
        path: p.join(tempDir.path, 'v13_replicated_${++dbSeq}.db'),
      ),
    );
    await db.initialize();
    return db;
  }

  group('PowerSync v13 & Hardened Gateway Verification', () {
    test(
        '1. Coalesces multiple ps_crud writes + pending_attachments into 1 multipart PATCH and enforces v13 TEXT/INTEGER column types',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final adapter = _MockV13Adapter((req) async => _jsonResp({'ok': true}));

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-v13-rs256',
        });

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, plan_id, lcp_id, nap_id, vlan_id, status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            '401',
            'JO-401',
            'Elena Cruz',
            'Main Ave',
            '3',
            '1',
            '2',
            '100',
            'Scheduled'
          ],
        );

        final repo = JobRepository(
          appDb.jobOrdersDao,
          pendingAttachments: appDb.pendingAttachmentsDao,
          runInTransaction: appDb.writeTransaction,
          isReplicatedMode: () => true,
        );

        final photo1 =
            base64Encode(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1]));
        final photo2 =
            base64Encode(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 2]));

        await repo.saveCompletionReport(
          id: 401,
          onsiteStatus: 'Done',
          onsiteRemarks: 'First edit',
          modemRouterSN: 'SN-FIRST',
          routerModel: 'HG8145V5',
          lcp: 'LCP-01',
          port: 'P03',
          vlan: '120',
          vlanId: 120,
          planId: 7,
          speedtestImage: 'https://speed.example.com/401',
          setupImage: 'data:image/jpeg;base64,$photo1',
        );

        await repo.saveCompletionReport(
          id: 401,
          onsiteStatus: 'Done',
          onsiteRemarks: 'Final coalesced edit',
          modemRouterSN: 'SN-FINAL',
          routerModel: 'HG8145V5',
          lcp: 'LCP-02',
          port: 'P08',
          vlan: '1000',
          vlanId: 1000,
          planId: 9,
          speedtestImage: 'https://speed.example.com/401-v2',
          setupImage: 'data:image/jpeg;base64,$photo2',
          materialsUsed: {'Drop Cable (m)': 85},
        );

        // Verify service_orders v13 integer quantities round-trip cleanly.
        await appDb.serviceOrdersDao.insertOrUpdateOrder(
          ServiceOrderDto(
            id: 701,
            accountNumber: 'ACC-701',
            fullName: 'Mario Luna',
            contactNumber: '09170001122',
            emailAddress: 'mario@example.com',
            address: 'Oak St',
            materialsUsed: const {'Patch Cord': 3},
            serviceCharge: 250.5,
          ),
          synced: false,
        );
        final soRawRow = await appDb
            .getOptional('SELECT * FROM service_orders WHERE id = ?', ['701']);
        expect(soRawRow?['item_quantity_1'], 3);
        expect(soRawRow?['service_charge'], 250.5);

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://powersync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          syncConflicts: appDb.syncConflictsDao,
          localIdMap: appDb.localIdMapDao,
        );

        await connector.uploadData(db);

        final joReqs = adapter.requests
            .where((r) => r.uri.path == '/api/JobOrders/401')
            .toList();
        expect(joReqs.length, 1);
        expect(joReqs.single.method, 'PATCH');
        expect(joReqs.single.headers['Authorization'], 'Bearer gw-v13-rs256');
        expect(joReqs.single.headers['Idempotency-Key'], isNotEmpty);
        expect(joReqs.single.rawText, contains('Final coalesced edit'));
        expect(joReqs.single.rawText, contains('LCP-02'));
        expect(joReqs.single.rawText, contains('P08'));
        expect(joReqs.single.rawText, contains('1000'));
        expect(joReqs.single.rawText,
            contains('https://speed.example.com/401-v2'));
        expect(joReqs.single.rawText, contains('name="setup_image"'));
        expect(await appDb.pendingAttachmentsDao.countPending(), 0);
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await appDb.close();
      }
    });

    test(
        '2. Batch [Order A (409 REASSIGNED), Order B (200)] logs Order A serverRecord, cleans up attachments, still uploads Order B, and completes batch once at end',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final adapter = _MockV13Adapter((req) async {
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
        return _jsonResp({'ok': true});
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-v13-rs256',
        });

        final blockedPhoto =
            await PhotoStorageService.instance.savePendingMediaBytes(
          Uint8List.fromList([9, 8, 7, 6]),
          extension: 'jpg',
        );

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['101', 'JO-101', 'Order A', 'Addr A', 'In Progress'],
        );
        await appDb.pendingAttachmentsDao.upsert(
          entityType: 'job_orders',
          entityId: '101',
          slotName: 'setup_image',
          filePath: blockedPhoto,
        );
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['102', 'JO-102', 'Order B', 'Addr B', 'In Progress'],
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://powersync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          syncConflicts: appDb.syncConflictsDao,
          errorLog: appDb.syncErrorLogsDao,
        );

        await expectLater(connector.uploadData(db), completes);

        expect(
          adapter.requests.map((r) => r.uri.path).toList(),
          ['/api/JobOrders/101', '/api/JobOrders/102'],
        );
        expect(await db.getNextCrudTransaction(), isNull);
        expect(await appDb.pendingAttachmentsDao.countPending(), 0);
        expect(
          await appDb.pendingAttachmentsDao
              .getAllForEntity('job_orders', '101'),
          isEmpty,
        );
        expect(File(blockedPhoto).existsSync(), isFalse);

        final conflicts = await appDb.syncConflictsDao.getUnresolved();
        expect(conflicts.length, 1);
        expect(conflicts.single.entityId, '101');
        expect(conflicts.single.reason, 'REASSIGNED');
        expect(
          conflicts.single.decodedServerSnapshot['assigned_email'],
          'other.tech@switchfiber.ph',
        );
      } finally {
        await appDb.close();
      }
    });

    test(
        '3. GET /api/sync/lookups parses tables[name] on 200, respects 304 Not Modified, and preserves Manila timestamps without +8h shift',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      var callCount = 0;

      final adapter = _MockV13Adapter((req) async {
        expect(req.uri.path, '/api/sync/lookups');
        callCount++;
        if (callCount == 1) {
          return _jsonResp({
            'etag': '"lookups-v13-etag"',
            'fetchedAt': '2026-11-28T14:30:00.000',
            'tableEtags': {'ports': 'p1'},
            'tables': {
              'inventory_items': [],
              'inventory_categories': [],
              'inventory_logs': [],
              'plans': [
                {
                  'id': 10,
                  'name': 'Fiber 150',
                  'description': '150 Mbps',
                  'amount': 1499.0,
                }
              ],
              'lcp': [
                {'id': 1, 'name': 'LCP-North', 'description': 'North'}
              ],
              'nap': [
                {
                  'id': 2,
                  'name': 'NAP-09',
                  'description': 'Pole 9',
                  'created_date': '2026-11-28T14:30:00.000',
                }
              ],
              'vlans': [],
              'lcpnap': [],
              'ports': [
                {
                  'id': 5,
                  'name': 'PORT 05',
                  'description': 'Splitter',
                  'created_by_user_id': 'admin@switchfiber.ph',
                  'created_date': '2026-11-28T09:15:22.500',
                }
              ],
              'lcpnap_ports': [],
              'routers': [],
            },
          });
        }
        expect(req.headers['If-None-Match'], '"lookups-v13-etag"');
        return _jsonResp(null, statusCode: 304);
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-v13-rs256',
        });

        final gw = PowerSyncGatewayClient(
          baseUrl: 'https://gateway.example.com',
          dio: Dio()..httpClientAdapter = adapter,
        );

        final parsedManila = parseManilaLocalDate('2026-11-28T14:30:00.000');
        expect(parsedManila, isNotNull);
        expect(parsedManila!.isUtc, isFalse);
        expect(parsedManila.hour, 14);
        expect(parsedManila.minute, 30);

        final lookups = LookupsSyncService(
          gatewayClient: gw,
          lookupsDao: appDb.lookupsDao,
        );

        expect(await lookups.sync(), isTrue);
        expect(lookups.lastSyncedAt?.hour, 14);
        expect(lookups.lastSyncedAt?.minute, 30);
        expect(lookups.lastSyncedAt?.isUtc, isFalse);

        final naps = await appDb.lookupsDao.getNaps();
        expect(naps.single.name, 'NAP-09');
        expect(naps.single.createdDate?.hour, 14);
        expect(naps.single.createdDate?.minute, 30);
        expect(naps.single.createdDate?.isUtc, isFalse);

        final rawPorts = await appDb.getAll('SELECT * FROM ports');
        expect(rawPorts.single['created_by_user_id'], 'admin@switchfiber.ph');

        expect(await lookups.sync(), isFalse);
        expect(callCount, 2);
      } finally {
        await appDb.close();
      }
    });

    testWidgets(
        '4. 403 NOT_ASSIGNED halts GET retries cleanly and 429 RATE_LIMITED activates login cooldown without /Users/login fallback',
        (tester) async {
      final db = await tester.runAsync(() async => openReplicatedDb());
      final appDb = AppDatabase(db!);

      final prevAdapter = ApiClient.instance.dio.httpClientAdapter;
      final prevBaseUrl = ApiClient.instance.dio.options.baseUrl;
      var jobGetCalls = 0;
      var soGetCalls = 0;

      final apiMockAdapter = _MockV13Adapter((req) async {
        if (req.uri.path.contains('/JobOrders/')) {
          jobGetCalls++;
        } else if (req.uri.path.contains('/ServiceOrders/')) {
          soGetCalls++;
        }
        return _jsonResp({
          'error': 'Order is not assigned to your account.',
          'code': 'NOT_ASSIGNED',
        }, statusCode: 403);
      });

      final loginMockAdapter = _MockV13Adapter((req) async {
        expect(req.uri.path, '/api/Auth/login');
        return _jsonResp(
          {
            'error': 'Too many login attempts.',
            'code': 'RATE_LIMITED',
            'retryAfterSeconds': 45,
          },
          statusCode: 429,
          headers: {
            'Retry-After': ['45']
          },
        );
      });

      try {
        ApiClient.blockNetworkForTesting = false;
        ApiClient.instance.dio.httpClientAdapter = apiMockAdapter;
        ApiClient.instance.dio.options.baseUrl =
            'https://gateway.example.com/api';

        final repo = JobRepository(
          appDb.jobOrdersDao,
          api: DioJobOrdersApi(ApiClient.instance),
          isReplicatedMode: () => false,
        );
        final jobsSignals = JobsSignals(repo);
        final soSignals = ServiceOrdersSignals(
          api: ServiceOrdersApi(ApiClient.instance),
          dao: appDb.serviceOrdersDao,
          isReplicatedMode: () => false,
        );

        await tester.runAsync(() async {
          expect(await repo.fetchRemoteJobById(888), isNull);
          expect(await repo.fetchRemoteJobById(888), isNull);
          expect(await repo.getJobOrderImages(888), isNull);
          expect(jobGetCalls, 1);
          expect(jobsSignals.isJobNotAssigned(888), isTrue);

          expect(await soSignals.fetchRemoteOrderById(999), isNull);
          expect(await soSignals.fetchRemoteOrderById(999), isNull);
          expect(await soSignals.getServiceOrderImages(999), isNull);
          expect(soGetCalls, 1);
          expect(soSignals.isOrderNotAssigned(999), isTrue);
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: JobOrderDetailScreen(
              jobId: 888,
              jobsSignals: jobsSignals,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Order Reassigned'), findsOneWidget);

        // Now test 429 RATE_LIMITED -> no /Users/login fallback + countdown UI
        final authService = AuthService(
          api: ApiClient.instance,
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = loginMockAdapter,
          ),
        );
        RateLimitedAuthException? rateErr;
        await tester.runAsync(() async {
          try {
            await authService.login(username: 'tech', password: 'bad');
          } on RateLimitedAuthException catch (e) {
            rateErr = e;
          }
        });
        expect(rateErr, isNotNull);
        expect(rateErr!.retryAfterSeconds, 45);
        expect(loginMockAdapter.requests.single.uri.path, '/api/Auth/login');

        AuthSignals.instance.rateLimitUntil.value =
            DateTime.now().add(const Duration(seconds: 30));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const LoginScreen(),
          ),
        );
        await tester.pump();
        expect(find.textContaining('Wait '), findsOneWidget);

        AuthSignals.instance.rateLimitUntil.value = null;
        await tester.pump();
        await tester.runAsync(() async {
          await jobsSignals.dispose();
          soSignals.dispose();
        });
      } finally {
        ApiClient.blockNetworkForTesting = true;
        ApiClient.instance.dio.httpClientAdapter = prevAdapter;
        ApiClient.instance.dio.options.baseUrl = prevBaseUrl;
        await tester.runAsync(() => appDb.close());
      }
    });

    test(
        '5. Offline LCPNapLocation UUID -> POST with Idempotency-Key -> local_id_map -> subsequent PATCH uses numeric server ID',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);

      final adapter = _MockV13Adapter((req) async {
        if (req.method == 'POST' && req.uri.path == '/api/LCPNapLocations') {
          return _jsonResp({'id': 9104});
        }
        if (req.method == 'PATCH' &&
            req.uri.path == '/api/LCPNapLocations/9104') {
          return _jsonResp({'ok': true});
        }
        return _jsonResp({'error': 'Unexpected ${req.method} ${req.uri.path}'},
            statusCode: 400);
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-v13-rs256',
        });

        final plantRepo = LcpNapRepository(
          appDb.lcpNapLocationsDao,
          null,
          () => true,
          appDb.pendingAttachmentsDao,
          db.writeTransaction,
        );

        final created = await plantRepo.createLocation(
          lcp: 'LCP-88',
          nap: 'NAP-88',
          portTotal: 16,
          coordinates: '14.60, 121.02',
          city: 'Pasig',
        );
        expect(created, isNotNull);
        final localUuid = created!.rowId;
        expect(int.tryParse(localUuid), isNull);

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://powersync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          pendingAttachments: appDb.pendingAttachmentsDao,
          syncConflicts: appDb.syncConflictsDao,
          localIdMap: appDb.localIdMapDao,
        );

        await connector.uploadData(db);
        expect(adapter.requests.first.headers['Idempotency-Key'], localUuid);
        expect(
          await appDb.localIdMapDao.resolveServerId(
            entityType: 'lcp_nap_locations',
            localId: localUuid,
          ),
          '9104',
        );

        await db.execute(
          'UPDATE lcp_nap_locations SET street = ?, port_total = ? WHERE id = ?',
          ['42 Fiber Ave', 32, localUuid],
        );

        await connector.uploadData(db);
        expect(
          adapter.requests.map((r) => '${r.method} ${r.uri.path}').toList(),
          ['POST /api/LCPNapLocations', 'PATCH /api/LCPNapLocations/9104'],
        );
        expect(adapter.requests[1].rawText, contains('42 Fiber Ave'));
      } finally {
        await appDb.close();
      }
    });

    testWidgets(
        '6. Auth 401 preserves ps_crud/pending_attachments, History paginates SQLite LIMIT 50 OFFSET ?, and JobOrderDetailScreen pops on Complete',
        (tester) async {
      final db = await tester.runAsync(() async => openReplicatedDb());
      final appDb = AppDatabase(db!);

      try {
        await tester.runAsync(() async {
          FlutterSecureStorage.setMockInitialValues({
            AppConstants.keyPowerSyncGatewayToken: 'expired-gw',
            AppConstants.keyUserSession:
                '{"id":7,"username":"tech7","email":"juan@example.com"}',
          });

          await db.execute(
            'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
            'VALUES (?, ?, ?, ?, ?)',
            ['550', 'JO-550', 'Offline Auth Test', 'Addr 550', 'In Progress'],
          );

          final photoPath =
              await PhotoStorageService.instance.savePendingMediaBytes(
            Uint8List.fromList([7, 7, 7]),
            extension: 'jpg',
          );
          await appDb.pendingAttachmentsDao.upsert(
            entityType: 'job_orders',
            entityId: '550',
            slotName: 'setup_image',
            filePath: photoPath,
          );

          var unauthorizedCalled = false;
          final adapter401 = _MockV13Adapter(
            (_) async => _jsonResp({'error': 'Expired'}, statusCode: 401),
          );
          final connector = SwitchFiberBackendConnector(
            endpoint: 'https://powersync.example.com',
            gatewayClient: PowerSyncGatewayClient(
              baseUrl: 'https://gateway.example.com',
              dio: Dio()..httpClientAdapter = adapter401,
            ),
            pendingAttachments: appDb.pendingAttachmentsDao,
            onUnauthorized: () => unauthorizedCalled = true,
          );

          await expectLater(
            connector.uploadData(db),
            throwsA(isA<PowerSyncUploadException>()),
          );
          expect(unauthorizedCalled, isTrue);
          expect(await db.getNextCrudTransaction(), isNotNull);
          expect(await appDb.pendingAttachmentsDao.countPending(), 1);
          await db.execute('DELETE FROM ps_crud');
          await appDb.pendingAttachmentsDao
              .deleteForEntity('job_orders', '550');

          // Seed 55 completed jobs for pagination check + 1 open job with filed report for Complete pop test.
          for (var i = 1; i <= 55; i++) {
            final day = (i % 28) + 1;
            final iso = '2026-10-${day.toString().padLeft(2, '0')}T10:00:00';
            await appDb.jobOrdersDao.insertOrUpdateJob(
              JobOrderDto(
                id: 2000 + i,
                ticketNumber: 'JO-${2000 + i}',
                customerName: 'History Tech $i',
                address: 'Street $i',
                status: 'Completed',
                onsiteStatus: 'Done',
                assignedEmail: 'juan@example.com',
                modifiedDate: DateTime(2026, 10, day, 10),
                dateInstalled: DateTime.parse(iso),
              ),
              synced: true,
            );
          }

          await appDb.jobOrdersDao.insertOrUpdateJob(
            JobOrderDto(
              id: 3001,
              ticketNumber: 'JO-3001',
              customerName: 'Pop On Complete',
              address: 'First St',
              status: 'Scheduled',
              onsiteStatus: 'Done',
              modemRouterSN: 'SN-3001',
              clientSignature: 'data:image/png;base64,abc',
              startTimeStamp: DateTime.now().toUtc(),
              assignedEmail: 'juan@example.com',
            ),
            synced: true,
          );
        });

        final repo = JobRepository(appDb.jobOrdersDao);
        final jobsSignals = JobsSignals(repo);
        jobsSignals.setTechnicianEmail('juan@example.com');

        final page1 = await tester.runAsync(
          () => jobsSignals.getHistoryJobsPage(limit: 50, offset: 0),
        );
        final page2 = await tester.runAsync(
          () => jobsSignals.getHistoryJobsPage(limit: 50, offset: 50),
        );
        expect(page1!.length, 50);
        expect(page2!.length, 5);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: JobHistoryView(jobsSignals: jobsSignals)),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump();
        }
        final listScroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        listScroll.position.jumpTo(listScroll.position.maxScrollExtent - 250);
        await tester.pump();
        final loadMoreBtn = find.byKey(const ValueKey('job_history_load_more'));
        await tester.scrollUntilVisible(
          loadMoreBtn,
          100,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        if (loadMoreBtn.evaluate().isNotEmpty) {
          await tester.tap(loadMoreBtn);
        }
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump();
        }
        await tester.scrollUntilVisible(
          find.text('History Tech 28'),
          200,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('History Tech 28'), findsOneWidget);

        // Verify JobOrderDetailScreen pops cleanly when Complete job succeeds.
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => JobOrderDetailScreen(
                        jobId: 3001,
                        jobsSignals: jobsSignals,
                      ),
                    ),
                  ),
                  child: const Text('Open 3001'),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.tap(find.text('Open 3001'));
        await tester.pumpAndSettle();
        expect(find.byType(JobOrderDetailScreen), findsOneWidget);

        await tester.tap(find.text('Complete job'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complete'));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byType(JobOrderDetailScreen), findsNothing);
        expect(find.text('Open 3001'), findsOneWidget);

        await tester.runAsync(() => jobsSignals.dispose());
      } finally {
        await tester.runAsync(() => appDb.close());
      }
    });
  });
}
