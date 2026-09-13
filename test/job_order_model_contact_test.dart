import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';

/// The subscriber's email and second number are not columns; they are read
/// from the raw server record so the app's schema stays the API's.
void main() {
  JobOrderDto job(String? raw) => JobOrderDto(
        id: 1,
        ticketNumber: 'SF-1',
        customerName: 'Sub',
        address: 'Lot 1',
        status: 'Scheduled',
        rawJson: raw,
      );

  test('reads applicantEmailAddress and secondContactNumber', () {
    final j = job('{"applicantEmailAddress": " sub@example.com ", '
        '"secondContactNumber": "09181234567", "emailAddress": "office@x.ph"}');
    expect(j.subscriberEmail, 'sub@example.com');
    expect(j.secondContactNumber, '09181234567');
  });

  test('blank, "null" and missing values read as null', () {
    expect(job('{"applicantEmailAddress": ""}').subscriberEmail, isNull);
    expect(job('{"applicantEmailAddress": "null"}').subscriberEmail, isNull);
    expect(job('{}').secondContactNumber, isNull);
    expect(job(null).subscriberEmail, isNull);
    expect(job('not json').subscriberEmail, isNull);
  });
}
