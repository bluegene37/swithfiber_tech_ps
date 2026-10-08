import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late JobRepository repository;
  late JobsSignals jobsSignals;

  final sampleJob = JobOrderDto(
    id: 99,
    ticketNumber: 'SF-2026-0099',
    customerName: 'Juan Dela Cruz',
    address: '123 Sampaguita Street',
    barangay: 'San Antonio',
    city: 'Pasig City',
    contactNumber: '09171234567',
    planName: 'Fiber 200 Mbps',
    status: 'Scheduled',
    lcpId: 10,
    napId: 2,
    rawJson: '{"id":99,"status":"Scheduled"}',
  );

  setUp(() async {
    db = AppDatabase.forTesting();
    repository = JobRepository(db.jobOrdersDao);
    jobsSignals = JobsSignals(repository);
    await db.jobOrdersDao.insertOrUpdateJob(sampleJob, synced: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    await jobsSignals.dispose();
    await db.close();
  });

  testWidgets(
      'job cards are collapsed by default and expand/collapse upon tapping chevron',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: JobOrdersScreen(jobsSignals: jobsSignals),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Collapsed state assertions
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('SF-2026-0099 (99)'), findsOneWidget);
    expect(find.text('SCHEDULED'), findsOneWidget);

    // Secondary details and actions should be collapsed (hidden)
    expect(find.text('123 Sampaguita Street, San Antonio, Pasig City'),
        findsNothing);
    expect(find.text('Fiber 200 Mbps'), findsNothing);
    expect(find.text('09171234567'), findsNothing);
    expect(find.text('NAVIGATE'), findsNothing);
    expect(find.text('CALL'), findsNothing);
    expect(find.text('SMS'), findsNothing);

    // Expand button is present
    final expandToggle = find.byKey(const ValueKey('job_expand_toggle_99'));
    expect(expandToggle, findsOneWidget);

    // 2. Tap expand button to reveal full details inline
    await tester.tap(expandToggle);
    await tester.pumpAndSettle();

    // Secondary details and action buttons should now be visible
    expect(find.text('123 Sampaguita Street, San Antonio, Pasig City'),
        findsOneWidget);
    expect(find.text('Fiber 200 Mbps'), findsOneWidget);
    expect(find.text('09171234567'), findsOneWidget);
    expect(find.text('NAVIGATE'), findsOneWidget);
    expect(find.text('CALL'), findsOneWidget);
    expect(find.text('SMS'), findsOneWidget);

    // 3. Tap expand button again to collapse
    await tester.tap(expandToggle);
    await tester.pumpAndSettle();

    // Details are hidden once more
    expect(find.text('123 Sampaguita Street, San Antonio, Pasig City'),
        findsNothing);
    expect(find.text('Fiber 200 Mbps'), findsNothing);
    expect(find.text('NAVIGATE'), findsNothing);

    // 4. Tapping on customer name opens the full JobOrderDetailScreen
    await tester.tap(find.text('Juan Dela Cruz'));
    await tester.pumpAndSettle();

    expect(find.byType(JobOrderDetailScreen), findsOneWidget);
  });
}
