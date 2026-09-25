import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';

void main() {
  group('Job Order Plan & Email Persistence Tests', () {
    test('JobOrdersTable schema defines subscriber_email and second_contact_number', () {
      final jobOrders =
          powerSyncSchema.tables.firstWhere((t) => t.name == 'job_orders');
      final columnNames = jobOrders.columns.map((c) => c.name).toSet();

      expect(columnNames, contains('subscriber_email'));
      expect(columnNames, contains('second_contact_number'));
    });

    test('JobOrderDto resolves planName from planId when plan_name is null/empty', () {
      final row = {
        'id': '101',
        'ticket_number': 'JO-101',
        'customer_name': 'Juan Dela Cruz',
        'address': '123 Main St',
        'plan_name': null,
        'plan_id': 1, // SwitchLite - P699 in CatalogService fallbackPlans
        'status': 'Scheduled',
        'raw_json': null,
      };

      final job = JobOrderDto.fromRow(row);
      expect(job.planName, 'SwitchLite - P699');
    });

    test('JobOrderDto preserves subscriberEmail and secondContactNumber from columns without raw_json', () {
      final row = {
        'id': '102',
        'ticket_number': 'JO-102',
        'customer_name': 'Maria Santos',
        'address': '456 Rizal St',
        'subscriber_email': 'maria.santos@example.com',
        'second_contact_number': '09171234567',
        'status': 'Scheduled',
        'raw_json': null,
      };

      final job = JobOrderDto.fromRow(row);
      expect(job.subscriberEmail, 'maria.santos@example.com');
      expect(job.secondContactNumber, '09171234567');
    });

    test('JobOrderDto preserves email across PowerSync null-overwrite cycles', () {
      JobOrderDto.clearMemoryCaches();

      // Step 1: REST API returns JSON with email and plan
      final apiJson = {
        'id': 103,
        'ticketNumber': 'JO-103',
        'customerName': 'Pedro Penduko',
        'address': '789 Mabini St',
        'applicantEmailAddress': 'pedro@example.com',
        'plan': 'SwitchSpeed - P1299',
        'planId': 4,
        'status': 'Scheduled',
      };
      final restJob = JobOrderDto.fromJson(apiJson);
      expect(restJob.subscriberEmail, 'pedro@example.com');
      expect(restJob.planName, 'SwitchSpeed - P1299');

      // Step 2: PowerSync syncs row from SQL Server with raw_json=null, subscriber_email=null, plan_name=null
      final powerSyncRow = {
        'id': '103',
        'ticket_number': 'JO-103',
        'customer_name': 'Pedro Penduko',
        'address': '789 Mabini St',
        'plan_name': null,
        'plan_id': 4,
        'subscriber_email': null,
        'status': 'Scheduled',
        'raw_json': null,
      };
      final syncedJob = JobOrderDto.fromRow(powerSyncRow);

      // Email and plan should still be preserved and not disappear!
      expect(syncedJob.subscriberEmail, 'pedro@example.com');
      expect(syncedJob.planName, 'SwitchSpeed - P1299');
    });

    test('JobOrderDto.toRow serializes subscriber_email and second_contact_number', () {
      final job = JobOrderDto(
        id: 104,
        ticketNumber: 'JO-104',
        customerName: 'Ana Gomez',
        address: '101 Bonifacio Ave',
        subscriberEmail: 'ana@example.com',
        secondContactNumber: '09189876543',
      );

      final row = job.toRow();
      expect(row['subscriber_email'], 'ana@example.com');
      expect(row['second_contact_number'], '09189876543');
    });
  });
}
