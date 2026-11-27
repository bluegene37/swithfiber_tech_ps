import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/database/daos/sync_error_logs_dao.dart';
import 'package:swithfiber_tech_ps/core/network/request_snapshot.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_gateway_client.dart';
import 'package:swithfiber_tech_ps/core/utils/data_url.dart';
import 'package:swithfiber_tech_ps/core/widgets/work_timing_bar.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';

/// Backend connector that supplies PowerSync authentication tokens
/// and handles outbound local CRUD mutations.
class SwitchFiberBackendConnector extends PowerSyncBackendConnector {
  final SecureStorageService _storage;
  final String _endpoint;
  // Gene - Nov, 23, 2026: Accept configurable devSecretKey and expose hasEndpoint for clean local-only fallback.
  final String _devSecretKey;
  // Gene - Nov, 27, 2026: Added PowerSync Gateway client, SyncErrorLogsDao hook, and post-upload invalidation callback.
  final PowerSyncGatewayClient? _gatewayClient;
  SyncErrorLogsDao? errorLog;
  void Function(String table, int entityId)? onEntityUploaded;

  /// Optional upload handler callback for intercepting or forwarding CRUD transactions.
  Future<void> Function(CrudTransaction transaction)? onUpload;

  /// Optional per-entry upload handler callback for individual CRUD mutations.
  Future<void> Function(CrudEntry entry)? onEntryUpload;

  /*
  SwitchFiberBackendConnector({
    SecureStorageService? storage,
    String? endpoint,
    this.onUpload,
    this.onEntryUpload,
  })  : _storage = storage ?? SecureStorageService(),
        _endpoint = endpoint ?? AppConstants.defaultPowerSyncEndpoint;
  */
  /*
  SwitchFiberBackendConnector({
    SecureStorageService? storage,
    String? endpoint,
    String? devSecretKey,
    this.onUpload,
    this.onEntryUpload,
  })  : _storage = storage ?? SecureStorageService(),
        _endpoint = endpoint ?? AppConstants.defaultPowerSyncEndpoint,
        _devSecretKey = devSecretKey ?? AppConstants.devSecretKey;
  */
  SwitchFiberBackendConnector({
    SecureStorageService? storage,
    String? endpoint,
    String? gatewayUrl,
    PowerSyncGatewayClient? gatewayClient,
    String? devSecretKey,
    this.errorLog,
    this.onEntityUploaded,
    this.onUpload,
    this.onEntryUpload,
  })  : _storage = storage ?? SecureStorageService(),
        _endpoint = endpoint ?? AppConstants.defaultPowerSyncEndpoint,
        _devSecretKey = devSecretKey ?? AppConstants.devSecretKey,
        _gatewayClient = _resolveGatewayClient(gatewayClient, gatewayUrl);

  static PowerSyncGatewayClient? _resolveGatewayClient(
    PowerSyncGatewayClient? provided,
    String? gatewayUrl,
  ) {
    if (provided != null) {
      return provided.hasBaseUrl ? provided : null;
    }
    final resolvedUrl =
        (gatewayUrl ?? AppConstants.defaultPowerSyncGatewayUrl).trim();
    if (resolvedUrl.isEmpty) return null;
    return PowerSyncGatewayClient(baseUrl: resolvedUrl);
  }

  bool get hasEndpoint => _endpoint.trim().isNotEmpty;

  bool get hasGateway => _gatewayClient?.hasBaseUrl ?? false;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final storedEndpoint =
        (await _storage.read(AppConstants.keyPowerSyncEndpoint))?.trim() ?? '';
    final effectiveEndpoint =
        _endpoint.trim().isNotEmpty ? _endpoint.trim() : storedEndpoint;
    if (effectiveEndpoint.isEmpty) {
      return null;
    }

    // 0. Determine current logged-in technician identity from session or auth state
    String currentUserId = 'technician@switchfiber.ph';
    bool hasKnownUser = false;
    try {
      final inMemoryUser = AuthSignals.instance.currentUser.value;
      if (inMemoryUser != null) {
        final email = inMemoryUser.email.trim().toLowerCase();
        final username = inMemoryUser.username.trim().toLowerCase();
        if (email.isNotEmpty) {
          currentUserId = email;
          hasKnownUser = true;
        } else if (username.isNotEmpty) {
          currentUserId =
              username.contains('@') ? username : '$username@switchfiber.ph';
          hasKnownUser = true;
        }
      } else {
        final sessionJson = await _storage.getUserSession();
        if (sessionJson != null && sessionJson.isNotEmpty) {
          final sessionMap = jsonDecode(sessionJson);
          if (sessionMap is Map<String, dynamic>) {
            final email = sessionMap['email']?.toString().trim().toLowerCase();
            final username =
                sessionMap['username']?.toString().trim().toLowerCase();
            if (email != null && email.isNotEmpty) {
              currentUserId = email;
              hasKnownUser = true;
            } else if (username != null && username.isNotEmpty) {
              currentUserId = username.contains('@')
                  ? username
                  : '$username@switchfiber.ph';
              hasKnownUser = true;
            }
          }
        }
      }
      if (!hasKnownUser) {
        final storedUserId =
            (await _storage.read(AppConstants.keyPowerSyncUserId))
                ?.trim()
                .toLowerCase();
        if (storedUserId != null && storedUserId.isNotEmpty) {
          currentUserId = storedUserId;
          hasKnownUser = true;
        }
      }
    } catch (_) {}

    // 1. Gateway Mode: reuse unexpired RS256 PowerSync JWT or mint via GET /api/Auth/powersync-token
    if (hasGateway) {
      final cachedToken = await _storage.read(AppConstants.keyPowerSyncToken);
      final cachedExpStr =
          await _storage.read(AppConstants.keyPowerSyncTokenExpiresAt);
      final cachedUser = (await _storage.read(AppConstants.keyPowerSyncUserId))
          ?.trim()
          .toLowerCase();
      final cachedExp =
          cachedExpStr == null ? null : DateTime.tryParse(cachedExpStr);
      final nowUtc = DateTime.now().toUtc();
      final matchesUser = cachedUser == null ||
          cachedUser.isEmpty ||
          !hasKnownUser ||
          cachedUser == currentUserId;

      if (cachedToken != null &&
          cachedToken.isNotEmpty &&
          cachedExp != null &&
          cachedExp.isAfter(nowUtc.add(const Duration(minutes: 5))) &&
          matchesUser) {
        return PowerSyncCredentials(
          endpoint: effectiveEndpoint,
          token: cachedToken,
          userId: (cachedUser != null && cachedUser.isNotEmpty)
              ? cachedUser
              : currentUserId,
          expiresAt: cachedExp,
        );
      }

      final bearer =
          await _storage.read(AppConstants.keyPowerSyncGatewayToken) ??
              cachedToken ??
              await _storage.read(AppConstants.keyJwtToken);
      if (bearer == null || bearer.trim().isEmpty) {
        return null;
      }

      try {
        final minted = await _gatewayClient!.fetchPowerSyncToken(
          bearerToken: bearer,
        );
        await _persistPowerSyncToken(minted);
        final targetEndpoint = _endpoint.trim().isNotEmpty
            ? _endpoint.trim()
            : (minted.endpoint.isNotEmpty
                ? minted.endpoint
                : effectiveEndpoint);
        final targetUserId =
            minted.userId.isNotEmpty ? minted.userId : currentUserId;
        return PowerSyncCredentials(
          endpoint: targetEndpoint,
          token: minted.token,
          userId: targetUserId,
          expiresAt: minted.expiresAt,
        );
      } on PowerSyncUploadException catch (e) {
        if (e.isUnauthorized) {
          await _storage.delete(AppConstants.keyPowerSyncToken);
          await _storage.delete(AppConstants.keyPowerSyncTokenExpiresAt);
          return null;
        }
        if (cachedToken != null &&
            cachedToken.isNotEmpty &&
            cachedExp != null &&
            cachedExp.isAfter(nowUtc) &&
            matchesUser) {
          return PowerSyncCredentials(
            endpoint: effectiveEndpoint,
            token: cachedToken,
            userId: (cachedUser != null && cachedUser.isNotEmpty)
                ? cachedUser
                : currentUserId,
            expiresAt: cachedExp,
          );
        }
        rethrow;
      }
    }

    // 2. Legacy / Non-Gateway Mode: Check for a dedicated PowerSync token or user session JWT
    final storedToken = await _storage.read(AppConstants.keyPowerSyncToken) ??
        await _storage.read(AppConstants.keyJwtToken);

    if (storedToken != null && storedToken.isNotEmpty) {
      return PowerSyncCredentials(
        endpoint: effectiveEndpoint,
        token: storedToken,
        userId: currentUserId,
      );
    }

    // 3. Direct Development Mode: Generate a fresh valid JWT only when devSecretKey is configured.
    if (_devSecretKey.trim().isEmpty) {
      return null;
    }
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

    /*
    final hmacSha256 = Hmac(sha256, utf8.encode(AppConstants.devSecretKey));
    */
    // Gene - Nov, 23, 2026: Sign with injected _devSecretKey instead of static hardcoded key.
    final hmacSha256 = Hmac(sha256, utf8.encode(_devSecretKey));
    final digest = hmacSha256.convert(utf8.encode(signingInput));
    final s = base64Url.encode(digest.bytes).replaceAll('=', '');

    final devToken = '$signingInput.$s';

    return PowerSyncCredentials(
      endpoint: effectiveEndpoint,
      token: devToken,
      userId: currentUserId,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
    );
  }

  Future<void> _persistPowerSyncToken(PowerSyncTokenResult result) async {
    await _storage.write(AppConstants.keyPowerSyncToken, result.token);
    if (result.expiresAt != null) {
      await _storage.write(
        AppConstants.keyPowerSyncTokenExpiresAt,
        result.expiresAt!.toUtc().toIso8601String(),
      );
    }
    if (result.userId.trim().isNotEmpty) {
      await _storage.write(
        AppConstants.keyPowerSyncUserId,
        result.userId.trim().toLowerCase(),
      );
    }
    if (result.endpoint.trim().isNotEmpty) {
      await _storage.write(
        AppConstants.keyPowerSyncEndpoint,
        result.endpoint.trim(),
      );
    }
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
/*
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
*/
        // Gene - Nov, 11, 2026: Added lcp_nap_locations recognition alongside job_orders and service_orders for PowerSync outbound CRUD routing.
        switch (op.table) {
          case 'job_orders':
          case 'service_orders':
          case 'lcp_nap_locations':
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
    } else if (hasGateway) {
      // Gene - Nov, 27, 2026: Upload queued PowerSync CRUD mutations through the authenticated PowerSync Gateway.
      await _uploadViaGateway(transaction);
      return;
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

  static const Set<String> _strippedClientColumns = {
    'raw_json',
    'is_synced',
    'updated_at',
    'optical_power',
    'materials_used_json',
  };

  static const Map<String, Map<String, String>> _photoColumnMappings = {
    'job_orders': {
      'setup_image': 'SetupImage',
      'client_signature': 'ClientSignature',
      'signed_contract_image': 'SignedContractImage',
      'box_reading_image': 'BoxReadingImage',
      'router_reading_image': 'RouterReadingImage',
      'port_label_image': 'PortLabelImage',
      'house_front': 'HouseFront',
    },
    'service_orders': {
      'client_signature': 'ClientSignature',
      'image1': 'Image1',
      'image2': 'Image2',
      'image3': 'Image3',
      'house_front_picture': 'HouseFrontPicture',
    },
    'lcp_nap_locations': {
      'image': 'Image',
      'image2': 'Image2',
      'reading_image': 'ReadingImage',
    },
  };

  static String _entityTypeForTable(String table) => switch (table) {
        'job_orders' => 'JOB_ORDER',
        'service_orders' => 'SERVICE_ORDER',
        'lcp_nap_locations' => 'LCP_NAP',
        _ => table.toUpperCase(),
      };

  static String _referenceForEntry(CrudEntry entry) {
    final id = entry.id;
    return switch (entry.table) {
      'job_orders' => 'JO-$id',
      'service_orders' => 'SO-${id.padLeft(4, '0')}',
      'lcp_nap_locations' => 'PLANT-$id',
      _ => '${entry.table}:$id',
    };
  }

  Future<String> _resolveUploadBearerToken() async {
    final token = await _storage.read(AppConstants.keyPowerSyncGatewayToken) ??
        await _storage.read(AppConstants.keyPowerSyncToken) ??
        await _storage.read(AppConstants.keyJwtToken);
    if (token == null || token.trim().isEmpty) {
      throw StateError(
        'No authentication token available to upload PowerSync changes.',
      );
    }
    return token.trim();
  }

  Future<String?> _refreshUploadBearerToken(String failedToken) async {
    final candidates = <String?>[
      await _storage.read(AppConstants.keyPowerSyncGatewayToken),
      await _storage.read(AppConstants.keyJwtToken),
    ];
    for (final candidate in candidates) {
      final clean = candidate?.trim() ?? '';
      if (clean.isEmpty) continue;
      try {
        final refreshed = await _gatewayClient!.fetchPowerSyncToken(
          bearerToken: clean,
        );
        await _persistPowerSyncToken(refreshed);
        return refreshed.token;
      } on PowerSyncUploadException catch (e) {
        if (!e.isUnauthorized) rethrow;
      }
    }
    return null;
  }

  Future<void> _uploadViaGateway(CrudTransaction transaction) async {
    var bearerToken = await _resolveUploadBearerToken();
    CrudEntry? currentEntry;
    try {
      final touched = await _executeGatewayUpload(
        transaction,
        bearerToken,
        onCurrentEntry: (e) => currentEntry = e,
      );
      await transaction.complete();
      await _markTouchedResolved(touched);
      for (final item in touched) {
        onEntityUploaded?.call(item.$1, item.$2);
      }
    } on PowerSyncUploadException catch (e) {
      if (e.isUnauthorized) {
        final refreshed = await _refreshUploadBearerToken(bearerToken);
        if (refreshed != null && refreshed.isNotEmpty) {
          bearerToken = refreshed;
          try {
            final touched = await _executeGatewayUpload(
              transaction,
              bearerToken,
              onCurrentEntry: (e) => currentEntry = e,
            );
            await transaction.complete();
            await _markTouchedResolved(touched);
            for (final item in touched) {
              onEntityUploaded?.call(item.$1, item.$2);
            }
            return;
          } on PowerSyncUploadException catch (retryErr) {
            await _handleUploadFailure(
              retryErr,
              entry: currentEntry ?? transaction.crud.first,
              transaction: transaction,
            );
            return;
          }
        }
      }
      await _handleUploadFailure(
        e,
        entry: currentEntry ?? transaction.crud.first,
        transaction: transaction,
      );
    } catch (e) {
      await _recordSyncError(
        entry: currentEntry ?? transaction.crud.first,
        statusCode: null,
        message: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> _handleUploadFailure(
    PowerSyncUploadException err, {
    required CrudEntry entry,
    required CrudTransaction transaction,
  }) async {
    await _recordSyncError(
      entry: entry,
      statusCode: err.statusCode,
      message: err.message,
      requestMethod: err.requestMethod,
      requestUrl: err.requestUrl,
      requestBody: err.requestBody is Map<String, dynamic>
          ? RequestSnapshot.body(err.requestBody as Map<String, dynamic>)
          : err.requestBody?.toString(),
      responseBody: RequestSnapshot.response(err.responseBody),
    );
    if (err.isPermanent) {
      // Permanent 4xx rejections (bad payload, missing record) would otherwise
      // block every subsequent queued mutation in ps_crud forever.
      await transaction.complete();
      return;
    }
    throw err;
  }

  Future<void> _markTouchedResolved(List<(String, int)> touched) async {
    final logDao = errorLog;
    if (logDao == null) return;
    for (final item in touched) {
      try {
        await logDao.markResolved(_entityTypeForTable(item.$1), item.$2);
      } catch (_) {}
    }
  }

  Future<void> _recordSyncError({
    required CrudEntry entry,
    required int? statusCode,
    required String message,
    String? requestMethod,
    String? requestUrl,
    String? requestBody,
    String? responseBody,
  }) async {
    final logDao = errorLog;
    if (logDao == null) return;
    try {
      await logDao.log(
        entityType: _entityTypeForTable(entry.table),
        entityId: int.tryParse(entry.id) ?? 0,
        reference: _referenceForEntry(entry),
        operation: entry.op.name,
        statusCode: statusCode,
        message: message,
        requestMethod: requestMethod ?? 'POST',
        requestUrl: requestUrl ?? '/api/powersync/upload',
        requestBody: requestBody,
        responseBody: responseBody,
      );
    } catch (_) {}
  }

  Future<List<(String, int)>> _executeGatewayUpload(
    CrudTransaction transaction,
    String bearerToken, {
    required void Function(CrudEntry entry) onCurrentEntry,
  }) async {
    final pendingBatchOps = <Map<String, dynamic>>[];
    final touched = <(String, int)>[];

    Future<void> flushBatch() async {
      if (pendingBatchOps.isEmpty) return;
      await _gatewayClient!.uploadBatch(
        operations: List<Map<String, dynamic>>.from(pendingBatchOps),
        bearerToken: bearerToken,
      );
      pendingBatchOps.clear();
    }

    for (final entry in transaction.crud) {
      onCurrentEntry(entry);
      if (!_photoColumnMappings.containsKey(entry.table)) {
        continue;
      }
      if (entry.op == UpdateType.delete) {
        // Mobile clients do not delete live server work orders or plant sites.
        continue;
      }

      final photoMap = _photoColumnMappings[entry.table]!;
      final rawData = Map<String, dynamic>.from(entry.opData ?? const {});
      final cleanData = <String, dynamic>{};
      final deleteFlags = <String, bool>{};
      final capturedFiles = <String, ({Uint8List bytes, String filename})>{};
      final storage = PhotoStorageService.instance;

      for (final kv in rawData.entries) {
        final key = kv.key;
        final value = kv.value;
        if (key == 'id' || _strippedClientColumns.contains(key)) {
          continue;
        }

        if (photoMap.containsKey(key)) {
          if (value == null) continue;
          final strVal = value.toString().trim();
          if (strVal.isEmpty) {
            deleteFlags['delete_$key'] = true;
            continue;
          }
          if (storage.isCapturedImage(strVal)) {
            final bytes =
                storage.resolveBytes(strVal) ?? DataUrl.decode(strVal);
            if (bytes != null && bytes.isNotEmpty) {
              final paramName = photoMap[key]!;
              final isPng = DataUrl.mimeTypeOf(strVal) == 'image/png' ||
                  strVal.toLowerCase().endsWith('.png') ||
                  key == 'client_signature';
              final ext = isPng ? 'png' : 'jpg';
              capturedFiles[paramName] = (
                bytes: bytes,
                filename: '${paramName.toLowerCase()}.$ext',
              );
            }
          }
          // Existing server filenames/URLs are omitted so Gateway preserves them.
          continue;
        }

        if (key == 'speedtest_image' &&
            value != null &&
            storage.isCapturedImage(value.toString())) {
          continue;
        }

        if (value == null && entry.op == UpdateType.put) {
          // Omit null columns from INSERT OR REPLACE so untouched server values stand.
          continue;
        }
        cleanData[key] = value;
      }

      _injectDurationIfMissing(entry.table, cleanData);

      final parsedId = int.tryParse(entry.id);
      final isNewOfflinePlant = entry.table == 'lcp_nap_locations' &&
          (parsedId == null || parsedId <= 0);
      final effectiveId = isNewOfflinePlant
          ? (parsedId != null ? 'offline-${parsedId.abs()}' : entry.id)
          : entry.id;

      if (parsedId != null && parsedId > 0) {
        touched.add((entry.table, parsedId));
      }

      if (capturedFiles.isNotEmpty) {
        await flushBatch();
        final formMap = <String, dynamic>{};
        cleanData.forEach((k, v) {
          if (v != null) formMap[k] = v.toString();
        });
        for (final flagKey in deleteFlags.keys) {
          formMap[flagKey] = 'true';
        }
        for (final fileEntry in capturedFiles.entries) {
          formMap[fileEntry.key] = MultipartFile.fromBytes(
            fileEntry.value.bytes,
            filename: fileEntry.value.filename,
          );
        }

        final (String method, String apiPath, String? idempotencyKey) =
            switch (entry.table) {
          'job_orders' => ('PUT', '/api/JobOrders/${entry.id}', null),
          'service_orders' => ('PUT', '/api/ServiceOrders/${entry.id}', null),
          'lcp_nap_locations' when isNewOfflinePlant => (
              'POST',
              '/api/LCPNapLocations',
              effectiveId,
            ),
          'lcp_nap_locations' => (
              'PUT',
              '/api/LCPNapLocations/${entry.id}',
              null,
            ),
          _ => throw StateError('Unsupported table: ${entry.table}'),
        };

        await _gatewayClient!.uploadMultipart(
          method: method,
          apiPath: apiPath,
          formData: FormData.fromMap(formMap),
          bearerToken: bearerToken,
          idempotencyKey: idempotencyKey,
        );
      } else {
        cleanData.addAll(deleteFlags);
        if (cleanData.isNotEmpty) {
          pendingBatchOps.add({
            'op': isNewOfflinePlant ? 'PUT' : 'PATCH',
            'table': entry.table,
            'id': effectiveId,
            'data': cleanData,
          });
        }
      }
    }

    await flushBatch();
    return touched;
  }

  static void _injectDurationIfMissing(
    String table,
    Map<String, dynamic> data,
  ) {
    final existing = data['duration']?.toString().trim() ?? '';
    if (existing.isNotEmpty) return;

    final start = parseTimingTimestamp(data['start_timestamp']);
    final endKey =
        table == 'service_orders' ? 'stop_timestamp' : 'end_timestamp';
    final end = parseTimingTimestamp(data[endKey]);
    if (start != null && end != null && end.isAfter(start)) {
      data['duration'] = formatTimingDurationMinutes(start, end);
    }
  }
}
