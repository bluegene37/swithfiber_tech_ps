import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';

JobOrderDto job({String status = '', String? onsiteStatus}) =>
    JobOrderDto.fromJson({
      'id': 1,
      'status': status,
      'onsiteStatus': onsiteStatus,
    });

void main() {
  group('the two stages a job moves through', () {
    test('recognises Scheduled, Activated, and Completed', () {
      expect(job(status: 'Scheduled').jobStatus, JobStatus.scheduled);
      expect(job(status: 'Activated').jobStatus, JobStatus.activated);
      expect(job(status: 'Completed').jobStatus, JobStatus.completed);
    });

    test('Rescheduled is open work that can still be completed', () {
      final j = job(status: 'Rescheduled');
      expect(j.jobStatus, JobStatus.rescheduled);
      expect(job(status: 'reschedule').jobStatus, JobStatus.rescheduled);
      expect(j.isRescheduled, isTrue);
      expect(j.isOpen, isTrue);
      expect(j.isScheduled, isFalse);
      expect(j.isHistory, isFalse);
      expect(j.canActivate, isTrue);
      expect(j.nextStatus, JobStatus.completed);
      expect(JobStatus.rescheduled.wireValue, 'Rescheduled');
    });

    test('status remarks round-trip and are only sent when known', () {
      final withReason = JobOrderDto.fromJson({
        'id': 2,
        'status': 'Rescheduled',
        'statusRemarks': 'Not Available',
      });
      expect(withReason.statusRemarks, 'Not Available');
      expect(withReason.toApiJson()['statusRemarks'], 'Not Available');

      // A row cached before the column existed must not blank the office's
      // value: the rawJson copy stands.
      final legacy = JobOrderDto(
        id: 3,
        ticketNumber: 'SF-3',
        customerName: 'x',
        address: 'y',
        status: 'Scheduled',
        rawJson: '{"id":3,"status":"Scheduled","statusRemarks":"office"}',
      );
      expect(legacy.toApiJson()['statusRemarks'], 'office');
      expect(RescheduleReasons.all, contains('Not Available'));
      expect(RescheduleReasons.all, contains('No Available Slot'));
    });

    test('tolerates casing and spacing from the backend', () {
      expect(job(status: 'scheduled').jobStatus, JobStatus.scheduled);
      expect(job(status: 'ACTIVATED').jobStatus, JobStatus.activated);
      expect(job(status: ' Activated ').jobStatus, JobStatus.activated);
      expect(job(status: 'completed').jobStatus, JobStatus.completed);
      expect(job(status: 'COMPLETED').jobStatus, JobStatus.completed);
      expect(job(status: ' Completed ').jobStatus, JobStatus.completed);
    });

    test('maps dispatch-ready office statuses to Scheduled', () {
      expect(job(status: 'Confirmed').jobStatus, JobStatus.scheduled);
      expect(job(status: 'Applied').jobStatus, JobStatus.scheduled);
      expect(job(status: 'Pending').jobStatus, JobStatus.scheduled);
    });

    test('recognises In Progress as distinct from Scheduled', () {
      expect(job(status: 'In Progress').jobStatus, JobStatus.inProgress);
      expect(job(status: 'inprogress').jobStatus, JobStatus.inProgress);
      expect(job(status: 'In Progress').isScheduled, isFalse);
      // expect(job(status: 'In Progress').isOpen, isTrue);
      // Gene - Oct, 3, 2026: In Progress is not open work on tech queue (under admin review).
      expect(job(status: 'In Progress').isOpen, isFalse);
      expect(job(status: 'In Progress').isInProgress, isTrue);
      expect(JobStatus.inProgress.wireValue, 'Inprogress');
      expect(JobStatus.inProgress.label, 'In Progress');
      // Finished legacy work.
      expect(job(status: 'Completed').jobStatus, JobStatus.completed);
      expect(job(status: 'Completed').isOpen, isFalse);
      expect(job(status: 'Activated').isOpen, isFalse);
    });

    test('an unknown backend status is left unmapped but readable and not open',
        () {
      expect(job(status: 'Cancelled').jobStatus, isNull);
      expect(job(status: 'Cancelled').status, 'Cancelled');
      expect(job(status: 'Cancelled').isOpen, isFalse);
    });
  });

  group('activation and terminal stages', () {
    test('Scheduled goes straight to Completed', () {
      expect(job(status: 'Scheduled').nextStatus, JobStatus.completed);
      expect(job(status: 'Confirmed').nextStatus, JobStatus.completed);
      expect(job(status: 'Scheduled').canActivate, isTrue);
    });

    test('Activated is terminal', () {
      expect(job(status: 'Activated').nextStatus, isNull);
      expect(job(status: 'Activated').canActivate, isFalse);
      expect(JobStatus.activated.next, isNull);
    });

    test('Completed is terminal', () {
      expect(job(status: 'Completed').nextStatus, isNull);
      expect(job(status: 'Completed').canActivate, isFalse);
      expect(JobStatus.completed.next, isNull);
    });

    test('sends back the exact wording the backend uses', () {
      expect(JobStatus.scheduled.wireValue, 'Scheduled');
      expect(JobStatus.activated.wireValue, 'Activated');
      expect(JobStatus.completed.wireValue, 'Completed');
    });
  });

  group('failed and rescheduled visits stay visible', () {
    test('an exception on site is surfaced regardless of job status', () {
      expect(job(status: 'Confirmed', onsiteStatus: 'Failed').siteException,
          SiteException.failed);
      expect(job(status: 'Confirmed', onsiteStatus: 'Reschedule').siteException,
          SiteException.reschedule);
    });

    test('a normal visit has no exception to flag', () {
      expect(
          job(status: 'Confirmed', onsiteStatus: 'Done').siteException, isNull);
      expect(job(status: 'Confirmed', onsiteStatus: '').siteException, isNull);
      expect(job(status: 'Confirmed').siteException, isNull);
    });
  });
}
