import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../models/job_order_model.dart';

/// The wording offered when texting a subscriber about an arrival. A starting
/// point the technician can edit in the messaging app, not a script.
String smsTemplateFor(JobOrderDto job) =>
    'Good day ${job.customerName}, Switch Fiber Technician is arriving '
    'shortly for ticket ${job.ticketNumber}.';

/// Opens the dialer on the job's contact number, or lets the technician pick
/// between primary and alternate numbers when both are present.
Future<void> callJob(BuildContext context, JobOrderDto job) => _contact(
      context,
      job,
      actionLabel: 'Call subscriber',
      icon: Icons.call_rounded,
      (phone) => Uri(scheme: 'tel', path: phone),
      failure: 'Could not open the dialer for',
    );

/// Opens the messaging app with the arrival text filled in, or lets the
/// technician pick between primary and alternate numbers when both are present.
Future<void> smsJob(BuildContext context, JobOrderDto job) => _contact(
      context,
      job,
      actionLabel: 'Text subscriber',
      icon: Icons.sms_rounded,
      (phone) => Uri(
        scheme: 'sms',
        path: phone,
        queryParameters: {'body': smsTemplateFor(job)},
      ),
      failure: 'Could not open the messaging app for',
    );

/// Collects distinct non-empty contact numbers for [job] (primary, then alternate).
List<({String label, String number})> contactNumbersFor(JobOrderDto job) {
  final seen = <String>{};
  final result = <({String label, String number})>[];
  void addIfValid(String label, String? raw) {
    final clean = raw?.trim() ?? '';
    if (clean.isEmpty) return;
    if (seen.add(clean)) {
      result.add((label: label, number: clean));
    }
  }

  addIfValid('Primary', job.contactNumber);
  addIfValid('Alternate', job.secondContactNumber);
  return result;
}

/*
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
*/
// Gene - Nov, 23, 2026: Support secondary/alternate phone numbers and show a 2-row picker when both primary and alternate numbers exist.
Future<void> _contact(
  BuildContext context,
  JobOrderDto job,
  Uri Function(String phone) build, {
  required String failure,
  required String actionLabel,
  required IconData icon,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final numbers = contactNumbersFor(job);
  if (numbers.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text('No contact number on ${job.ticketNumber}.'),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }

  String? chosenPhone;
  if (numbers.length == 1) {
    chosenPhone = numbers.first.number;
  } else {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    chosenPhone = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          20 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$actionLabel · ${job.customerName}',
              style: ctx.text.titleSmall,
            ),
            const SizedBox(height: 10),
            for (final entry in numbers)
              ListTile(
                key: ValueKey('contact_option_${entry.label.toLowerCase()}'),
                minTileHeight: 52,
                leading: Icon(icon, size: 24, color: AppTheme.brandInkOf(ctx)),
                title: Text(
                  '${entry.label} · ${entry.number}',
                  style: ctx.text.bodyLarge,
                ),
                onTap: () => Navigator.of(ctx).pop(entry.number),
              ),
          ],
        ),
      ),
    );
  }

  if (chosenPhone == null || chosenPhone.isEmpty) return;

  var opened = false;
  try {
    opened = await launchUrl(build(chosenPhone),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (opened) return;
  messenger.showSnackBar(SnackBar(
    content: Text('$failure $chosenPhone.'),
    behavior: SnackBarBehavior.floating,
    backgroundColor: AppTheme.danger,
  ));
}
