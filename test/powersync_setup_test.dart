import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('PowerSync Client Setup Tests', () {
    test(
        'PowerSync endpoint and dev key default to empty without --dart-define',
        () {
      expect(AppConstants.defaultPowerSyncEndpoint, isEmpty);
      expect(AppConstants.devSecretKey, isEmpty);
    });

    test('PowerSync schema v12 defines core, lookup, and operational tables',
        () {
      // Gene - Nov, 28, 2026: Schema v12 includes 3 business + 2 operational/history + 11 lookup + 3 v12 operational tables (19 total).
      expect(powerSyncSchema.tables.length, 19);

      final tableNames = powerSyncSchema.tables.map((t) => t.name).toList();
      expect(tableNames, contains('job_orders'));
      expect(tableNames, contains('service_orders'));
      expect(tableNames, contains('lcp_nap_locations'));
      expect(tableNames, contains('sync_error_logs'));
      expect(tableNames, contains('work_timing_history'));
      expect(tableNames, contains('inventory_items'));
      expect(tableNames, contains('inventory_categories'));
      expect(tableNames, contains('inventory_logs'));
      expect(tableNames, contains('plans'));
      expect(tableNames, contains('lcp'));
      expect(tableNames, contains('nap'));
      expect(tableNames, contains('vlans'));
      expect(tableNames, contains('lcpnap'));
      expect(tableNames, contains('ports'));
      expect(tableNames, contains('lcpnap_ports'));
      expect(tableNames, contains('routers'));
      expect(tableNames, contains('pending_attachments'));
      expect(tableNames, contains('sync_conflicts'));
      expect(tableNames, contains('local_id_map'));

      // Local-only tables while REST handles fallback transport
      final jobOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'job_orders');
      final serviceOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'service_orders');
      final timingHistory = powerSyncSchema.tables
          .firstWhere((t) => t.name == 'work_timing_history');
      expect(jobOrders.localOnly, isTrue);
      expect(serviceOrders.localOnly, isTrue);
      expect(timingHistory.localOnly, isTrue);

      expect(() => powerSyncSchema.validate(), returnsNormally);
    });

    test(
        'SwitchFiberBackendConnector returns null when endpoint/key are unconfigured',
        () async {
      final connector = SwitchFiberBackendConnector();
      expect(connector.hasEndpoint, isFalse);
      expect(await connector.fetchCredentials(), isNull);
    });

    test(
        'SwitchFiberBackendConnector enforces RS256-only and returns null for HS256 dev-key fallback',
        () async {
      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://powersync.example.com',
        devSecretKey: 'test-dev-secret-key',
      );
      final creds = await connector.fetchCredentials();
      expect(creds, isNull);
    });

    test('SwitchFiberBackendConnector returns credentials when token exists',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyPowerSyncToken: 'test-jwt-token-123',
      });

      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://powersync.example.com',
      );
      final creds = await connector.fetchCredentials();
      expect(creds, isNotNull);
      expect(creds!.token, 'test-jwt-token-123');
      expect(creds.endpoint, 'https://powersync.example.com');
    });

    test(
        'SwitchFiberBackendConnector extracts logged-in technician email from session with stored token',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyPowerSyncToken: 'test-rs256-token',
        AppConstants.keyUserSession:
            '{"id":42,"username":"tech_juan","email":"juan.delacruz@switchfiber.ph"}',
      });

      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://powersync.example.com',
      );
      final creds = await connector.fetchCredentials();
      expect(creds, isNotNull);
      expect(creds!.userId, 'juan.delacruz@switchfiber.ph');
    });

    test('PowerSyncService singleton starts uninitialized', () {
      final service = PowerSyncService.instance;
      expect(service.isInitialized, isFalse);
      expect(() => service.db, throwsStateError);
    });
  });
}
