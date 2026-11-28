// Gene - Nov, 28, 2026: Model for local-only disk-backed photo attachment mutations queued alongside PowerSync v12 scalar writes.
import '../sql_values.dart';

class PendingAttachment {
  static const String statusPending = 'PENDING';
  static const String statusConflict = 'CONFLICT';
  static const String statusFailed = 'FAILED';

  final String id;
  final String entityType;
  final String entityId;
  final String slotName;
  final String? filePath;
  final bool deleteFlag;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PendingAttachment({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.slotName,
    this.filePath,
    this.deleteFlag = false,
    this.status = statusPending,
    required this.createdAt,
    required this.updatedAt,
  });

  static String deterministicId(
    String entityType,
    String entityId,
    String slotName,
  ) =>
      '${entityType}_${entityId}_$slotName';

  factory PendingAttachment.fromRow(Map<String, Object?> row) =>
      PendingAttachment(
        id: rowText(row['id']) ?? '',
        entityType: rowText(row['entity_type']) ?? '',
        entityId: rowText(row['entity_id']) ?? '',
        slotName: rowText(row['slot_name']) ?? '',
        filePath: rowText(row['file_path']),
        deleteFlag: rowBool(row['delete_flag'], fallback: false),
        status: rowText(row['status']) ?? statusPending,
        createdAt: rowDate(row['created_at']) ?? DateTime.now().toUtc(),
        updatedAt: rowDate(row['updated_at']) ?? DateTime.now().toUtc(),
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'slot_name': slotName,
        'file_path': filePath,
        'delete_flag': boolInt(deleteFlag),
        'status': status,
        'created_at': dateText(createdAt.toUtc()),
        'updated_at': dateText(updatedAt.toUtc()),
      };
}
