import 'dart:convert';
// Gene - Nov, 28, 2026: Added dart:io and package:path for streaming multipart files from pending_attachments, and disabled legacy crypto HS256 dev-key signing (RS256-only).
import 'dart:io';
import 'dart:typed_data';
/*
import 'package:crypto/crypto.dart';
*/
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/database/daos/local_id_map_dao.dart';
import 'package:swithfiber_tech_ps/core/database/daos/pending_attachments_dao.dart';
import 'package:swithfiber_tech_ps/core/database/daos/sync_conflicts_dao.dart';
import 'package:swithfiber_tech_ps/core/database/daos/sync_error_logs_dao.dart';
import 'package:swithfiber_tech_ps/core/database/models/pending_attachment.dart';
import 'package:swithfiber_tech_ps/core/network/request_snapshot.dart';
import 'package:swithfiber_tech_ps/core/services/photo_storage_service.dart';
import 'package:swithfiber_tech_ps/core/storage/secure_storage_service.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_gateway_client.dart';
import 'package:swithfiber_tech_ps/core/utils/data_url.dart';
import 'package:swithfiber_tech_ps/core/widgets/work_timing_bar.dart';
import 'package:swithfiber_tech_ps/features/auth/services/auth_service.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';

/// Backend connector that supplies PowerSync authentication tokens
/// and handles outbound local CRUD mutations.
class SwitchFiberBackendConnector extends PowerSyncBackendConnector {
  final SecureStorageService _storage;
  final String _endpoint;
  /*
  // Gene - Nov, 23, 2026: Accept configurable devSecretKey and expose hasEndpoint for clean local-only fallback.
  final String _devSecretKey;
  */
  // Gene - Nov, 28, 2026: Removed unused _devSecretKey field (RS256-only auth on PowerSync v12).
  // Gene - Nov, 27, 2026: Added PowerSync Gateway client, SyncErrorLogsDao hook, and post-upload invalidation callback.
  final PowerSyncGatewayClient? _gatewayClient;
  SyncErrorLogsDao? errorLog;
  // Gene - Nov, 28, 2026: Added v12 PendingAttachmentsDao, SyncConflictsDao, LocalIdMapDao, and AuthService for coalesced multipart uploads, non-blocking 409 conflicts, and proactive RS256 token refresh.
  PendingAttachmentsDao? pendingAttachments;
  SyncConflictsDao? syncConflicts;
  LocalIdMapDao? localIdMap;
  AuthService? authService;
  void Function(String table, int entityId)? onEntityUploaded;
  // Gene - Nov, 28, 2026: Notify auth layer when gateway credentials are permanently rejected (401) so in-place re-login runs without wiping local SQLite.
  void Function()? onUnauthorized;

  /// Optional upload handler callback for intercepting or forwarding CRUD transactions.
  Future<void> Function(CrudTransaction transaction)? onUpload;

  /// Optional per-entry upload handler callback for individual CRUD mutations.
  Future<void> Function(CrudEntry entry)? onEntryUpload;

  // Gene - Nov, 28, 2026: Accept v12 DAOs and AuthService while preserving optional devSecretKey constructor compatibility.
  SwitchFiberBackendConnector({
    SecureStorageService? storage,
    String? endpoint,
    String? gatewayUrl,
    PowerSyncGatewayClient? gatewayClient,
    @Deprecated(
        'HS256 dev tokens are removed on PowerSync v12; use RS256 Gateway auth.')
    String? devSecretKey,
    this.errorLog,
    this.pendingAttachments,
    this.syncConflicts,
    this.localIdMap,
    this.authService,
    this.onEntityUploaded,
    this.onUnauthorized,
    this.onUpload,
    this.onEntryUpload,
  })  : _storage = storage ?? SecureStorageService(),
        _endpoint = endpoint ?? AppConstants.defaultPowerSyncEndpoint,
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

  bool get canConnect => hasEndpoint || hasGateway;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final storedEndpoint =
        (await _storage.read(AppConstants.keyPowerSyncEndpoint))?.trim() ?? '';
    final effectiveEndpoint =
        _endpoint.trim().isNotEmpty ? _endpoint.trim() : storedEndpoint;
    if (effectiveEndpoint.isEmpty && !hasGateway) {
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

    // 1. Gateway Mode: proactive POST /api/Auth/refresh + RS256 PowerSync token minting (never clears local SQLite on 401/offline).
    if (hasGateway) {
      final cachedToken = await _storage.read(AppConstants.keyPowerSyncToken);
      final cachedExpStr =
          await _storage.read(AppConstants.keyPowerSyncTokenExpiresAt);
      final cachedUser = (await _storage.read(AppConstants.keyPowerSyncUserId))
          ?.trim()
          .toLowerCase();
      final cachedExp =
          cachedExpStr == null ? null : DateTime.tryParse(cachedExpStr);
      final gwToken =
          (await _storage.read(AppConstants.keyPowerSyncGatewayToken))?.trim();
      final gwExpStr =
          await _storage.read(AppConstants.keyPowerSyncGatewayTokenExpiresAt);
      final gwExp = gwExpStr == null ? null : DateTime.tryParse(gwExpStr);
      final nowUtc = DateTime.now().toUtc();
      final matchesUser = cachedUser == null ||
          cachedUser.isEmpty ||
          !hasKnownUser ||
          cachedUser == currentUserId;

      final needsSessionRefresh = gwToken != null &&
          gwToken.isNotEmpty &&
          gwExp != null &&
          gwExp.isBefore(nowUtc.add(const Duration(minutes: 15)));

      if (needsSessionRefresh) {
        try {
          final refreshed = await (authService != null
              ? authService!.refreshGatewaySession()
              : _gatewayClient!.refreshSession(bearerToken: gwToken));
          if (refreshed != null) {
            await _persistGatewaySessionResult(refreshed);
            final ps = refreshed.powerSync;
            final nextEndpoint =
                _resolveTargetEndpoint(ps?.endpoint, effectiveEndpoint);
            if (ps != null && ps.token.isNotEmpty && nextEndpoint.isNotEmpty) {
              return PowerSyncCredentials(
                endpoint: nextEndpoint,
                token: ps.token,
                userId: ps.userId.isNotEmpty ? ps.userId : currentUserId,
                expiresAt: ps.expiresAt,
              );
            }
          }
        } on PowerSyncUploadException catch (e) {
          if (e.isUnauthorized) {
            await _storage.delete(AppConstants.keyPowerSyncGatewayToken);
            await _storage
                .delete(AppConstants.keyPowerSyncGatewayTokenExpiresAt);
          }
          // Fall through cleanly to fallback bearers or cached valid token.
        } catch (_) {}
      }

      if (cachedToken != null &&
          cachedToken.isNotEmpty &&
          cachedExp != null &&
          cachedExp.isAfter(nowUtc.add(const Duration(minutes: 5))) &&
          matchesUser &&
          effectiveEndpoint.isNotEmpty) {
        return PowerSyncCredentials(
          endpoint: effectiveEndpoint,
          token: cachedToken,
          userId: (cachedUser != null && cachedUser.isNotEmpty)
              ? cachedUser
              : currentUserId,
          expiresAt: cachedExp,
        );
      }

      final latestGwToken =
          (await _storage.read(AppConstants.keyPowerSyncGatewayToken))?.trim();
      final jwtToken = (await _storage.read(AppConstants.keyJwtToken))?.trim();
      final cachedBearer = cachedToken?.trim();
      final uniqueCandidates = <String>[];
      for (final candidate in [latestGwToken, jwtToken, cachedBearer]) {
        if (candidate != null &&
            candidate.isNotEmpty &&
            !uniqueCandidates.contains(candidate)) {
          uniqueCandidates.add(candidate);
        }
      }
      if (uniqueCandidates.isEmpty) {
        if (hasKnownUser) {
          onUnauthorized?.call();
        }
        return null;
      }

      var sawUnauthorized = false;
      for (final bearer in uniqueCandidates) {
        try {
          final minted = await _gatewayClient!.fetchPowerSyncToken(
            bearerToken: bearer,
          );
          await _persistPowerSyncToken(minted);
          final targetEndpoint =
              _resolveTargetEndpoint(minted.endpoint, effectiveEndpoint);
          if (targetEndpoint.isEmpty) return null;
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
            // Try POST /api/Auth/refresh once before retiring this bearer.
            try {
              final refreshed = await _gatewayClient!.refreshSession(
                bearerToken: bearer,
              );
              await _persistGatewaySessionResult(refreshed);
              final ps = refreshed.powerSync;
              if (ps != null && ps.token.isNotEmpty) {
                final targetEndpoint =
                    _resolveTargetEndpoint(ps.endpoint, effectiveEndpoint);
                if (targetEndpoint.isEmpty) return null;
                return PowerSyncCredentials(
                  endpoint: targetEndpoint,
                  token: ps.token,
                  userId: ps.userId.isNotEmpty ? ps.userId : currentUserId,
                  expiresAt: ps.expiresAt,
                );
              }
            } on PowerSyncUploadException catch (refreshErr) {
              if (!refreshErr.isUnauthorized) rethrow;
            }
            sawUnauthorized = true;
            if (bearer == latestGwToken) {
              await _storage.delete(AppConstants.keyPowerSyncGatewayToken);
              await _storage
                  .delete(AppConstants.keyPowerSyncGatewayTokenExpiresAt);
            }
            if (bearer == cachedBearer) {
              await _storage.delete(AppConstants.keyPowerSyncToken);
              await _storage.delete(AppConstants.keyPowerSyncTokenExpiresAt);
            }
            if (bearer == jwtToken) {
              await _storage.delete(AppConstants.keyJwtToken);
            }
            continue;
          }
          if (cachedToken != null &&
              cachedToken.isNotEmpty &&
              cachedExp != null &&
              cachedExp.isAfter(nowUtc) &&
              matchesUser &&
              effectiveEndpoint.isNotEmpty) {
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

      if (sawUnauthorized) {
        await _storage.clearTokensOnly();
        onUnauthorized?.call();
      }
      return null;
    }

    // 2. Non-Gateway Mode: reuse explicit RS256 PowerSync token if available.
    if (effectiveEndpoint.isEmpty) return null;
    final storedToken = await _storage.read(AppConstants.keyPowerSyncToken) ??
        await _storage.read(AppConstants.keyJwtToken);

    if (storedToken != null && storedToken.isNotEmpty) {
      return PowerSyncCredentials(
        endpoint: effectiveEndpoint,
        token: storedToken,
        userId: currentUserId,
      );
    }

    // 3. Legacy HS256 Dev-Key Signing REMOVED (PowerSync v12 backend enforces RS256-only).
    /*
    if (_devSecretKey.trim().isEmpty) {
      return null;
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final exp = now + 82800;
    ...
    */
    return null;
  }

  String _resolveTargetEndpoint(String? dynamicEndpoint, String fallback) {
    final dyn = dynamicEndpoint?.trim() ?? '';
    if (_endpoint.trim().isNotEmpty) return _endpoint.trim();
    if (dyn.isNotEmpty) return dyn;
    return fallback;
  }

  Future<void> _persistGatewaySessionResult(GatewayLoginResult result) async {
    if (result.sessionToken.trim().isNotEmpty) {
      await _storage.write(
        AppConstants.keyPowerSyncGatewayToken,
        result.sessionToken.trim(),
      );
      await _storage.saveToken(result.sessionToken.trim());
    }
    if (result.tokenExpiresAt != null) {
      await _storage.write(
        AppConstants.keyPowerSyncGatewayTokenExpiresAt,
        result.tokenExpiresAt!.toUtc().toIso8601String(),
      );
    }
    if (result.powerSync != null) {
      await _persistPowerSyncToken(result.powerSync!);
    }
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
    final handler = onUpload;
    final entryHandler = onEntryUpload;

    // Preserve getNextCrudTransaction() hook behavior for legacy/mock unit tests.
    if (handler != null || entryHandler != null) {
      final transaction = await database.getNextCrudTransaction();
      if (transaction == null) return;

      if (handler != null) {
        await handler(transaction);
      } else if (entryHandler != null) {
        for (var op in transaction.crud) {
          await entryHandler(op);
        }
      }
      await transaction.complete();
      return;
    }

    if (hasGateway) {
      // Gene - Nov, 28, 2026: Drain up to 100 ps_crud mutations coalesced per (table, id) + pending_attachments via PATCH/POST multipart with Idempotency-Key & non-blocking 409 handling.
      final batch = await database.getCrudBatch(limit: 100);
      if (batch == null) {
        await _uploadStandalonePendingAttachments();
        return;
      }
      await _uploadCoalescedBatch(batch);
      return;
    }

    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;
    throw StateError(
      'No upload handler registered to process outbound CRUD transaction '
      '(${transaction.crud.length} mutations). Queue preserved.',
    );
  }

  static const Set<String> _strippedClientColumns = {
    'raw_json',
    'is_synced',
    'updated_at',
    'optical_power',
    'materials_used_json',
  };

  static final RegExp _legacyMaterialColumnRegex =
      RegExp(r'^item_(name|quantity)([1-9]|10)$');

  // Gene - Nov, 28, 2026: Canonical v12 multipart photo slot field names (speedtest_image excluded: remains scalar text on job_orders).
  static const Map<String, Set<String>> _photoSlotNames = {
    'job_orders': {
      'setup_image',
      'client_signature',
      'signed_contract_image',
      'box_reading_image',
      'router_reading_image',
      'port_label_image',
      'house_front',
    },
    'service_orders': {
      'client_signature',
      'image1',
      'image2',
      'image3',
      'house_front_picture',
    },
    'lcp_nap_locations': {
      'image',
      'image2',
      'reading_image',
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
        await _storage.read(AppConstants.keyJwtToken) ??
        await _storage.read(AppConstants.keyPowerSyncToken);
    if (token == null || token.trim().isEmpty) {
      onUnauthorized?.call();
      throw const PowerSyncUploadException(
        statusCode: 401,
        message:
            'No authentication token available to upload PowerSync changes.',
      );
    }
    return token.trim();
  }

  Future<String?> _refreshSessionBearerForUpload() async {
    final candidates = <String?>[
      await _storage.read(AppConstants.keyPowerSyncGatewayToken),
      await _storage.read(AppConstants.keyJwtToken),
    ];
    for (final candidate in candidates) {
      final clean = candidate?.trim() ?? '';
      if (clean.isEmpty) continue;
      try {
        final refreshed = await (authService != null
            ? authService!.refreshGatewaySession()
            : _gatewayClient!.refreshSession(bearerToken: clean));
        if (refreshed != null) {
          await _persistGatewaySessionResult(refreshed);
          if (refreshed.sessionToken.trim().isNotEmpty) {
            return refreshed.sessionToken.trim();
          }
          if (refreshed.powerSync != null &&
              refreshed.powerSync!.token.trim().isNotEmpty) {
            return refreshed.powerSync!.token.trim();
          }
        }
      } on PowerSyncUploadException catch (e) {
        if (!e.isUnauthorized) rethrow;
      }
      try {
        final minted = await _gatewayClient!.fetchPowerSyncToken(
          bearerToken: clean,
        );
        await _persistPowerSyncToken(minted);
        return clean;
      } on PowerSyncUploadException catch (e) {
        if (!e.isUnauthorized) rethrow;
      }
    }
    return null;
  }

  Future<void> _uploadCoalescedBatch(CrudBatch batch) async {
    var bearerToken = await _resolveUploadBearerToken();
    final storage = PhotoStorageService.instance;

    final groups = <String, _CoalescedEntityGroup>{};
    for (final entry in batch.crud) {
      final slotSet = _photoSlotNames[entry.table];
      if (slotSet == null) continue;
      if (entry.op == UpdateType.delete) {
        // Mobile clients do not delete live server work orders or plant sites.
        continue;
      }

      final groupKey = '${entry.table}::${entry.id}';
      final group = groups.putIfAbsent(
        groupKey,
        () => _CoalescedEntityGroup(
          table: entry.table,
          rawId: entry.id,
          firstClientId: entry.clientId,
          lastClientId: entry.clientId,
          representativeEntry: entry,
        ),
      );
      group.lastClientId = entry.clientId;
      group.representativeEntry = entry;
      if (entry.op == UpdateType.put) {
        group.hasPut = true;
      }

      final rawData = Map<String, dynamic>.from(entry.opData ?? const {});
      for (final kv in rawData.entries) {
        final key = kv.key;
        final value = kv.value;
        if (key == 'id' ||
            _strippedClientColumns.contains(key) ||
            _legacyMaterialColumnRegex.hasMatch(key)) {
          continue;
        }
        if (slotSet.contains(key)) {
          if (value == null) continue;
          final strVal = value.toString().trim();
          if (strVal.isEmpty) {
            group.inlineDeleteFlags[key] = true;
            group.inlineFiles.remove(key);
          } else if (storage.isCapturedImage(strVal)) {
            final bytes =
                storage.resolveBytes(strVal) ?? DataUrl.decode(strVal);
            if (bytes != null && bytes.isNotEmpty) {
              final isPng = DataUrl.mimeTypeOf(strVal) == 'image/png' ||
                  strVal.toLowerCase().endsWith('.png') ||
                  key == 'client_signature';
              group.inlineFiles[key] = (
                bytes: bytes,
                filename: '$key.${isPng ? 'png' : 'jpg'}',
              );
              group.inlineDeleteFlags.remove(key);
            }
          }
          continue;
        }
        if (value == null && entry.op == UpdateType.put) {
          // Omit unset nulls from INSERT OR REPLACE so existing server columns stand.
          continue;
        }
        if (value != null) {
          group.dirtyScalarData[key] = value;
        }
      }
    }

    final resolvedPlantIds = <String, String>{};
    final handledAttachmentKeys = <String>{};

    for (final group in groups.values) {
      String targetId = group.rawId;
      var isOfflineCreate = false;

      if (group.table == 'lcp_nap_locations' &&
          int.tryParse(targetId) == null) {
        final mapped = resolvedPlantIds[group.rawId] ??
            await localIdMap?.resolveServerId(
              entityType: 'lcp_nap_locations',
              localId: group.rawId,
            );
        if (mapped != null && mapped.trim().isNotEmpty) {
          targetId = mapped.trim();
        } else {
          isOfflineCreate = true;
        }
      }

      handledAttachmentKeys.add('${group.table}::${group.rawId}');
      handledAttachmentKeys.add('${group.table}::$targetId');

      final pendingList = <PendingAttachment>[];
      if (pendingAttachments != null) {
        pendingList.addAll(
          await pendingAttachments!.getPendingForEntity(
            group.table,
            group.rawId,
          ),
        );
        if (targetId != group.rawId) {
          pendingList.addAll(
            await pendingAttachments!.getPendingForEntity(
              group.table,
              targetId,
            ),
          );
        }
      }

      final attBySlot = <String, PendingAttachment>{};
      for (final att in pendingList) {
        attBySlot[att.slotName] = att;
      }

      _injectDurationIfMissing(group.table, group.dirtyScalarData);

      final outcome = await _sendEntityMultipartGroup(
        table: group.table,
        rawId: group.rawId,
        targetId: targetId,
        isOfflineCreate: isOfflineCreate,
        idempotencyKey: isOfflineCreate
            ? group.rawId
            : 'psv13-${group.table}-$targetId-${group.firstClientId}-${group.lastClientId}',
        dirtyScalarData: group.dirtyScalarData,
        inlineFiles: group.inlineFiles,
        inlineDeleteFlags: group.inlineDeleteFlags,
        attachments: attBySlot.values.toList(),
        bearerToken: bearerToken,
        representativeEntry: group.representativeEntry,
        onTokenRefreshed: (nextToken) => bearerToken = nextToken,
        onOfflineCreatedId: (serverId) {
          resolvedPlantIds[group.rawId] = serverId;
          handledAttachmentKeys.add('lcp_nap_locations::$serverId');
        },
      );
      if (outcome == _GroupUploadOutcome.transientFailure) {
        // Rethrown inside _sendEntityMultipartGroup, unreachable safeguard.
        return;
      }
    }

    await _uploadStandalonePendingAttachments(
      bearerToken: bearerToken,
      skipEntityKeys: handledAttachmentKeys,
    );

    await batch.complete();
  }

  Future<void> _uploadStandalonePendingAttachments({
    String? bearerToken,
    Set<String> skipEntityKeys = const {},
  }) async {
    final attDao = pendingAttachments;
    if (attDao == null) return;
    final allPending = await attDao.getAllPending();
    if (allPending.isEmpty) return;

    var activeToken = bearerToken ?? await _resolveUploadBearerToken();
    final grouped = <String, List<PendingAttachment>>{};
    for (final att in allPending) {
      final key = '${att.entityType}::${att.entityId}';
      if (skipEntityKeys.contains(key)) continue;
      grouped.putIfAbsent(key, () => []).add(att);
    }

    for (final entry in grouped.entries) {
      final first = entry.value.first;
      final table = first.entityType;
      var rawId = first.entityId;
      var targetId = rawId;
      var isOfflineCreate = false;

      if (table == 'lcp_nap_locations' && int.tryParse(rawId) == null) {
        final mapped = await localIdMap?.resolveServerId(
          entityType: 'lcp_nap_locations',
          localId: rawId,
        );
        if (mapped != null && mapped.trim().isNotEmpty) {
          targetId = mapped.trim();
        } else {
          // Wait for associated ps_crud create row unless offline row lacks ps_crud.
          isOfflineCreate = true;
        }
      }

      final syntheticEntry = CrudEntry(
        0,
        UpdateType.patch,
        table,
        targetId,
        null,
        const {},
      );

      await _sendEntityMultipartGroup(
        table: table,
        rawId: rawId,
        targetId: targetId,
        isOfflineCreate: isOfflineCreate,
        idempotencyKey: isOfflineCreate
            ? rawId
            : 'psv12-att-$table-$targetId-${first.updatedAt.microsecondsSinceEpoch}',
        dirtyScalarData: const {},
        inlineFiles: const {},
        inlineDeleteFlags: const {},
        attachments: entry.value,
        bearerToken: activeToken,
        representativeEntry: syntheticEntry,
        onTokenRefreshed: (nextToken) => activeToken = nextToken,
      );
    }
  }

  Future<_GroupUploadOutcome> _sendEntityMultipartGroup({
    required String table,
    required String rawId,
    required String targetId,
    required bool isOfflineCreate,
    required String idempotencyKey,
    required Map<String, dynamic> dirtyScalarData,
    required Map<String, ({Uint8List bytes, String filename})> inlineFiles,
    required Map<String, bool> inlineDeleteFlags,
    required List<PendingAttachment> attachments,
    required String bearerToken,
    required CrudEntry representativeEntry,
    required void Function(String refreshedToken) onTokenRefreshed,
    void Function(String serverId)? onOfflineCreatedId,
  }) async {
    final slotNames = _photoSlotNames[table] ?? const <String>{};
    final attachmentSlots = {for (final a in attachments) a.slotName};
    final attachmentIdsToDelete = <String>[];

    Future<FormData?> buildFormData() async {
      attachmentIdsToDelete.clear();
      final formMap = <String, dynamic>{};

      dirtyScalarData.forEach((k, v) {
        if (v != null) formMap[k] = v.toString();
      });

      for (final slot in inlineDeleteFlags.keys) {
        if (attachmentSlots.contains(slot)) continue;
        formMap['delete_$slot'] = 'true';
      }
      for (final kv in inlineFiles.entries) {
        if (attachmentSlots.contains(kv.key)) continue;
        formMap[kv.key] = MultipartFile.fromBytes(
          kv.value.bytes,
          filename: kv.value.filename,
        );
      }

      for (final att in attachments) {
        if (slotNames.isNotEmpty && !slotNames.contains(att.slotName)) {
          continue;
        }
        if (att.deleteFlag) {
          formMap['delete_${att.slotName}'] = 'true';
          attachmentIdsToDelete.add(att.id);
          continue;
        }
        final path = att.filePath?.trim();
        if (path == null || path.isEmpty) {
          attachmentIdsToDelete.add(att.id);
          continue;
        }
        final file = File(path);
        if (!file.existsSync()) {
          attachmentIdsToDelete.add(att.id);
          continue;
        }
        formMap[att.slotName] = await MultipartFile.fromFile(
          path,
          filename: p.basename(path),
        );
        attachmentIdsToDelete.add(att.id);
      }

      if (formMap.isEmpty) return null;
      return FormData.fromMap(formMap);
    }

    final initialForm = await buildFormData();
    if (initialForm == null) {
      if (attachmentIdsToDelete.isNotEmpty && pendingAttachments != null) {
        await pendingAttachments!.deleteByIds(
          attachmentIdsToDelete,
          deleteFiles: false,
        );
      }
      return _GroupUploadOutcome.succeeded;
    }

    final (String method, String apiPath) = switch (table) {
      'job_orders' => ('PATCH', '/api/JobOrders/$targetId'),
      'service_orders' => ('PATCH', '/api/ServiceOrders/$targetId'),
      'lcp_nap_locations' when isOfflineCreate => (
          'POST',
          '/api/LCPNapLocations'
        ),
      'lcp_nap_locations' => ('PATCH', '/api/LCPNapLocations/$targetId'),
      _ => throw StateError('Unsupported table: $table'),
    };

    final summaryMap = <String, dynamic>{
      ...dirtyScalarData,
      for (final att in attachments)
        att.slotName: att.deleteFlag
            ? '<delete>'
            : (att.filePath != null ? p.basename(att.filePath!) : ''),
      for (final k in inlineDeleteFlags.keys) k: '<delete>',
      for (final k in inlineFiles.keys) k: inlineFiles[k]!.filename,
    };

    Future<Map<String, dynamic>?> execute(
      FormData formData,
      String token,
    ) =>
        _gatewayClient!.uploadMultipart(
          method: method,
          apiPath: apiPath,
          formData: formData,
          bearerToken: token,
          idempotencyKey: idempotencyKey,
          requestBodySummary: RequestSnapshot.body(summaryMap),
        );

    try {
      Map<String, dynamic>? responseJson;
      try {
        responseJson = await execute(initialForm, bearerToken);
      } on PowerSyncUploadException catch (e) {
        if (!e.isUnauthorized) rethrow;
        final refreshed = await _refreshSessionBearerForUpload();
        if (refreshed == null || refreshed.isEmpty) rethrow;
        onTokenRefreshed(refreshed);
        final retryForm = await buildFormData();
        if (retryForm != null) {
          responseJson = await execute(retryForm, refreshed);
        }
      }

      if (isOfflineCreate) {
        final serverId = _extractServerId(responseJson);
        if (serverId != null && serverId.isNotEmpty) {
          await localIdMap?.putMapping(
            entityType: 'lcp_nap_locations',
            localId: rawId,
            serverId: serverId,
          );
          onOfflineCreatedId?.call(serverId);
          if (pendingAttachments != null && attachmentIdsToDelete.isNotEmpty) {
            await pendingAttachments!.deleteByIds(
              attachmentIdsToDelete,
              deleteFiles: true,
            );
          }
          await pendingAttachments?.remapEntityId(
            entityType: 'lcp_nap_locations',
            oldEntityId: rawId,
            newEntityId: serverId,
          );
          final parsedServerId = int.tryParse(serverId);
          if (parsedServerId != null && parsedServerId > 0) {
            await _markTouchedResolved([(table, parsedServerId)]);
            onEntityUploaded?.call(table, parsedServerId);
          }
          return _GroupUploadOutcome.succeeded;
        }
      }

      if (pendingAttachments != null && attachmentIdsToDelete.isNotEmpty) {
        await pendingAttachments!.deleteByIds(
          attachmentIdsToDelete,
          deleteFiles: true,
        );
      }
      final numericId = int.tryParse(targetId);
      if (numericId != null && numericId > 0) {
        await _markTouchedResolved([(table, numericId)]);
        onEntityUploaded?.call(table, numericId);
      }
      return _GroupUploadOutcome.succeeded;
    } on PowerSyncUploadException catch (e) {
      // Gene - Nov, 28, 2026: On 409 Conflict (REASSIGNED/CANCELLED) or 403 NOT_ASSIGNED, log serverRecord to sync_conflicts, delete blocked pending_attachments + temp files, and continue processing remaining entities in the batch.
      if (e.isConflict || e.isNotAssigned) {
        final conflictReason =
            e.isNotAssigned ? 'NOT_ASSIGNED' : e.conflictCode;
        final fallbackSnapshot = <String, dynamic>{
          if (e.conflictAssignedEmail != null &&
              e.conflictAssignedEmail!.isNotEmpty)
            'assignedEmail': e.conflictAssignedEmail,
          if (e.conflictServerStatus != null &&
              e.conflictServerStatus!.isNotEmpty)
            'serverStatus': e.conflictServerStatus,
        };
        await syncConflicts?.recordConflict(
          entityType: table,
          entityId: targetId,
          reason: conflictReason,
          statusCode: e.statusCode ?? 409,
          message: e.message,
          serverSnapshot: jsonEncode(e.serverRecord ?? fallbackSnapshot),
          localPayload: jsonEncode(summaryMap),
        );
        if (pendingAttachments != null) {
          await pendingAttachments!.deleteForEntity(table, rawId);
          if (targetId != rawId) {
            await pendingAttachments!.deleteForEntity(table, targetId);
          }
        }
        return _GroupUploadOutcome.conflictRecorded;
      }

      await _recordSyncError(
        entry: representativeEntry,
        statusCode: e.statusCode,
        message: e.message,
        requestMethod: e.requestMethod,
        requestUrl: e.requestUrl,
        requestBody: RequestSnapshot.body(summaryMap),
        responseBody: RequestSnapshot.response(e.responseBody),
      );

      if (e.isUnauthorized) {
        await _storage.clearTokensOnly();
        onUnauthorized?.call();
        rethrow;
      }

      if (e.isPermanent) {
        // Permanent 4xx rejections (excluding 401/408/409/429) must not stall FIFO.
        return _GroupUploadOutcome.permanentErrorSkipped;
      }
      rethrow;
    } catch (e) {
      await _recordSyncError(
        entry: representativeEntry,
        statusCode: null,
        message: e.toString(),
        requestMethod: method,
        requestUrl: apiPath,
        requestBody: RequestSnapshot.body(summaryMap),
      );
      rethrow;
    }
  }

  static String? _extractServerId(Map<String, dynamic>? response) {
    if (response == null) return null;
    final candidates = [
      response['id'],
      response['Id'],
      response['locationId'],
      if (response['data'] is Map) (response['data'] as Map)['id'],
      if (response['record'] is Map) (response['record'] as Map)['id'],
    ];
    for (final c in candidates) {
      if (c == null) continue;
      final str = c.toString().trim();
      if (str.isNotEmpty) return str;
    }
    return null;
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
        requestMethod: requestMethod ?? 'PATCH',
        requestUrl: requestUrl ?? '/api/${entry.table}/${entry.id}',
        requestBody: requestBody,
        responseBody: responseBody,
      );
    } catch (_) {}
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

class _CoalescedEntityGroup {
  final String table;
  final String rawId;
  final int firstClientId;
  int lastClientId;
  CrudEntry representativeEntry;
  bool hasPut = false;
  final Map<String, dynamic> dirtyScalarData = {};
  final Map<String, ({Uint8List bytes, String filename})> inlineFiles = {};
  final Map<String, bool> inlineDeleteFlags = {};

  _CoalescedEntityGroup({
    required this.table,
    required this.rawId,
    required this.firstClientId,
    required this.lastClientId,
    required this.representativeEntry,
  });
}

enum _GroupUploadOutcome {
  succeeded,
  conflictRecorded,
  permanentErrorSkipped,
  transientFailure,
}
