import '../sql_values.dart';

/// One refused push, as read back from the `sync_error_logs` table.
class SyncErrorLog {
  final String id;
  final int seq;

  /// 'JOB_ORDER' or 'SERVICE_ORDER'.
  final String entityType;
  final int entityId;

  /// The ticket number, so a log line is readable without a lookup.
  final String reference;

  /// What the technician was doing: 'complete', 'activate', 'field-status'.
  final String operation;

  /// HTTP status, or null when the request never got an answer at all.
  final int? statusCode;

  /// The server's own message, or the exception when there was no response.
  final String message;

  /// Size of the request body in bytes.
  final int payloadBytes;
  final DateTime occurredAt;

  /// Set once the same record syncs successfully.
  final bool resolved;

  /// The HTTP method and full URL of the call that failed.
  final String requestMethod;
  final String requestUrl;

  /// The JSON body exactly as sent, with inline images abbreviated.
  final String? requestBody;

  /// The raw response body, when there was one.
  final String? responseBody;

  const SyncErrorLog({
    required this.id,
    required this.seq,
    required this.entityType,
    required this.entityId,
    required this.reference,
    required this.operation,
    this.statusCode,
    required this.message,
    this.payloadBytes = 0,
    required this.occurredAt,
    this.resolved = false,
    this.requestMethod = '',
    this.requestUrl = '',
    this.requestBody,
    this.responseBody,
  });

  factory SyncErrorLog.fromRow(Map<String, Object?> row) => SyncErrorLog(
        id: row['id']?.toString() ?? '',
        seq: rowInt(row['seq']),
        entityType: rowText(row['entity_type']) ?? '',
        entityId: rowInt(row['entity_id']),
        reference: rowText(row['reference']) ?? '',
        operation: rowText(row['operation']) ?? '',
        statusCode: rowIntOrNull(row['status_code']),
        message: rowText(row['message']) ?? '',
        payloadBytes: rowInt(row['payload_bytes']),
        occurredAt: rowDate(row['occurred_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        resolved: rowBool(row['resolved']),
        requestMethod: rowText(row['request_method']) ?? '',
        requestUrl: rowText(row['request_url']) ?? '',
        requestBody: rowText(row['request_body']),
        responseBody: rowText(row['response_body']),
      );
}
