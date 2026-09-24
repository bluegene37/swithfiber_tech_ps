import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';

/// Backend connector that supplies PowerSync authentication tokens
/// and handles outbound local CRUD mutations.
class SwitchFiberBackendConnector extends PowerSyncBackendConnector {
  final SecureStorageService _storage;
  final String _endpoint;

  /// Optional upload handler callback for intercepting or forwarding CRUD transactions.
  Future<void> Function(CrudTransaction transaction)? onUpload;

  /// Optional per-entry upload handler callback for individual CRUD mutations.
  Future<void> Function(CrudEntry entry)? onEntryUpload;

  SwitchFiberBackendConnector({
    SecureStorageService? storage,
    String? endpoint,
    this.onUpload,
    this.onEntryUpload,
  })  : _storage = storage ?? SecureStorageService(),
        _endpoint = endpoint ?? AppConstants.defaultPowerSyncEndpoint;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // 0. Determine current logged-in technician identity from session or auth state
    String currentUserId = 'technician@switchfiber.ph';
    try {
      final inMemoryUser = AuthSignals.instance.currentUser.value;
      if (inMemoryUser != null) {
        final email = inMemoryUser.email.trim();
        final username = inMemoryUser.username.trim();
        if (email.isNotEmpty) {
          currentUserId = email;
        } else if (username.isNotEmpty) {
          currentUserId =
              username.contains('@') ? username : '$username@switchfiber.ph';
        }
      } else {
        final sessionJson = await _storage.getUserSession();
        if (sessionJson != null && sessionJson.isNotEmpty) {
          final sessionMap = jsonDecode(sessionJson);
          if (sessionMap is Map<String, dynamic>) {
            final email = sessionMap['email']?.toString().trim();
            final username = sessionMap['username']?.toString().trim();
            if (email != null && email.isNotEmpty) {
              currentUserId = email;
            } else if (username != null && username.isNotEmpty) {
              currentUserId = username.contains('@')
                  ? username
                  : '$username@switchfiber.ph';
            }
          }
        }
      }
    } catch (_) {}

    // 1. Check for a dedicated PowerSync token or user session JWT
    final storedToken = await _storage.read(AppConstants.keyPowerSyncToken) ??
        await _storage.read(AppConstants.keyJwtToken);

    if (storedToken != null && storedToken.isNotEmpty) {
      return PowerSyncCredentials(
        endpoint: _endpoint,
        token: storedToken,
        userId: currentUserId,
      );
    }

    // 2. Direct Development Mode: Generate a fresh valid JWT with valid lifetime (< 86400s)
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    // PowerSync requires token lifetime <= 86400 seconds (24 hours). We set 23 hours.
    final exp = now + 82800;

    String b64Url(String s) =>
        base64Url.encode(utf8.encode(s)).replaceAll('=', '');

    final header = jsonEncode({'alg': 'HS256', 'typ': 'JWT', 'kid': 'dev-key'});
    final payload = jsonEncode({
      'sub': currentUserId,
      'aud': 'powersync',
      'iat': now,
      'exp': exp,
    });

    final h = b64Url(header);
    final p = b64Url(payload);
    final signingInput = '$h.$p';

    final hmacSha256 = Hmac(sha256, utf8.encode(AppConstants.devSecretKey));
    final digest = hmacSha256.convert(utf8.encode(signingInput));
    final s = base64Url.encode(digest.bytes).replaceAll('=', '');

    final devToken = '$signingInput.$s';

    return PowerSyncCredentials(
      endpoint: _endpoint,
      token: devToken,
      userId: currentUserId,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // Called when there are local mutations queued for upload
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    final handler = onUpload;
    final entryHandler = onEntryUpload;

    if (handler != null) {
      await handler(transaction);
    } else if (entryHandler != null) {
      for (var op in transaction.crud) {
        // Table recognition for core business tables
        switch (op.table) {
          case 'job_orders':
          case 'service_orders':
            switch (op.op) {
              case UpdateType.put:
              case UpdateType.patch:
              case UpdateType.delete:
                break;
            }
            break;
          default:
            break;
        }
        await entryHandler(op);
      }
    } else {
      // Prevent silently completing transactions and dropping unhandled mutations.
      // Throwing StateError ensures the transaction is preserved in ps_crud for retry.
      throw StateError(
        'No upload handler registered to process outbound CRUD transaction '
        '(${transaction.crud.length} mutations). Queue preserved.',
      );
    }

    // Only complete the transaction when the upload handler succeeds.
    // If an exception was thrown above, it bubbles up to PowerSync,
    // preserving the transaction in ps_crud for retry on reconnect.
    await transaction.complete();
  }
}
