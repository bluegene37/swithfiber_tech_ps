// Gene - Oct 8, 2026: Unit tests for JobOrderDto.scheduledDate resolution and JobOrdersScreen.dateGroupLabel.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';

void main() {
  group('JobOrderDto.scheduledDate resolution', () {
    test('prioritizes explicit dateInstalled over all fallbacks', () {
      final installed = DateTime(2026, 10, 15);
      final job = JobOrderDto(
        id: 1,
        ticketNumber: 'SF-2026-0801',
        customerName: 'Test Customer',
        address: 'Test Address',
        dateInstalled: installed,
        modifiedDate: DateTime(2026, 9, 1),
        rawJson: '{"createdDate": "2026-07-20T08:00:00"}',
      );
      expect(job.scheduledDate, installed);
    });

    test('falls back to modifiedDate when dateInstalled is null', () {
      final modified = DateTime(2026, 9, 1);
      final job = JobOrderDto(
        id: 2,
        ticketNumber: 'SF-2026-0801',
        customerName: 'Test Customer',
        address: 'Test Address',
        modifiedDate: modified,
      );
      expect(job.scheduledDate, modified);
    });

    test('falls back to updatedAt when no earlier dates exist', () {
      final updated = DateTime(2026, 5, 1);
      final job = JobOrderDto(
        id: 6,
        ticketNumber: 'PLAIN-TICKET',
        customerName: 'Test Customer',
        address: 'Test Address',
        updatedAt: updated,
      );
      expect(job.scheduledDate, updated);
    });
  });

  group('JobOrdersScreen.dateGroupLabel formatting', () {
    test('formats Today with Today prefix and formatted date', () {
      final now = DateTime.now();
      final label = JobOrdersScreen.dateGroupLabel(now);
      final formatted = DateFormat('MMM d, yyyy').format(now);
      expect(label, 'Today · $formatted');
    });

    test('formats Tomorrow with Tomorrow prefix and formatted date', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final label = JobOrdersScreen.dateGroupLabel(tomorrow);
      final formatted = DateFormat('MMM d, yyyy').format(tomorrow);
      expect(label, 'Tomorrow · $formatted');
    });

    test('formats past or future dates with standard date string', () {
      final future = DateTime(2026, 12, 25);
      final label = JobOrdersScreen.dateGroupLabel(future);
      expect(label, 'Dec 25, 2026');
    });

    test('formats null as No Scheduled Date', () {
      expect(JobOrdersScreen.dateGroupLabel(null), 'No Scheduled Date');
    });

    test('includes job count when count is greater than 1', () {
      final date = DateTime(2026, 12, 25);
      expect(
        JobOrdersScreen.dateGroupLabel(date, count: 3),
        'Dec 25, 2026 (3 jobs)',
      );
    });
  });
}
