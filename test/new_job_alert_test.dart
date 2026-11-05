import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/shell/technician_shell.dart';

// Gene - Nov 5, 2026: Extended JobOrdersApi to inherit default image and multipart methods.
class MockJobOrdersApi extends JobOrdersApi {
  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusAssigned({
    required String status,
    String? assignedEmail,
  }) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusDate({
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async =>
      [];

  @override
  Future<Map<String, dynamic>?> fetchById(int id) async => null;

  @override
  Future<void> update(int id, Map<String, dynamic> body) async {}
}

class MockServiceOrdersApi extends ServiceOrdersApi {
  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  JobOrderDto createSampleJob({
    required int id,
    required String ticketNumber,
    required String customerName,
    String status = 'Scheduled',
    String? assignedEmail = 'tech@switchfiber.ph',
  }) {
    return JobOrderDto(
      id: id,
      ticketNumber: ticketNumber,
      customerName: customerName,
      status: status,
      assignedEmail: assignedEmail,
      address: '123 Rizal Ave',
      barangay: 'San Roque',
      city: 'Angono',
      planName: 'Fiber 50Mbps',
      contactNumber: '09123456789',
    );
  }

  group('JobsSignals New Job Alert Signal Tests', () {
    late AppDatabase db;
    late JobRepository repository;

    setUp(() {
      db = AppDatabase.forTesting();
      repository = JobRepository(db.jobOrdersDao, api: MockJobOrdersApi());
    });

    tearDown(() async {
      await db.close();
    });

    test('Initial snapshot does not trigger new job alert or callback',
        () async {
      final initialJob = createSampleJob(
        id: 501,
        ticketNumber: 'T-501',
        customerName: 'Initial Customer',
      );
      await db.jobOrdersDao.insertOrUpdateJob(initialJob);

      JobOrderDto? alertedJob;
      final signals = JobsSignals(
        repository,
        onNewJobAlert: (job) => alertedJob = job,
      );
      addTearDown(() => signals.dispose());

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.allJobs.value.length, 1);
      expect(signals.newJobAlert.value, isNull);
      expect(alertedJob, isNull);
    });

    test(
        'Newly inserted open job triggers newJobAlert signal and sound/haptic callback',
        () async {
      JobOrderDto? alertedJob;
      final signals = JobsSignals(
        repository,
        onNewJobAlert: (job) => alertedJob = job,
      );
      addTearDown(() => signals.dispose());

      await Future.delayed(const Duration(milliseconds: 50));
      expect(signals.newJobAlert.value, isNull);

      final newJob = createSampleJob(
        id: 502,
        ticketNumber: 'T-502',
        customerName: 'Juan Dela Cruz',
        status: 'Scheduled',
      );
      await db.jobOrdersDao.insertOrUpdateJob(newJob);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newJobAlert.value, isNotNull);
      expect(signals.newJobAlert.value?.id, 502);
      expect(signals.newJobAlert.value?.ticketNumber, 'T-502');
      expect(signals.newJobAlert.value?.customerName, 'Juan Dela Cruz');
      expect(alertedJob?.id, 502);

      signals.dismissAlert();
      expect(signals.newJobAlert.value, isNull);
    });

    test('Non-open jobs (Completed/Activated) do not trigger new job alert',
        () async {
      JobOrderDto? alertedJob;
      final signals = JobsSignals(
        repository,
        onNewJobAlert: (job) => alertedJob = job,
      );
      addTearDown(() => signals.dispose());

      await Future.delayed(const Duration(milliseconds: 50));

      final completedJob = createSampleJob(
        id: 503,
        ticketNumber: 'T-503',
        customerName: 'Done Customer',
        status: 'Completed',
      );
      await db.jobOrdersDao.insertOrUpdateJob(completedJob);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newJobAlert.value, isNull);
      expect(alertedJob, isNull);
    });

    test(
        'Jobs assigned to another technician do not trigger alert when email is scoped',
        () async {
      JobOrderDto? alertedJob;
      final signals = JobsSignals(
        repository,
        onNewJobAlert: (job) => alertedJob = job,
      );
      addTearDown(() => signals.dispose());

      signals.setTechnicianEmail('tech@switchfiber.ph');
      await Future.delayed(const Duration(milliseconds: 50));

      final otherTechJob = createSampleJob(
        id: 504,
        ticketNumber: 'T-504',
        customerName: 'Other Tech Job',
        status: 'Scheduled',
        assignedEmail: 'someone.else@switchfiber.ph',
      );
      await db.jobOrdersDao.insertOrUpdateJob(otherTechJob);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newJobAlert.value, isNull);
      expect(alertedJob, isNull);

      final myJob = createSampleJob(
        id: 505,
        ticketNumber: 'T-505',
        customerName: 'My Assigned Job',
        status: 'Scheduled',
        assignedEmail: 'tech@switchfiber.ph',
      );
      await db.jobOrdersDao.insertOrUpdateJob(myJob);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newJobAlert.value?.id, 505);
      expect(alertedJob?.id, 505);
    });

    test('Reassigning an existing job to the technician triggers new job alert',
        () async {
      JobOrderDto? alertedJob;

      final initialJob = createSampleJob(
        id: 506,
        ticketNumber: 'T-506',
        customerName: 'Reassigned Customer',
        status: 'Scheduled',
        assignedEmail: 'other@switchfiber.ph',
      );
      await db.jobOrdersDao.insertOrUpdateJob(initialJob);

      final signals = JobsSignals(
        repository,
        onNewJobAlert: (job) => alertedJob = job,
      );
      addTearDown(() => signals.dispose());

      signals.setTechnicianEmail('tech@switchfiber.ph');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newJobAlert.value, isNull);
      expect(alertedJob, isNull);

      final reassignedJob = createSampleJob(
        id: 506,
        ticketNumber: 'T-506',
        customerName: 'Reassigned Customer',
        status: 'Scheduled',
        assignedEmail: 'tech@switchfiber.ph',
      );
      await db.jobOrdersDao.insertOrUpdateJob(reassignedJob);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newJobAlert.value?.id, 506);
      expect(alertedJob?.id, 506);
    });
  });

  group('TechnicianShell In-App Alert Banner Widget Tests', () {
    testWidgets(
        'Displays top alert banner with ticket number and customer name, and dismisses on X tap',
        (tester) async {
      late final AppDatabase db;
      late final JobRepository repository;
      late final JobsSignals signals;
      late final LcpNapSignals lcpNapSignals;
      late final ServiceOrdersSignals serviceOrdersSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        repository = JobRepository(db.jobOrdersDao, api: MockJobOrdersApi());
        signals = JobsSignals(repository);
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
        serviceOrdersSignals =
            ServiceOrdersSignals(api: MockServiceOrdersApi());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      addTearDown(() async {
        await signals.dispose();
        await lcpNapSignals.dispose();
        await db.close();
      });

      final authSignals = AuthSignals.instance;
      authSignals.currentUser.value = UserModel(
        id: 1,
        username: 'tech_juan',
        fname: 'Juan',
        lname: 'Dela Cruz',
        email: 'tech@switchfiber.ph',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TechnicianShell(
            authSignals: authSignals,
            jobsSignals: signals,
            lcpNapSignals: lcpNapSignals,
            serviceOrdersSignals: serviceOrdersSignals,
            enableAutoSync: false,
          ),
        ),
      );

      await tester.pump();

      // Initially no banner
      expect(find.text('NEW DISPATCH'), findsNothing);

      // Trigger new job alert signal
      final testJob = createSampleJob(
        id: 777,
        ticketNumber: 'T-777888',
        customerName: 'Pedro Penduko',
      );
      signals.newJobAlert.value = testJob;

      await tester.pump();

      // Alert banner is now visible
      expect(find.text('NEW DISPATCH'), findsOneWidget);
      expect(find.text('T-777888'), findsOneWidget);
      expect(find.text('Pedro Penduko'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);

      // Tap dismiss ("X") button
      final dismissButton = find.byTooltip('Dismiss');
      expect(dismissButton, findsOneWidget);
      await tester.tap(dismissButton);
      await tester.pump();

      // Banner is removed
      expect(find.text('NEW DISPATCH'), findsNothing);
      expect(signals.newJobAlert.value, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'Tapping View button navigates to JobOrderDetailScreen and dismisses banner',
        (tester) async {
      late final AppDatabase db;
      late final JobRepository repository;
      late final JobsSignals signals;
      late final LcpNapSignals lcpNapSignals;
      late final ServiceOrdersSignals serviceOrdersSignals;

      final testJob = createSampleJob(
        id: 888,
        ticketNumber: 'T-888999',
        customerName: 'Maria Clara',
      );

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        repository = JobRepository(db.jobOrdersDao, api: MockJobOrdersApi());
        signals = JobsSignals(repository);
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
        serviceOrdersSignals =
            ServiceOrdersSignals(api: MockServiceOrdersApi());
        await db.jobOrdersDao.insertOrUpdateJob(testJob);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      addTearDown(() async {
        await signals.dispose();
        await lcpNapSignals.dispose();
        await db.close();
      });

      final authSignals = AuthSignals.instance;
      authSignals.currentUser.value = UserModel(
        id: 1,
        username: 'tech_juan',
        fname: 'Juan',
        lname: 'Dela Cruz',
        email: 'tech@switchfiber.ph',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TechnicianShell(
            authSignals: authSignals,
            jobsSignals: signals,
            lcpNapSignals: lcpNapSignals,
            serviceOrdersSignals: serviceOrdersSignals,
            enableAutoSync: false,
          ),
        ),
      );

      await tester.pump();

      signals.newJobAlert.value = testJob;

      await tester.pump();

      expect(find.text('NEW DISPATCH'), findsOneWidget);

      // Tap View button
      await tester.tap(find.text('View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Alert is dismissed
      expect(signals.newJobAlert.value, isNull);

      // Navigated to JobOrderDetailScreen
      expect(find.byType(JobOrderDetailScreen), findsOneWidget);
      expect(find.text('Maria Clara'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
