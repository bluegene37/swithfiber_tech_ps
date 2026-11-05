// Gene - Oct, 1, 2026: Comprehensive unit and widget tests for new service order alert system
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
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

  ServiceOrderDto createSampleOrder({
    required int id,
    required String accountNumber,
    required String fullName,
    String supportStatus = 'Open',
    String? visitStatus = 'Pending',
    String concern = 'No Connection',
    String? assignedEmail = 'tech@switchfiber.ph',
  }) {
    return ServiceOrderDto(
      id: id,
      accountNumber: accountNumber,
      fullName: fullName,
      contactNumber: '09123456789',
      emailAddress: 'client@example.com',
      address: '123 Mabini St',
      barangay: 'San Isidro',
      city: 'Taytay',
      supportStatus: supportStatus,
      visitStatus: visitStatus,
      concern: concern,
      assignedEmail: assignedEmail,
    );
  }

  group('ServiceOrdersSignals New Service Order Alert Signal Tests', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting();
    });

    tearDown(() async {
      await db.close();
    });

    test('Initial snapshot does not trigger new order alert or callback',
        () async {
      final initialOrder = createSampleOrder(
        id: 601,
        accountNumber: 'ACC-601',
        fullName: 'Initial Customer',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(initialOrder);

      ServiceOrderDto? alertedOrder;
      final signals = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: MockServiceOrdersApi(),
        onNewOrderAlert: (order) => alertedOrder = order,
      );
      addTearDown(() => signals.dispose());

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.allOrders.value.length, 1);
      expect(signals.newOrderAlert.value, isNull);
      expect(alertedOrder, isNull);
    });

    test(
        'Newly inserted open service order triggers newOrderAlert signal and callback',
        () async {
      ServiceOrderDto? alertedOrder;
      final signals = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: MockServiceOrdersApi(),
        onNewOrderAlert: (order) => alertedOrder = order,
      );
      addTearDown(() => signals.dispose());

      await Future.delayed(const Duration(milliseconds: 50));
      expect(signals.newOrderAlert.value, isNull);

      final newOrder = createSampleOrder(
        id: 602,
        accountNumber: 'ACC-602',
        fullName: 'Juan Dela Cruz',
        concern: 'Red LOS Light',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(newOrder);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newOrderAlert.value, isNotNull);
      expect(signals.newOrderAlert.value?.id, 602);
      expect(signals.newOrderAlert.value?.accountNumber, 'ACC-602');
      expect(signals.newOrderAlert.value?.fullName, 'Juan Dela Cruz');
      expect(alertedOrder?.id, 602);

      signals.dismissAlert();
      expect(signals.newOrderAlert.value, isNull);
    });

    test('Completed/Resolved service orders do not trigger alert', () async {
      ServiceOrderDto? alertedOrder;
      final signals = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: MockServiceOrdersApi(),
        onNewOrderAlert: (order) => alertedOrder = order,
      );
      addTearDown(() => signals.dispose());

      await Future.delayed(const Duration(milliseconds: 50));

      // Insert Done service order
      final doneOrder = createSampleOrder(
        id: 603,
        accountNumber: 'ACC-603',
        fullName: 'Done Customer',
        visitStatus: 'Done',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(doneOrder);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(signals.newOrderAlert.value, isNull);
      expect(alertedOrder, isNull);

      // Insert Resolved supportStatus order
      final resolvedOrder = createSampleOrder(
        id: 604,
        accountNumber: 'ACC-604',
        fullName: 'Resolved Customer',
        supportStatus: 'Resolved',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(resolvedOrder);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(signals.newOrderAlert.value, isNull);
      expect(alertedOrder, isNull);
    });

    test(
        'Orders assigned to another technician do not trigger alert when email is scoped',
        () async {
      ServiceOrderDto? alertedOrder;
      final signals = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: MockServiceOrdersApi(),
        onNewOrderAlert: (order) => alertedOrder = order,
      );
      addTearDown(() => signals.dispose());

      signals.setTechnicianEmail('tech1@switchfiber.ph');
      await Future.delayed(const Duration(milliseconds: 50));

      final otherTechOrder = createSampleOrder(
        id: 605,
        accountNumber: 'ACC-605',
        fullName: 'Other Tech Customer',
        assignedEmail: 'other_tech@switchfiber.ph',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(otherTechOrder);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(signals.newOrderAlert.value, isNull);
      expect(alertedOrder, isNull);
    });

    test('Reassigning an existing order to the technician triggers alert',
        () async {
      final initialOtherOrder = createSampleOrder(
        id: 606,
        accountNumber: 'ACC-606',
        fullName: 'Reassigned Customer',
        assignedEmail: 'someone_else@switchfiber.ph',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(initialOtherOrder);

      ServiceOrderDto? alertedOrder;
      final signals = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: MockServiceOrdersApi(),
        onNewOrderAlert: (order) => alertedOrder = order,
      );
      addTearDown(() => signals.dispose());

      signals.setTechnicianEmail('tech1@switchfiber.ph');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(signals.newOrderAlert.value, isNull);

      // Now reassign to tech1
      final reassignedOrder = createSampleOrder(
        id: 606,
        accountNumber: 'ACC-606',
        fullName: 'Reassigned Customer',
        assignedEmail: 'tech1@switchfiber.ph',
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(reassignedOrder);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(signals.newOrderAlert.value?.id, 606);
      expect(alertedOrder?.id, 606);
    });
  });

  group('TechnicianShell Service Order Alert Banner Widget Tests', () {
    testWidgets(
        'Displays top alert banner for new service order and dismisses on X tap',
        (tester) async {
      late final AppDatabase db;
      late final JobRepository repository;
      late final JobsSignals jobsSignals;
      late final LcpNapSignals lcpNapSignals;
      late final ServiceOrdersSignals serviceOrdersSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        repository = JobRepository(db.jobOrdersDao, api: MockJobOrdersApi());
        jobsSignals = JobsSignals(repository);
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
        serviceOrdersSignals = ServiceOrdersSignals(
          dao: db.serviceOrdersDao,
          api: MockServiceOrdersApi(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        serviceOrdersSignals.dispose();
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
            jobsSignals: jobsSignals,
            lcpNapSignals: lcpNapSignals,
            serviceOrdersSignals: serviceOrdersSignals,
            enableAutoSync: false,
          ),
        ),
      );

      await tester.pump();

      // Initially no banner
      expect(find.text('NEW SERVICE ORDER'), findsNothing);

      // Trigger new service order alert signal
      final testOrder = createSampleOrder(
        id: 777,
        accountNumber: 'ACC-SO-777',
        fullName: 'Pedro Penduko',
        concern: 'ONT Fiber Cut',
      );
      serviceOrdersSignals.newOrderAlert.value = testOrder;

      await tester.pump();

      // Alert banner is now visible
      expect(find.text('NEW SERVICE ORDER'), findsOneWidget);
      expect(find.text('ACC-SO-777'), findsOneWidget);
      expect(find.text('Pedro Penduko'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);

      // Tap dismiss ("X") button
      final dismissButton = find.byTooltip('Dismiss');
      expect(dismissButton, findsOneWidget);
      await tester.tap(dismissButton);
      await tester.pump();

      // Banner is removed
      expect(find.text('NEW SERVICE ORDER'), findsNothing);
      expect(serviceOrdersSignals.newOrderAlert.value, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'Tapping View button on service order banner navigates to ServiceOrderDetailScreen and dismisses banner',
        (tester) async {
      late final AppDatabase db;
      late final JobRepository repository;
      late final JobsSignals jobsSignals;
      late final LcpNapSignals lcpNapSignals;
      late final ServiceOrdersSignals serviceOrdersSignals;

      final testOrder = createSampleOrder(
        id: 888,
        accountNumber: 'ACC-SO-888',
        fullName: 'Maria Clara',
        concern: 'High Loss / Red LOS',
      );

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        repository = JobRepository(db.jobOrdersDao, api: MockJobOrdersApi());
        jobsSignals = JobsSignals(repository);
        lcpNapSignals = LcpNapSignals(LcpNapRepository(LcpNapLocationsDao(db)));
        serviceOrdersSignals = ServiceOrdersSignals(
          dao: db.serviceOrdersDao,
          api: MockServiceOrdersApi(),
        );
        await db.serviceOrdersDao.insertOrUpdateOrder(testOrder);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        serviceOrdersSignals.dispose();
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
            jobsSignals: jobsSignals,
            lcpNapSignals: lcpNapSignals,
            serviceOrdersSignals: serviceOrdersSignals,
            enableAutoSync: false,
          ),
        ),
      );

      await tester.pump();

      serviceOrdersSignals.newOrderAlert.value = testOrder;

      await tester.pump();

      expect(find.text('NEW SERVICE ORDER'), findsOneWidget);

      // Tap View button
      await tester.tap(find.text('View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Alert is dismissed
      expect(serviceOrdersSignals.newOrderAlert.value, isNull);

      // Navigated to ServiceOrderDetailScreen
      expect(find.byType(ServiceOrderDetailScreen), findsOneWidget);
      expect(find.text('Maria Clara'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
