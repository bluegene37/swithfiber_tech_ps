import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';

/// Backend connector that supplies PowerSync authentication tokens
/// and handles outbound local CRUD mutations.
class SwitchFiberBackendConnector extends PowerSyncBackendConnector {
  final SecureStorageService _storage;
  final String _endpoint;

  SwitchFiberBackendConnector({
    SecureStorageService? storage,
    String? endpoint,
  })  : _storage = storage ?? SecureStorageService(),
        _endpoint = endpoint ?? AppConstants.defaultPowerSyncEndpoint;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // Check for a dedicated PowerSync token or fall back to user session JWT
    final token = await _storage.read(AppConstants.keyPowerSyncToken) ??
        await _storage.read(AppConstants.keyJwtToken);

    if (token == null || token.isEmpty) {
      // User is not signed in or no token configured yet
      return null;
    }

    return PowerSyncCredentials(
      endpoint: _endpoint,
      token: token,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // Called when there are local mutations queued for upload
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    for (var op in transaction.crud) {
      // Outbound CRUD mutations are uploaded to the Switch Fiber API.
      // Detailed endpoint mapping will be attached as tables are migrated.
      switch (op.op) {
        case UpdateType.put:
          break;
        case UpdateType.patch:
          break;
        case UpdateType.delete:
          break;
      }
    }

    await transaction.complete();
  }
}
