// Gene - Nov, 26, 2026: Immutable local history model representing one Start -> Finish/Stop work session.
import '../sql_values.dart';

/// A single Start -> Finish/Stop work timing session recorded on a Job Order
/// or Service Order for a specific technician (`userId`) and local date (`workDate`).
class WorkTimingEntry {
  static const String orderTypeJobOrder = 'JOB_ORDER';
  static const String orderTypeServiceOrder = 'SERVICE_ORDER';

  final String id;

  /// `'JOB_ORDER'` or `'SERVICE_ORDER'`.
  final String orderType;
  final int orderId;
  final String orderReference;
  final String customerName;
  final String userId;
  final String? userName;

  /// Local calendar date (`YYYY-MM-DD`) when the session started.
  final String workDate;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMinutes;
  final bool isSynced;
  final DateTime createdAt;

  const WorkTimingEntry({
    required this.id,
    required this.orderType,
    required this.orderId,
    required this.orderReference,
    required this.customerName,
    required this.userId,
    this.userName,
    required this.workDate,
    required this.startTime,
    this.endTime,
    this.durationMinutes,
    this.isSynced = false,
    required this.createdAt,
  });

  bool get isJobOrder => orderType == orderTypeJobOrder;
  bool get isServiceOrder => orderType == orderTypeServiceOrder;
  bool get isInProgress => endTime == null || !endTime!.isAfter(startTime);

  Duration? get elapsed => endTime != null && endTime!.isAfter(startTime)
      ? endTime!.difference(startTime)
      : null;

  factory WorkTimingEntry.fromRow(Map<String, Object?> row) {
    final start =
        rowDate(row['start_time']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final end = rowDate(row['end_time']);
    return WorkTimingEntry(
      id: row['id']?.toString() ?? '',
      orderType: rowText(row['order_type']) ?? orderTypeJobOrder,
      orderId: rowInt(row['order_id']),
      orderReference: rowText(row['order_reference']) ?? '',
      customerName: rowText(row['customer_name']) ?? '',
      userId: rowText(row['user_id']) ?? '0',
      userName: rowText(row['user_name']),
      workDate: rowText(row['work_date']) ?? '',
      startTime: start,
      endTime: end,
      durationMinutes: rowIntOrNull(row['duration_minutes']),
      isSynced: rowBool(row['is_synced']),
      createdAt: rowDate(row['created_at']) ?? start,
    );
  }
}
