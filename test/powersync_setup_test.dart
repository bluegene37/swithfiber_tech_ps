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

    test('PowerSync schema defines core tables and valid structure', () {
      expect(powerSyncSchema.tables.length, 4);

      final tableNames = powerSyncSchema.tables.map((t) => t.name).toList();
      expect(tableNames, contains('job_orders'));
      expect(tableNames, contains('service_orders'));
      expect(tableNames, contains('lcp_nap_locations'));
      expect(tableNames, contains('sync_error_logs'));

      // Local-only tables while the Switch Fiber REST API handles transport
      final jobOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'job_orders');
      final serviceOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'service_orders');
      expect(jobOrders.localOnly, isTrue);
      expect(serviceOrders.localOnly, isTrue);

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
        'SwitchFiberBackendConnector returns dev token fallback when no token exists',
        () async {
      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://powersync.example.com',
        devSecretKey: 'test-dev-secret-key',
      );
      final creds = await connector.fetchCredentials();
      expect(creds, isNotNull);
      expect(creds!.token.startsWith('eyJ'), isTrue);
      expect(creds.userId, 'technician@switchfiber.ph');
      expect(creds.expiresAt, isNotNull);
      expect(creds.endpoint, 'https://powersync.example.com');
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
        'SwitchFiberBackendConnector extracts logged-in technician email from session',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyUserSession:
            '{"id":42,"username":"tech_juan","email":"juan.delacruz@switchfiber.ph"}',
      });

      final connector = SwitchFiberBackendConnector(
        endpoint: 'https://powersync.example.com',
        devSecretKey: 'test-dev-secret-key',
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
