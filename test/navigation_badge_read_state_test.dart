import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/core/theme/app_theme.dart';
import 'package:swithfiber_tech_ps/core/widgets/status_rail_row.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/models/job_order_model.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/screens/job_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/models/lcp_nap_model.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_order_detail_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/screens/service_orders_screen.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/shell/technician_shell.dart';

class _StubJobsApi extends JobOrdersApi {
  final List<Map<String, dynamic>> scheduled;
  final List<Map<String, dynamic>> rescheduled;
  final List<Map<String, dynamic>> activated;

  _StubJobsApi({
    this.scheduled = const [],
    this.rescheduled = const [],
    this.activated = const [],
  });

  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusAssigned({
    required String status,
    String? assignedEmail,
  }) async {
    if (status == 'Scheduled') return scheduled;
    if (status == 'Rescheduled') return rescheduled;
    if (status == 'Activated') return activated;
    return [];
  }

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

class _StubServiceOrdersApi extends ServiceOrdersApi {
  final List<ServiceOrderDto> orders;

  _StubServiceOrdersApi({this.orders = const []});

  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async => orders;
}

JobOrderDto _makeJob(
  int id,
  String name, {
  String status = 'Scheduled',
  String onsite = 'Scheduled',
  String? assignedEmail = 'tech@switchfiber.ph',
}) =>
    JobOrderDto(
      id: id,
      ticketNumber: 'SF-2026-00$id',
      customerName: name,
      address: 'Lot $id, Fiber Street',
      barangay: 'Batingan',
      city: 'Binangonan',
      status: status,
      onsiteStatus: onsite,
      contactNumber: '09171234567',
      assignedEmail: assignedEmail,
      isSynced: true,
      updatedAt: DateTime.now(),
    );

ServiceOrderDto _makeOrder(
  int id,
  String name, {
  String supportStatus = 'Open',
  String? visitStatus = 'Pending',
  String? assignedEmail = 'tech@switchfiber.ph',
}) =>
    ServiceOrderDto(
      id: id,
      accountNumber: 'ACC-00$id',
      fullName: name,
      contactNumber: '09171234567',
      emailAddress: 'sub$id@example.com',
      address: 'Lot $id, Repair Ave',
      barangay: 'Batingan',
      city: 'Binangonan',
      concern: 'No Connection',
      priorityLevel: 'Normal',
      supportStatus: supportStatus,
      visitStatus: visitStatus,
      assignedEmail: assignedEmail,
      isSynced: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const techEmail = 'tech@switchfiber.ph';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AuthSignals.instance.currentUser.value = UserModel(
      id: 1,
      username: 'tech_juan',
      fname: 'Juan',
      lname: 'Dela Cruz',
      email: techEmail,
    );
  });

  group('Navigation Bubbles & Read/Unread Tracking', () {
    testWidgets(
        'Plant has no count bubble; Today and Repairs show NEW tags and clear unread counts when clicked or read',
        (tester) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(402 * 3.0, 1200 * 3.0);
      addTearDown(tester.view.reset);

      late AppDatabase db;
      late JobsSignals jobsSignals;
      late LcpNapSignals lcpNapSignals;
      late ServiceOrdersSignals serviceOrdersSignals;

      final scheduled1 = _makeJob(1, 'Job One');
      final scheduled2 = _makeJob(2, 'Job Two');
      final rescheduled = _makeJob(3, 'Job Rescheduled', status: 'Rescheduled');
      final activated = _makeJob(4, 'Job Activated', status: 'Activated');

      final repair1 = _makeOrder(11, 'Repair One');
      final repair2 = _makeOrder(12, 'Repair Two');

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        await db.jobOrdersDao.insertAllJobs(
          [scheduled1, scheduled2, rescheduled, activated],
          synced: true,
        );
        await db.serviceOrdersDao.insertAllOrders(
          [repair1, repair2],
          synced: true,
        );
        final lcpRepo = LcpNapRepository(LcpNapLocationsDao(db));
        await db.lcpNapLocationsDao.insertAllLocations([
          for (var i = 1; i <= 5; i++)
            LcpNapDto(
              id: 500 + i,
              lcp: 'LCP 01',
              nap: 'NAP 00$i',
              lcpNap: 'LCP 01 NAP 00$i',
              portTotal: 16,
              street: 'Manila East Rd',
              barangay: 'Batingan',
              city: 'Binangonan',
              region: 'Rizal',
              isSynced: true,
            ),
        ]);

        jobsSignals = JobsSignals(
          JobRepository(
            db.jobOrdersDao,
            api: _StubJobsApi(
              scheduled: [
                {
                  'id': 1,
                  'ticketNumber': 'SF-2026-001',
                  'customerName': 'Job One',
                  'address': 'Lot 1, Fiber Street',
                  'barangay': 'Batingan',
                  'city': 'Binangonan',
                  'status': 'Scheduled',
                  'onsiteStatus': 'Scheduled',
                  'contactNumber': '09171234567',
                  'assignedEmail': techEmail,
                },
                {
                  'id': 2,
                  'ticketNumber': 'SF-2026-002',
                  'customerName': 'Job Two',
                  'address': 'Lot 2, Fiber Street',
                  'barangay': 'Batingan',
                  'city': 'Binangonan',
                  'status': 'Scheduled',
                  'onsiteStatus': 'Scheduled',
                  'contactNumber': '09171234567',
                  'assignedEmail': techEmail,
                },
              ],
              rescheduled: [
                {
                  'id': 3,
                  'ticketNumber': 'SF-2026-003',
                  'customerName': 'Job Rescheduled',
                  'address': 'Lot 3, Fiber Street',
                  'barangay': 'Batingan',
                  'city': 'Binangonan',
                  'status': 'Rescheduled',
                  'onsiteStatus': 'Reschedule',
                  'contactNumber': '09171234567',
                  'assignedEmail': techEmail,
                },
              ],
              activated: [
                {
                  'id': 4,
                  'ticketNumber': 'SF-2026-004',
                  'customerName': 'Job Activated',
                  'address': 'Lot 4, Fiber Street',
                  'barangay': 'Batingan',
                  'city': 'Binangonan',
                  'status': 'Activated',
                  'onsiteStatus': 'Done',
                  'contactNumber': '09171234567',
                  'assignedEmail': techEmail,
                },
              ],
            ),
          ),
        );
        lcpNapSignals = LcpNapSignals(lcpRepo);
        serviceOrdersSignals = ServiceOrdersSignals(
          dao: db.serviceOrdersDao,
          api: _StubServiceOrdersApi(orders: [repair1, repair2]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await jobsSignals.dispose();
          await lcpNapSignals.dispose();
          serviceOrdersSignals.dispose();
          await db.close();
        });
      });

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: TechnicianShell(
              authSignals: AuthSignals.instance,
              jobsSignals: jobsSignals,
              lcpNapSignals: lcpNapSignals,
              serviceOrdersSignals: serviceOrdersSignals,
              enableAutoSync: false,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final todayTab = find.ancestor(
        of: find.text('Today'),
        matching: find.byType(GestureDetector),
      );
      final repairsTab = find.ancestor(
        of: find.text('Repairs'),
        matching: find.byType(GestureDetector),
      );
      final plantTab = find.ancestor(
        of: find.text('Plant'),
        matching: find.byType(GestureDetector),
      );

      // 1. Plant tab never displays a count bubble even with 5 seeded sites.
      expect(lcpNapSignals.totalSitesCount.value, 5);
      expect(
        find.descendant(of: plantTab, matching: find.text('5')),
        findsNothing,
      );

      // 2. Today bubble counts only unread scheduled jobs (2, excluding rescheduled & activated)
      // and Repairs bubble counts unread open repairs (2).
      expect(
        find.descendant(of: todayTab, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: repairsTab, matching: find.text('2')),
        findsOneWidget,
      );
      // Only the 2 scheduled jobs carry NEW; rescheduled does not.
      expect(find.text('NEW'), findsNWidgets(2));

      // 3. Clicking the first job in the list marks it read, removes its NEW tag,
      // and decrements the Today bubble from 2 to 1.
      await tester.tap(find.text('Job One'));
      await tester.pump();
      expect(
        find.descendant(of: todayTab, matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.text('NEW'), findsOneWidget);

      // 4. Clicking Details on the second job marks it read, opens JobOrderDetailScreen,
      // and clears the Today bubble completely upon returning.
      final detailsButtons = find.text('DETAILS');
      expect(detailsButtons, findsNWidgets(3));
      final jobTwoRow = find.ancestor(
        of: find.text('Job Two'),
        matching: find.byType(StatusRailRow),
      );
      final jobTwoDetails = find.descendant(
        of: jobTwoRow,
        matching: find.text('DETAILS'),
      );
      await tester.ensureVisible(jobTwoDetails);
      await tester.tap(jobTwoDetails);
      await tester.pumpAndSettle();
      expect(find.byType(JobOrderDetailScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(JobOrderDetailScreen))).pop();
      await tester.pumpAndSettle();

      expect(find.text('NEW'), findsNothing);
      expect(
        find.descendant(of: todayTab, matching: find.text('1')),
        findsNothing,
      );
      expect(jobsSignals.unreadScheduledCount.value, 0);

      // 5. Switch to Repairs tab: both repair cards display NEW tags.
      await tester.runAsync(() async {
        await tester.tap(find.text('Repairs'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('service_order_new_tag_11')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('service_order_new_tag_12')),
          findsOneWidget);
      expect(
        find.descendant(of: repairsTab, matching: find.text('2')),
        findsOneWidget,
      );

      // 6. Tap first repair card -> opens details, marks read -> decrements Repairs bubble to 1.
      await tester.tap(find.text('Repair One'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceOrderDetailScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(ServiceOrderDetailScreen))).pop();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('service_order_new_tag_11')), findsNothing);
      expect(find.byKey(const ValueKey('service_order_new_tag_12')),
          findsOneWidget);
      expect(
        find.descendant(of: repairsTab, matching: find.text('1')),
        findsOneWidget,
      );

      // 7. Tap second repair card -> opens details, marks read -> clears Repairs bubble completely.
      await tester.tap(find.text('Repair Two'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceOrderDetailScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(ServiceOrderDetailScreen))).pop();
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('service_order_new_tag_12')), findsNothing);
      expect(
        find.descendant(of: repairsTab, matching: find.text('1')),
        findsNothing,
      );
      expect(serviceOrdersSignals.unreadCount.value, 0);
    });

    test(
        'Read job and service order IDs persist across signal restarts per technician and stay unread for newly synced items',
        () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);

      await db.jobOrdersDao.insertAllJobs([
        _makeJob(101, 'Persisted Job'),
      ], synced: true);
      await db.serviceOrdersDao.insertAllOrders([
        _makeOrder(201, 'Persisted Repair'),
      ], synced: true);

      // First session: restore, mark both items read, wait for storage write.
      final jobs1 = JobsSignals(
        JobRepository(db.jobOrdersDao, api: _StubJobsApi()),
      );
      final orders1 = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: _StubServiceOrdersApi(),
      );
      jobs1.setTechnicianEmail(techEmail);
      orders1.setTechnicianEmail(techEmail);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(jobs1.unreadScheduledCount.value, 1);
      expect(orders1.unreadCount.value, 1);

      jobs1.markJobAsRead(101);
      orders1.markOrderAsRead(201);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(jobs1.unreadScheduledCount.value, 0);
      expect(orders1.unreadCount.value, 0);

      await jobs1.dispose();
      orders1.dispose();

      // Second session (fresh signals instances simulating app restart):
      final jobs2 = JobsSignals(
        JobRepository(db.jobOrdersDao, api: _StubJobsApi()),
      );
      final orders2 = ServiceOrdersSignals(
        dao: db.serviceOrdersDao,
        api: _StubServiceOrdersApi(),
      );
      addTearDown(() async {
        await jobs2.dispose();
        orders2.dispose();
      });

      jobs2.setTechnicianEmail(techEmail);
      orders2.setTechnicianEmail(techEmail);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(jobs2.unreadScheduledCount.value, 0);
      expect(orders2.unreadCount.value, 0);

      // Calling setTechnicianEmail again with whitespace/casing difference must not wipe state.
      jobs2.setTechnicianEmail(' TECH@SWITCHFIBER.PH ');
      orders2.setTechnicianEmail(' TECH@SWITCHFIBER.PH ');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(jobs2.unreadScheduledCount.value, 0);
      expect(orders2.unreadCount.value, 0);

      // A newly added job or service order appears as unread (NEW) and increments count to 1.
      await db.jobOrdersDao.insertOrUpdateJob(
        _makeJob(102, 'Brand New Job'),
        synced: true,
      );
      await db.serviceOrdersDao.insertOrUpdateOrder(
        _makeOrder(202, 'Brand New Repair'),
        synced: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(jobs2.unreadScheduledCount.value, 1);
      expect(jobs2.isJobUnread(_makeJob(102, 'Brand New Job')), isTrue);
      expect(jobs2.isJobUnread(_makeJob(101, 'Persisted Job')), isFalse);

      expect(orders2.unreadCount.value, 1);
      expect(orders2.isOrderUnread(_makeOrder(202, 'Brand New Repair')), isTrue);
      expect(
          orders2.isOrderUnread(_makeOrder(201, 'Persisted Repair')), isFalse);

      // Switching to a different technician scopes read state cleanly.
      jobs2.setTechnicianEmail('other@switchfiber.ph');
      orders2.setTechnicianEmail('other@switchfiber.ph');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(jobs2.isJobRead(101), isFalse);
      expect(orders2.isOrderRead(201), isFalse);
    });

    testWidgets(
        'Unread NEW tags on JobOrdersScreen and ServiceOrdersScreen do not overflow at 200% text scale on 402dp width',
        (tester) async {
      late AppDatabase db;
      late JobsSignals jobs;
      late ServiceOrdersSignals orders;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        await db.jobOrdersDao.insertOrUpdateJob(
          _makeJob(301, 'Very Long Subscriber Name At Maximum Scale'),
          synced: true,
        );
        await db.serviceOrdersDao.insertOrUpdateOrder(
          _makeOrder(401, 'Very Long Repair Subscriber Name'),
          synced: true,
        );
        jobs = JobsSignals(
          JobRepository(db.jobOrdersDao, api: _StubJobsApi()),
        );
        orders = ServiceOrdersSignals(
          dao: db.serviceOrdersDao,
          api: _StubServiceOrdersApi(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });

      addTearDown(() async {
        await tester.runAsync(() async {
          await jobs.dispose();
          orders.dispose();
          await db.close();
        });
      });

      Future<List<String>> pumpAt200(Widget child) async {
        tester.view.devicePixelRatio = 3.0;
        tester.view.physicalSize = const Size(402 * 3.0, 874 * 3.0);
        addTearDown(tester.view.reset);

        final errors = <String>[];
        final original = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d.toString());
        addTearDown(() => FlutterError.onError = original);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: child,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        FlutterError.onError = original;
        tester.takeException();
        return errors.where((e) => e.contains('overflowed')).toList();
      }

      final jobOverflows = await pumpAt200(JobOrdersScreen(jobsSignals: jobs));
      expect(jobOverflows, isEmpty, reason: jobOverflows.join('\n'));
      expect(find.text('NEW'), findsOneWidget);

      final orderOverflows =
          await pumpAt200(ServiceOrdersScreen(signals: orders));
      expect(orderOverflows, isEmpty, reason: orderOverflows.join('\n'));
      expect(find.byKey(const ValueKey('service_order_new_tag_401')),
          findsOneWidget);
    });
  });
}
