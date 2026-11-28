// Gene - Nov, 27, 2026: End-to-end tests for PowerSync Server v11 schema alignment, DTO hydration, Gateway client, token minting, uploadData routing, and replicated-mode repositories.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_gateway_client.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';
// Gene - Nov, 28, 2026: Added PowerSyncService import for fresh-install credential cleanup tests.
import 'package:swithfiber_tech_ps/core/sync/powersync_service.dart';
import 'package:swithfiber_tech_ps/features/auth/services/auth_service.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';

class _RecordedRequest {
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final dynamic data;
  final Uint8List rawBytes;

  _RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.data,
    required this.rawBytes,
  });

  Map<String, dynamic>? get jsonBody {
    if (rawBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(rawBytes));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    if (data is Map<String, dynamic>) return data as Map<String, dynamic>;
    return null;
  }

  String get rawText => utf8.decode(rawBytes, allowMalformed: true);
}

typedef _AdapterHandler = Future<ResponseBody> Function(
  _RecordedRequest req,
);

class _MockGatewayAdapter implements HttpClientAdapter {
  final List<_RecordedRequest> requests = [];
  _AdapterHandler handler;

  _MockGatewayAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final chunks = <int>[];
    if (requestStream != null) {
      await for (final part in requestStream) {
        chunks.addAll(part);
      }
    }
    final rec = _RecordedRequest(
      method: options.method,
      uri: options.uri,
      headers: Map<String, dynamic>.from(options.headers),
      data: options.data,
      rawBytes: Uint8List.fromList(chunks),
    );
    requests.add(rec);
    return handler(rec);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(dynamic body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RejectingJobsApi extends JobOrdersApi {
  int fetchCalls = 0;
  int updateCalls = 0;
  int timingCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async {
    fetchCalls++;
    throw StateError(
        'REST fetchByStatus should not be called in replicated mode');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusAssigned({
    required String status,
    String? assignedEmail,
  }) async {
    fetchCalls++;
    throw StateError(
        'REST fetchByStatusAssigned should not be called in replicated mode');
  }

  @override
  Future<Map<String, dynamic>?> fetchById(int id) async => null;

  @override
  Future<void> update(int id, Map<String, dynamic> body) async {
    updateCalls++;
    throw StateError('REST update should not be called in replicated mode');
  }

  @override
  Future<void> createTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    DateTime? endTime,
    String? idempotencyKey,
  }) async {
    timingCalls++;
    throw StateError('Simulated offline timing error');
  }

  @override
  Future<void> updateTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    required DateTime endTime,
    String? idempotencyKey,
  }) async {
    timingCalls++;
    throw StateError('Simulated offline timing error');
  }
}

class _RejectingServiceOrdersApi extends ServiceOrdersApi {
  int fetchCalls = 0;
  int updateCalls = 0;
  int timingCalls = 0;

  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async {
    fetchCalls++;
    throw StateError('REST fetchServiceOrders should not be called');
  }

  @override
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    updateCalls++;
    throw StateError('REST updateServiceOrder should not be called');
  }

  @override
  Future<bool> createTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    DateTime? endTime,
    String? idempotencyKey,
  }) async {
    timingCalls++;
    throw StateError('Simulated upstream timing failure');
  }

  @override
  Future<bool> updateTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    required DateTime endTime,
    String? idempotencyKey,
  }) async {
    timingCalls++;
    throw StateError('Upstream column jo_id failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('ps_gateway_integration_');
    PhotoStorageService.instance.setDirectoryForTesting(tempDir);
  });

  tearDown(() {
    PhotoStorageService.instance.setDirectoryForTesting(null);
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<PowerSyncDatabase> openReplicatedDb() async {
    final db = PowerSyncDatabase(
      schema: powerSyncReplicatedSchema,
      path: p.join(
        tempDir.path,
        'replicated_${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await db.initialize();
    return db;
  }

  group('PowerSync Server v11 Schema & Hydration', () {
    test(
        'powerSyncReplicatedSchema validates and marks synced vs localOnly tables',
        () {
      expect(() => powerSyncReplicatedSchema.validate(), returnsNormally);
      expect(powerSyncReplicatedSchema.tables.length, 19);

      final jobs = powerSyncReplicatedSchema.tables
          .firstWhere((t) => t.name == 'job_orders');
      final repairs = powerSyncReplicatedSchema.tables
          .firstWhere((t) => t.name == 'service_orders');
      final plant = powerSyncReplicatedSchema.tables
          .firstWhere((t) => t.name == 'lcp_nap_locations');
      final errorLogs = powerSyncReplicatedSchema.tables
          .firstWhere((t) => t.name == 'sync_error_logs');
      final timingHistory = powerSyncReplicatedSchema.tables
          .firstWhere((t) => t.name == 'work_timing_history');

      expect(jobs.localOnly, isFalse);
      expect(repairs.localOnly, isFalse);
      expect(plant.localOnly, isFalse);
      expect(errorLogs.localOnly, isTrue);
      expect(timingHistory.localOnly, isTrue);

      final jobCols = jobs.columns.map((c) => c.name).toSet();
      expect(
        jobCols,
        containsAll([
          'address_coordinates',
          'installation_landmark',
          'usage_type',
          'renter',
          'duration',
          'applicant_email',
          'username',
          'connection_type',
          'visit_by',
          'visit_with',
          'visit_with_other',
          'remarks',
          'jo_remarks',
          'application_id',
          'lcp',
          'port',
          'vlan',
          'provider',
          'region',
          'location',
          'modified_by',
          'item_name_1',
          'item_quantity_1',
          'item_name_10',
          'item_quantity_10',
        ]),
      );

      final soCols = repairs.columns.map((c) => c.name).toSet();
      expect(
        soCols,
        containsAll([
          'support_remarks',
          'assigned_by',
          'assigned_date',
          'requested_by',
          'duration',
          'item_name_1',
          'item_quantity_1',
          'item_name_10',
          'item_quantity_10',
        ]),
      );

      expect(
          activePowerSyncSchema(replicated: true), powerSyncReplicatedSchema);
      expect(activePowerSyncSchema(replicated: false), powerSyncSchema);
    });

    test(
        'JobOrderDto.fromRow hydrates v11 columns and materials without raw_json',
        () {
      final job = JobOrderDto.fromRow({
        'id': '4328',
        'ticket_number': 'ACC-4328',
        'customer_name': 'Juan Dela Cruz',
        'address': '123 Fiber St',
        'applicant_email': 'subscriber@example.com',
        'username': 'pppoe_juan',
        'connection_type': 'Fiber',
        'visit_by': 'Tech Alpha',
        'visit_with': 'Tech Beta',
        'visit_with_other': 'Helper One',
        'address_coordinates': '14.5800, 121.0500',
        'installation_landmark': 'Near Blue Gate',
        'remarks': 'Pole 4 drop',
        'application_id': 'APP-4328',
        'start_timestamp': '2026-11-27T08:00:00Z',
        'end_timestamp': '2026-11-27T09:15:00Z',
        'duration': '75',
        'item_name_1': 'Drop Cable (m)',
        'item_quantity_1': '60',
        'item_name_2': 'SC/APC Fast Connector',
        'item_quantity_2': '2',
        'status': 'Scheduled',
        'raw_json': null,
        'is_synced': null,
      });

      expect(job.id, 4328);
      expect(job.subscriberEmail, 'subscriber@example.com');
      expect(job.username, 'pppoe_juan');
      expect(job.connectionType, 'Fiber');
      expect(job.visitBy, 'Tech Alpha');
      expect(job.visitWith, 'Tech Beta');
      expect(job.visitWithOther, 'Helper One');
      expect(job.latLng?.latitude, closeTo(14.58, 0.0001));
      expect(job.installationLandmark, 'Near Blue Gate');
      expect(job.landmarkRemarks, 'Pole 4 drop');
      expect(job.applicationId, 'APP-4328');
      expect(job.duration, '75');
      expect(job.materialsUsed, {
        'Drop Cable (m)': 60,
        'SC/APC Fast Connector': 2,
      });
      expect(job.isSynced, isTrue);
    });

    test(
        'ServiceOrderDto.fromRow hydrates support_remarks and item columns without raw_json',
        () {
      final so = ServiceOrderDto.fromRow({
        'id': '869',
        'account_number': 'ACC-869',
        'full_name': 'Maria Clara',
        'contact_number': '09170001111',
        'email_address': 'maria@example.com',
        'address': '45 Optical Rd',
        'support_remarks': 'Check splitter port 3',
        'item_name_1': 'Cable Tie',
        'item_quantity_1': '4',
        'item_name_2': 'SC/APC Fast Connector',
        'item_quantity_2': '2',
        'raw_json': null,
        'materials_used_json': null,
        'is_synced': null,
      });

      expect(so.id, 869);
      expect(so.supportRemarks, 'Check splitter port 3');
      expect(so.materialsUsed, {
        'Cable Tie': 4,
        'SC/APC Fast Connector': 2,
      });
      expect(so.isSynced, isTrue);
    });
  });

  group('PowerSyncGatewayClient & Token Minting', () {
    test(
        'normalizes baseUrl and executes login, token mint, batch, and multipart',
        () async {
      final adapter = _MockGatewayAdapter((req) async {
        if (req.uri.path == '/api/Auth/login') {
          return _jsonResponse({
            'email': 'Tech.User@Example.com',
            'token': 'gw-session-jwt',
            'tokenExpiresAt': '2026-11-28T10:00:00Z',
            'powersync': {
              'token': 'ps-rs256-jwt',
              'expiresAt': '2026-11-28T09:00:00Z',
              'userId': 'Tech.User@Example.com',
              'endpoint': 'https://sync.example.com',
            },
          });
        }
        if (req.uri.path == '/api/Auth/powersync-token') {
          return _jsonResponse({
            'token': 'ps-refreshed-jwt',
            'expiresAt': '2026-11-28T12:00:00Z',
            'userId': 'tech.user@example.com',
            'endpoint': 'https://sync.example.com',
          });
        }
        return _jsonResponse({'ok': true});
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final client = PowerSyncGatewayClient(
        baseUrl: 'https://gateway.example.com/api/',
        dio: dio,
      );
      expect(client.baseUrl, 'https://gateway.example.com');
      expect(client.hasBaseUrl, isTrue);

      final loginRes = await client.login(
        username: 'tech_user',
        password: 'example-password',
      );
      expect(loginRes.email, 'tech.user@example.com');
      expect(loginRes.sessionToken, 'gw-session-jwt');
      expect(loginRes.powerSync?.token, 'ps-rs256-jwt');

      final tokenRes = await client.fetchPowerSyncToken(
        bearerToken: 'gw-session-jwt',
      );
      expect(tokenRes.token, 'ps-refreshed-jwt');
      expect(tokenRes.userId, 'tech.user@example.com');

      await client.uploadBatch(
        operations: [
          {
            'op': 'PATCH',
            'table': 'job_orders',
            'id': '4328',
            'data': {'onsite_status': 'Done'},
          },
        ],
        bearerToken: 'gw-session-jwt',
      );

      await client.uploadMultipart(
        method: 'POST',
        apiPath: '/api/LCPNapLocations',
        formData: FormData.fromMap({
          'lcp': 'LCP 01',
          'Image': MultipartFile.fromBytes([1, 2, 3], filename: 'image.jpg'),
        }),
        bearerToken: 'gw-session-jwt',
        idempotencyKey: 'offline-99',
      );

      expect(adapter.requests.length, 4);
      expect(adapter.requests[1].headers['Authorization'],
          'Bearer gw-session-jwt');
      expect(adapter.requests[2].uri.toString(),
          'https://gateway.example.com/api/powersync/upload');
      expect(adapter.requests[3].headers['Idempotency-Key'], 'offline-99');
    });

    test(
        'fetchCredentials mints, caches, reuses, refreshes near expiry, and clears on 401',
        () async {
      var mintCount = 0;
      var return401 = false;
      final futureExp = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 12))
          .toIso8601String();

      final adapter = _MockGatewayAdapter((req) async {
        if (req.uri.path == '/api/Auth/powersync-token') {
          if (return401) {
            return _jsonResponse({'message': 'Token expired'}, statusCode: 401);
          }
          mintCount++;
          return _jsonResponse({
            'token': 'rs256-token-$mintCount',
            'expiresAt': futureExp,
            'userId': 'Mixed.Tech@Example.com',
            'endpoint': 'https://sync.example.com',
          });
        }
        return _jsonResponse({'ok': true});
      });

      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyJwtToken: 'legacy-bearer',
        AppConstants.keyUserSession:
            '{"id":2,"username":"tech","email":"Mixed.Tech@Example.com"}',
      });

      final gwClient = PowerSyncGatewayClient(
        baseUrl: 'https://gateway.example.com',
        dio: Dio()..httpClientAdapter = adapter,
      );
      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://sync.example.com',
        gatewayClient: gwClient,
      );

      // 1. Mints token on first fetch
      final c1 = await connector.fetchCredentials();
      expect(c1, isNotNull);
      expect(c1!.token, 'rs256-token-1');
      expect(c1.userId, 'mixed.tech@example.com');
      expect(mintCount, 1);

      // 2. Reuses cached unexpired token without hitting network
      final c2 = await connector.fetchCredentials();
      expect(c2?.token, 'rs256-token-1');
      expect(mintCount, 1);

      // 3. Refreshes when within 5-minute expiry window
      await SecureStorageService.instance.write(
        AppConstants.keyPowerSyncTokenExpiresAt,
        DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 2))
            .toIso8601String(),
      );
      final c3 = await connector.fetchCredentials();
      expect(c3?.token, 'rs256-token-2');
      expect(mintCount, 2);

      // 4. Clears cached PowerSync token and returns null on 401
      await SecureStorageService.instance.write(
        AppConstants.keyPowerSyncTokenExpiresAt,
        DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      );
      return401 = true;
      final c4 = await connector.fetchCredentials();
      expect(c4, isNull);
      expect(
        await SecureStorageService.instance
            .read(AppConstants.keyPowerSyncToken),
        isNull,
      );
    });
  });

  group('SwitchFiberBackendConnector uploadData Gateway Routing', () {
    test('batches scalar PATCH ops, strips local fields, and computes duration',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final adapter =
          _MockGatewayAdapter((req) async => _jsonResponse({'ok': true}));

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-jwt',
        });

        await db.writeTransaction((tx) async {
          await tx.execute(
            'INSERT INTO job_orders (id, ticket_number, customer_name, address, status, '
            'onsite_status, box_reading_image, setup_image, start_timestamp, end_timestamp, '
            'optical_power, raw_json, is_synced, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              '4328',
              'ACC-4328',
              'Juan Dela Cruz',
              '123 Main',
              'Completed',
              'Done',
              'uploads/existing_box.jpg',
              '', // explicit photo clear
              '2026-11-27T08:00:00Z',
              '2026-11-27T08:45:00Z',
              -19.2,
              '{"ignored":true}',
              0,
              '2026-11-27T08:45:00Z',
            ],
          );
          await tx.execute(
            'INSERT INTO service_orders (id, account_number, full_name, address, '
            'visit_status, start_timestamp, stop_timestamp, materials_used_json, '
            'raw_json, is_synced, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              '869',
              'ACC-869',
              'Maria Clara',
              '45 Fiber Rd',
              'Done',
              '2026-11-27T10:00:00Z',
              '2026-11-27T10:30:00Z',
              '{"Tape":1}',
              '{"ignored":true}',
              0,
              '2026-11-27T10:30:00Z',
            ],
          );
        });

        final uploaded = <(String, int)>[];
        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          errorLog: appDb.syncErrorLogsDao,
          onEntityUploaded: (table, id) => uploaded.add((table, id)),
        );

        await connector.uploadData(db);

        expect(adapter.requests.length, 2);

        final joReq = adapter.requests[0];
        expect(joReq.method, 'PATCH');
        expect(joReq.uri.path, '/api/JobOrders/4328');
        expect(joReq.headers['Authorization'], 'Bearer gw-jwt');
        expect((joReq.headers['Idempotency-Key'] ?? '').toString(), isNotEmpty);
        expect(joReq.rawText, contains('name="onsite_status"'));
        expect(joReq.rawText, contains('Done'));
        expect(joReq.rawText, contains('name="duration"'));
        expect(joReq.rawText, contains('45'));
        expect(joReq.rawText, contains('name="delete_setup_image"'));
        expect(joReq.rawText, isNot(contains('existing_box.jpg')));
        expect(joReq.rawText, isNot(contains('name="optical_power"')));
        expect(joReq.rawText, isNot(contains('name="raw_json"')));
        expect(joReq.rawText, isNot(contains('name="is_synced"')));
        expect(joReq.rawText, isNot(contains('name="updated_at"')));

        final soReq = adapter.requests[1];
        expect(soReq.method, 'PATCH');
        expect(soReq.uri.path, '/api/ServiceOrders/869');
        expect(soReq.rawText, contains('name="duration"'));
        expect(soReq.rawText, contains('30'));
        expect(soReq.rawText, isNot(contains('name="materials_used_json"')));

        expect(uploaded, [('job_orders', 4328), ('service_orders', 869)]);
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await appDb.close();
      }
    });

    test(
        'routes captured photos to multipart PATCH and offline plant creates to POST with Idempotency-Key',
        () async {
      final db = await openReplicatedDb();
      final adapter =
          _MockGatewayAdapter((req) async => _jsonResponse({'id': 1723}));

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-jwt',
        });

        final photoFile = File(p.join(tempDir.path, 'box_photo.jpg'));
        photoFile.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, '
          'onsite_status, box_reading_image, setup_image, port_label_image) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            '4328',
            'ACC-4328',
            'Juan',
            '123 St',
            'Done',
            photoFile.path,
            '',
            'uploads/keep_me.jpg',
          ],
        );

        await db.execute(
          'INSERT INTO lcp_nap_locations (id, lcp, nap, lcp_nap, port_total, '
          'coordinates, image) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'local-uuid-42',
            'LCP 09',
            'NAP 03',
            'LCP 09 NAP 03',
            16,
            '14.60, 121.10',
            photoFile.path,
          ],
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
        );

        await connector.uploadData(db);

        expect(adapter.requests.length, 2);

        final joReq = adapter.requests[0];
        expect(joReq.method, 'PATCH');
        expect(joReq.uri.path, '/api/JobOrders/4328');
        expect(joReq.rawText, contains('name="box_reading_image"'));
        expect(joReq.rawText, contains('name="delete_setup_image"'));
        expect(joReq.rawText, isNot(contains('keep_me.jpg')));

        final plantReq = adapter.requests[1];
        expect(plantReq.method, 'POST');
        expect(plantReq.uri.path, '/api/LCPNapLocations');
        expect(plantReq.headers['Idempotency-Key'], 'local-uuid-42');
        expect(plantReq.rawText, contains('name="image"'));

        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });

    test(
        'routes non-numeric UUID lcp_nap_locations ID to POST /api/LCPNapLocations with Idempotency-Key',
        () async {
      final db = await openReplicatedDb();
      final adapter =
          _MockGatewayAdapter((req) async => _jsonResponse({'id': 1777}));

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-jwt',
        });

        await db.execute(
          'INSERT INTO lcp_nap_locations (id, lcp, nap, lcp_nap, port_total, coordinates) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          [
            'local-uuid-77',
            'LCP 07',
            'NAP 07',
            'LCP 07 NAP 07',
            8,
            '14.51, 121.02',
          ],
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
        );

        await connector.uploadData(db);

        final req = adapter.requests.single;
        expect(req.method, 'POST');
        expect(req.uri.path, '/api/LCPNapLocations');
        expect(req.headers['Idempotency-Key'], 'local-uuid-77');
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });

    test('refreshes token once on 401 and retries upload cleanly', () async {
      final db = await openReplicatedDb();
      var uploadAttempts = 0;

      final adapter = _MockGatewayAdapter((req) async {
        if (req.uri.path == '/api/JobOrders/500') {
          uploadAttempts++;
          if (uploadAttempts == 1) {
            return _jsonResponse({'message': 'Expired'}, statusCode: 401);
          }
          return _jsonResponse({'ok': true});
        }
        if (req.uri.path == '/api/Auth/refresh') {
          return _jsonResponse({
            'token': 'fresh-token-after-401',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 12))
                .toIso8601String(),
            'powersync': {
              'token': 'ps-token-after-401',
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 12))
                  .toIso8601String(),
              'userId': 'tech@example.com',
              'endpoint': 'https://sync.example.com',
            },
          });
        }
        if (req.uri.path == '/api/Auth/powersync-token') {
          return _jsonResponse({
            'token': 'fresh-token-after-401',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 12))
                .toIso8601String(),
            'userId': 'tech@example.com',
            'endpoint': 'https://sync.example.com',
          });
        }
        return _jsonResponse({'ok': true});
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'stale-gw-jwt',
        });

        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['500', 'T-500', 'Test Sub', 'Addr', 'Completed'],
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
        );

        await connector.uploadData(db);

        expect(uploadAttempts, 2);
        expect(
          adapter.requests.last.headers['Authorization'],
          'Bearer fresh-token-after-401',
        );
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });

    test(
        'logs permanent 400 and completes tx, while transient 503 preserves ps_crud',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      var statusToReturn = 400;

      final adapter = _MockGatewayAdapter((req) async {
        return _jsonResponse({'message': 'Rejected $statusToReturn'},
            statusCode: statusToReturn);
      });

      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyPowerSyncGatewayToken: 'gw-jwt',
        });

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
          gatewayClient: PowerSyncGatewayClient(
            baseUrl: 'https://gateway.example.com',
            dio: Dio()..httpClientAdapter = adapter,
          ),
          errorLog: appDb.syncErrorLogsDao,
        );

        // 1. Permanent 400 -> logged & completed
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['701', 'T-701', 'Bad Row', 'Addr', 'Completed'],
        );
        await connector.uploadData(db);
        expect(await db.getNextCrudTransaction(), isNull);
        var logs = await appDb.syncErrorLogsDao.getAll();
        expect(logs.length, 1);
        expect(logs.first.statusCode, 400);
        expect(logs.first.entityId, 701);

        // 2. Transient 503 -> logged & bubbles up preserving ps_crud
        statusToReturn = 503;
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['702', 'T-702', 'Retry Row', 'Addr', 'Completed'],
        );
        await expectLater(
          () => connector.uploadData(db),
          throwsA(isA<PowerSyncUploadException>()),
        );
        final pending = await db.getNextCrudTransaction();
        expect(pending, isNotNull);
        expect(pending!.crud.first.id, '702');
        logs = await appDb.syncErrorLogsDao.getAll();
        expect(logs.length, 2);
        expect(logs.first.statusCode, 503);
      } finally {
        await appDb.close();
      }
    });

    test(
        'throws StateError and preserves ps_crud when gateway URL and upload hooks are absent',
        () async {
      final db = await openReplicatedDb();

      try {
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['703', 'T-703', 'Unconfigured Gateway Row', 'Addr', 'Completed'],
        );

        final connector = SwitchFiberBackendConnector(
          endpoint: 'https://sync.example.com',
        );
        expect(connector.hasEndpoint, isTrue);
        expect(connector.hasGateway, isFalse);

        await expectLater(
          () => connector.uploadData(db),
          throwsStateError,
        );

        final pending = await db.getNextCrudTransaction();
        expect(pending, isNotNull);
        expect(pending!.crud.first.id, '703');
      } finally {
        await db.close();
      }
    });
  });

  group('AuthService Gateway Login & Credential Cleanup', () {
    late HttpClientAdapter originalApiAdapter;
    late bool originalNetworkBlock;

    setUp(() {
      originalApiAdapter = ApiClient.instance.dio.httpClientAdapter;
      originalNetworkBlock = ApiClient.blockNetworkForTesting;
    });

    tearDown(() {
      ApiClient.instance.dio.httpClientAdapter = originalApiAdapter;
      ApiClient.blockNetworkForTesting = originalNetworkBlock;
    });

    test(
        'AuthService.login enriches missing email and persists PowerSync tokens; clearCredentials wipes them',
        () async {
      ApiClient.blockNetworkForTesting = false;
      ApiClient.instance.dio.httpClientAdapter =
          _MockGatewayAdapter((req) async {
        return _jsonResponse({
          'token': 'legacy-api-jwt',
          'user': {
            'id': 2,
            'username': 'tech_demo',
            'fname': 'Demo',
            'lname': 'Tech',
            'accesslevel_id': 8,
            'active': true,
          },
        });
      });

      final gwClient = PowerSyncGatewayClient(
        baseUrl: 'https://gateway.example.com',
        dio: Dio()
          ..httpClientAdapter = _MockGatewayAdapter((req) async {
            return _jsonResponse({
              'email': 'demo.tech@example.com',
              'token': 'gw-session-jwt',
              'powersync': {
                'token': 'ps-rs256-jwt',
                'expiresAt': '2026-11-28T10:00:00Z',
                'userId': 'demo.tech@example.com',
                'endpoint': 'https://sync.example.com',
              },
            });
          }),
      );

      final auth = AuthService(gatewayClient: gwClient);
      final user = await auth.login(
        username: 'tech_demo',
        password: 'example-password',
      );

      expect(user.email, 'demo.tech@example.com');
      final storage = SecureStorageService.instance;
      expect(await storage.getToken(), 'legacy-api-jwt');
      expect(await storage.read(AppConstants.keyPowerSyncGatewayToken),
          'gw-session-jwt');
      expect(
          await storage.read(AppConstants.keyPowerSyncToken), 'ps-rs256-jwt');
      expect(await storage.read(AppConstants.keyPowerSyncUserId),
          'demo.tech@example.com');
      expect(await storage.read(AppConstants.keyPowerSyncEndpoint),
          'https://sync.example.com');

      await storage.clearCredentials();
      expect(await storage.getToken(), isNull);
      expect(await storage.read(AppConstants.keyPowerSyncGatewayToken), isNull);
      expect(await storage.read(AppConstants.keyPowerSyncToken), isNull);
      expect(
          await storage.read(AppConstants.keyPowerSyncTokenExpiresAt), isNull);
      expect(await storage.read(AppConstants.keyPowerSyncUserId), isNull);
      expect(await storage.read(AppConstants.keyPowerSyncEndpoint), isNull);
    });
  });

  group('Replicated Mode Repositories & Signals', () {
    test(
        'JobRepository, ServiceOrdersSignals, and LcpNapRepository skip REST pulls/pushes and queue in ps_crud',
        () async {
      final db = await openReplicatedDb();
      final appDb = AppDatabase(db);
      final jobsApi = _RejectingJobsApi();
      final soApi = _RejectingServiceOrdersApi();

      try {
        final jobRepo = JobRepository(
          appDb.jobOrdersDao,
          api: jobsApi,
          timingHistory: appDb.workTimingHistoryDao,
          isReplicatedMode: () => true,
        );
        final soSignals = ServiceOrdersSignals(
          api: soApi,
          dao: appDb.serviceOrdersDao,
          timingHistory: appDb.workTimingHistoryDao,
          isReplicatedMode: () => true,
        );
        final plantRepo = LcpNapRepository(
          appDb.lcpNapLocationsDao,
          ApiClient.instance,
          () => true,
        );

        // Seed rows directly into replicated tables and clear initial sync queue
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, address, status) '
          'VALUES (?, ?, ?, ?, ?)',
          ['10', 'JO-10', 'Alice', '1 St', 'Scheduled'],
        );
        await db.execute(
          'INSERT INTO service_orders (id, account_number, full_name, contact_number, '
          'email_address, address, support_status, concern) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            '20',
            'SO-20',
            'Bob',
            '0917',
            'bob@example.com',
            '2 St',
            'Open',
            'Slow'
          ],
        );
        await db.execute(
          'INSERT INTO lcp_nap_locations (id, lcp, nap, lcp_nap, port_total, image) '
          'VALUES (?, ?, ?, ?, ?, ?)',
          ['30', 'LCP 1', 'NAP 1', 'LCP 1 - NAP 1', 8, 'uploads/keep_ext.jpg'],
        );
        while (true) {
          final tx = await db.getNextCrudTransaction();
          if (tx == null) break;
          await tx.complete();
        }

        // Pulls are no-ops
        await jobRepo.fetchRemoteJobs(technicianEmail: 'tech@example.com');
        await soSignals.fetchRemote(technicianEmail: 'tech@example.com');
        await plantRepo.fetchRemoteLocations();
        expect(jobsApi.fetchCalls, 0);
        expect(soApi.fetchCalls, 0);

        // Mutations queue locally in ps_crud without calling REST PUT
        await jobRepo.startJobTiming(10, techId: 'tech@example.com');
        final compRes =
            await jobRepo.completeJob(10, technicianEmail: 'tech@example.com');
        expect(compRes.success, isTrue);
        expect(jobsApi.updateCalls, 0);

        final existingSo = await appDb.serviceOrdersDao.getOrderById(20);
        final startErr = await soSignals.startOrder(existingSo!, techId: '2');
        expect(startErr, isNull);
        final startedSo = await appDb.serviceOrdersDao.getOrderById(20);
        final finErr = await soSignals.finishOrder(startedSo!, techId: '2');
        expect(finErr, isNull);
        expect(soApi.updateCalls, 0);

        final existingPlant =
            await appDb.lcpNapLocationsDao.getLocationById(30);
        await plantRepo.uploadLcpNapPhotos(
          locationId: 30,
          location: existingPlant!,
          image2Bytes: Uint8List.fromList([1, 2, 3, 4]),
        );
        final updatedPlant = await appDb.lcpNapLocationsDao.getLocationById(30);
        expect(updatedPlant?.image, 'uploads/keep_ext.jpg');
        expect(updatedPlant?.image2, isNotNull);

        final createdOffline = await plantRepo.createLocation(
          lcp: 'LCP 99',
          nap: 'NAP 99',
          coordinates: '14.5, 121.1',
        );
        expect(createdOffline, isNotNull);
        expect(createdOffline!.id, lessThan(0));

        // Verify CRUD transactions are queued in ps_crud
        final crudCount = await db.get('SELECT count(*) AS c FROM ps_crud');
        expect((crudCount['c'] as int), greaterThanOrEqualTo(5));

        soSignals.dispose();
      } finally {
        await appDb.close();
      }
    });

    // Gene - Nov, 28, 2026: Regression tests for first-open empty queue/session deadlock and 401 credential fallback.
    test(
        'clearStaleCredentialsOnFreshInstall clears orphaned keychain on fresh install but preserves upgrades',
        () async {
      final freshDir =
          await Directory.systemTemp.createTemp('sf_fresh_install_test_');
      final upgradeDir =
          await Directory.systemTemp.createTemp('sf_upgrade_install_test_');
      try {
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyUserSession:
              '{"id":2,"username":"tech","email":"tech@example.com"}',
          AppConstants.keyJwtToken: 'orphaned-jwt',
          AppConstants.keyPowerSyncGatewayToken: 'orphaned-gw',
        });

        await PowerSyncService.clearStaleCredentialsOnFreshInstall(
          supportDir: freshDir,
          storage: SecureStorageService.instance,
        );

        expect(await SecureStorageService.instance.getUserSession(), isNull);
        expect(await SecureStorageService.instance.getToken(), isNull);
        expect(
          File(p.join(freshDir.path, PowerSyncService.installMarkerFilename))
              .existsSync(),
          isTrue,
        );

        // Repeat launch preserves newly logged-in session because install marker exists.
        await SecureStorageService.instance.saveUserSession(
            '{"id":2,"username":"tech","email":"tech@example.com"}');
        await SecureStorageService.instance.saveToken('fresh-jwt');
        await PowerSyncService.clearStaleCredentialsOnFreshInstall(
          supportDir: freshDir,
          storage: SecureStorageService.instance,
        );
        expect(await SecureStorageService.instance.getToken(), 'fresh-jwt');

        // Existing install upgrading from switchfiber_powersync.db preserves credentials.
        await File(p.join(upgradeDir.path, 'switchfiber_powersync.db'))
            .writeAsString('existing-db');
        FlutterSecureStorage.setMockInitialValues({
          AppConstants.keyUserSession:
              '{"id":5,"username":"upgrader","email":"upgrader@example.com"}',
          AppConstants.keyJwtToken: 'upgrade-jwt',
        });
        await PowerSyncService.clearStaleCredentialsOnFreshInstall(
          supportDir: upgradeDir,
          storage: SecureStorageService.instance,
        );
        expect(await SecureStorageService.instance.getUserSession(), isNotNull);
        expect(await SecureStorageService.instance.getToken(), 'upgrade-jwt');
        expect(
          File(p.join(upgradeDir.path, PowerSyncService.installMarkerFilename))
              .existsSync(),
          isTrue,
        );
      } finally {
        await freshDir.delete(recursive: true);
        await upgradeDir.delete(recursive: true);
      }
    });

    test(
        'AuthService.restoreSession rejects tokenless user_session and preserves email fallback when token exists',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyUserSession:
            '{"id":7,"username":"tech7","fname":"T","lname":"7","email":"tech7@example.com","accessLevelId":2,"active":true}',
      });
      final authService = AuthService();
      final orphanedUser = await authService.restoreSession();
      expect(orphanedUser, isNull);
      expect(await SecureStorageService.instance.getUserSession(), isNull);

      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyUserSession:
            '{"id":7,"username":"tech7","fname":"T","lname":"7","email":"","accessLevelId":2,"active":true}',
        AppConstants.keyJwtToken: 'valid-jwt',
        AppConstants.keyPowerSyncUserId: 'tech7@example.com',
      });
      final validUser = await authService.restoreSession();
      expect(validUser, isNotNull);
      expect(validUser!.email, 'tech7@example.com');
    });

    test(
        'fetchCredentials falls back when gateway token returns 401 and invokes onUnauthorized if all tokens fail',
        () async {
      final exp = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 6))
          .toIso8601String();
      var rejectAll = false;
      var unauthorizedCalls = 0;

      final adapter = _MockGatewayAdapter((req) async {
        if (req.uri.path == '/api/Auth/powersync-token') {
          if (rejectAll) {
            return _jsonResponse({'message': 'Expired'}, statusCode: 401);
          }
          final auth = req.headers['Authorization']?.toString() ?? '';
          if (auth == 'Bearer gw-expired') {
            return _jsonResponse({'message': 'Expired'}, statusCode: 401);
          }
          if (auth == 'Bearer legacy-valid') {
            return _jsonResponse({
              'token': 'minted-from-fallback',
              'expiresAt': exp,
              'userId': 'tech@example.com',
              'endpoint': 'https://sync.example.com',
            });
          }
        }
        return _jsonResponse({'ok': true});
      });

      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyPowerSyncGatewayToken: 'gw-expired',
        AppConstants.keyJwtToken: 'legacy-valid',
        AppConstants.keyUserSession:
            '{"id":2,"username":"tech","email":"tech@example.com"}',
      });

      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://sync.example.com',
        gatewayClient: PowerSyncGatewayClient(
          baseUrl: 'https://gateway.example.com',
          dio: Dio()..httpClientAdapter = adapter,
        ),
        onUnauthorized: () => unauthorizedCalls++,
      );

      final recovered = await connector.fetchCredentials();
      expect(recovered, isNotNull);
      expect(recovered!.token, 'minted-from-fallback');
      expect(
        await SecureStorageService.instance
            .read(AppConstants.keyPowerSyncGatewayToken),
        isNull,
      );
      expect(unauthorizedCalls, 0);

      // Now expire cached token and fail all remaining bearers -> onUnauthorized fires.
      await SecureStorageService.instance.write(
        AppConstants.keyPowerSyncTokenExpiresAt,
        DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      );
      rejectAll = true;
      final failed = await connector.fetchCredentials();
      expect(failed, isNull);
      expect(unauthorizedCalls, 1);
      expect(await SecureStorageService.instance.getToken(), isNull);
    });
  });
}
