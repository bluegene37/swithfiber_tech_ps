// Gene - Nov, 28, 2026: Model for non-blocking 409 REASSIGNED / CANCELLED sync conflicts surfaced in the Needs Review UI.
import 'dart:convert';
import '../sql_values.dart';

class SyncConflict {
  final String id;
  final String entityType;
  final String entityId;
  final String reason;
  final int statusCode;
  final String message;
  final String serverSnapshot;
  final String localPayload;
  final bool resolved;
  final DateTime createdAt;

  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.statusCode,
    required this.message,
    required this.serverSnapshot,
    required this.localPayload,
    this.resolved = false,
    required this.createdAt,
  });

  factory SyncConflict.fromRow(Map<String, Object?> row) => SyncConflict(
        id: rowText(row['id']) ?? '',
        entityType: rowText(row['entity_type']) ?? '',
        entityId: rowText(row['entity_id']) ?? '',
        reason: rowText(row['reason']) ?? 'CONFLICT',
        statusCode: rowInt(row['status_code'], 409),
        message: rowText(row['message']) ?? '',
        serverSnapshot: rowText(row['server_snapshot']) ?? '{}',
        localPayload: rowText(row['local_payload']) ?? '{}',
        resolved: rowBool(row['resolved'], fallback: false),
        createdAt: rowDate(row['created_at']) ?? DateTime.now().toUtc(),
      );

  Map<String, dynamic> get decodedServerSnapshot => _tryDecode(serverSnapshot);
  Map<String, dynamic> get decodedLocalPayload => _tryDecode(localPayload);

  static Map<String, dynamic> _tryDecode(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  String get referenceLabel => switch (entityType) {
        'job_orders' || 'JOB_ORDER' => 'JO #$entityId',
        'service_orders' || 'SERVICE_ORDER' => 'Service Order #$entityId',
        'lcp_nap_locations' || 'LCP_NAP' => 'LCP NAP #$entityId',
        _ => '$entityType #$entityId',
      };

  Map<String, Object?> toRow() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'reason': reason,
        'status_code': statusCode,
        'message': message,
        'server_snapshot': serverSnapshot,
        'local_payload': localPayload,
        'resolved': boolInt(resolved),
        'created_at': dateText(createdAt.toUtc()),
      };
}
