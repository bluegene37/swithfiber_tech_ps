import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../models/job_order_model.dart';

/// The wording offered when texting a subscriber about an arrival. A starting
/// point the technician can edit in the messaging app, not a script.
String smsTemplateFor(JobOrderDto job) =>
    'Good day ${job.customerName}, Switch Fiber Technician is arriving '
    'shortly for ticket ${job.ticketNumber}.';

/// Opens the dialer on the job's contact number, or says why it could not.
Future<void> callJob(BuildContext context, JobOrderDto job) => _contact(
      context,
      job,
      (phone) => Uri(scheme: 'tel', path: phone),
      failure: 'Could not open the dialer for',
    );

/// Opens the messaging app with the arrival text filled in, or says why not.
Future<void> smsJob(BuildContext context, JobOrderDto job) => _contact(
      context,
      job,
      (phone) => Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': smsTemplateFor(job)},
      ),
      failure: 'Could not open the messaging app for',
    );

/// Hands the built URI to the phone. A job with no number and a phone that
/// refuses both get a plain sentence instead of a silent nothing.
Future<void> _contact(
  BuildContext context,
  JobOrderDto job,
  Uri Function(String phone) build, {
  required String failure,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final phone = job.contactNumber?.trim() ?? '';
  if (phone.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text('No contact number on ${job.ticketNumber}.'),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  var opened = false;
  try {
    opened =
        await launchUrl(build(phone), mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  messenger.showSnackBar(SnackBar(
    content: Text('$failure $phone.'),
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppTheme.danger,
  ));
}
