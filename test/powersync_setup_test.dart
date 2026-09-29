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
    test('PowerSync default endpoint is correctly configured', () {
      expect(
        AppConstants.defaultPowerSyncEndpoint,
        'http://103.249.198.50:8080',
      );
    });

    test('PowerSync schema defines core tables and valid structure', () {
      expect(powerSyncSchema.tables.length, 4);

      final tableNames = powerSyncSchema.tables.map((t) => t.name).toList();
      expect(tableNames, contains('job_orders'));
      expect(tableNames, contains('service_orders'));
      expect(tableNames, contains('lcp_nap_locations'));
      expect(tableNames, contains('sync_error_logs'));

      // Core business tables replicate with PowerSync; sync_error_logs and lcp_nap remain local-only
      final jobOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'job_orders');
      final serviceOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'service_orders');
      expect(jobOrders.localOnly, isFalse);
      expect(serviceOrders.localOnly, isFalse);

      expect(() => powerSyncSchema.validate(), returnsNormally);
    });

    test(
        'SwitchFiberBackendConnector returns dev token fallback when no token exists',
        () async {
      final connector = SwitchFiberBackendConnector();
      final creds = await connector.fetchCredentials();
      expect(creds, isNotNull);
      expect(creds!.token.startsWith('eyJ'), isTrue);
      expect(creds.userId, 'technician@switchfiber.ph');
      expect(creds.expiresAt, isNotNull);
      expect(creds.endpoint, AppConstants.defaultPowerSyncEndpoint);
    });

    test('SwitchFiberBackendConnector returns credentials when token exists',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyPowerSyncToken: 'test-jwt-token-123',
      });

      final connector = SwitchFiberBackendConnector();
      final creds = await connector.fetchCredentials();
      expect(creds, isNotNull);
      expect(creds!.token, 'test-jwt-token-123');
      expect(creds.endpoint, AppConstants.defaultPowerSyncEndpoint);
    });

    test(
        'SwitchFiberBackendConnector extracts logged-in technician email from session',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        AppConstants.keyUserSession:
            '{"id":42,"username":"tech_juan","email":"juan.delacruz@switchfiber.ph"}',
      });

      final connector = SwitchFiberBackendConnector();
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
