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
        'https://6aa61885a77ca1231d27bb58.powersync.journeyapps.com',
      );
    });

    test('PowerSync schema defines core tables and valid structure', () {
      expect(powerSyncSchema.tables.length, 4);

      final tableNames = powerSyncSchema.tables.map((t) => t.name).toList();
      expect(tableNames, contains('job_orders'));
      expect(tableNames, contains('service_orders'));
      expect(tableNames, contains('lcp_nap_locations'));
      expect(tableNames, contains('sync_error_logs'));

      // Every table stays local-only until the PowerSync service replicates
      // the backend: a REST pull must not land in the upload queue.
      expect(powerSyncSchema.tables.every((t) => t.localOnly), isTrue);

      expect(() => powerSyncSchema.validate(), returnsNormally);
    });

    test('SwitchFiberBackendConnector returns null when no token exists',
        () async {
      final connector = SwitchFiberBackendConnector();
      final creds = await connector.fetchCredentials();
      expect(creds, isNull);
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

    test('PowerSyncService singleton starts uninitialized', () {
      final service = PowerSyncService.instance;
      expect(service.isInitialized, isFalse);
      expect(() => service.db, throwsStateError);
    });
  });
}
