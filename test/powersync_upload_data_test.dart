import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_backend_connector.dart';
import 'package:swithfiber_tech_ps/core/sync/powersync_schema.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('powersync_upload_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<PowerSyncDatabase> createDb() async {
    final dbPath = p.join(
      tempDir.path,
      'test_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final db = PowerSyncDatabase(
      schema: powerSyncSchema,
      path: dbPath,
    );
    await db.initialize();
    return db;
  }

  group('SwitchFiberBackendConnector uploadData unit tests', () {
    test('returns safely without error when no transaction is available (null)',
        () async {
      final db = await createDb();
      try {
        bool onUploadCalled = false;
        final connector = SwitchFiberBackendConnector(
          onUpload: (tx) async {
            onUploadCalled = true;
          },
        );

        // No transactions exist initially
        expect(await db.getNextCrudTransaction(), isNull);

        // Should return cleanly without throwing and without invoking onUpload
        await expectLater(connector.uploadData(db), completes);
        expect(onUploadCalled, isFalse);
      } finally {
        await db.close();
      }
    });

    test(
        'executes onUpload when a transaction is pending and calls complete() on success',
        () async {
      final db = await createDb();
      try {
        // Enqueue a local mutation on job_orders
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, status) VALUES (uuid(), ?, ?, ?)',
          ['T-1001', 'Juan Dela Cruz', 'scheduled'],
        );

        CrudTransaction? capturedTx;
        bool uploadHandlerInvoked = false;

        final connector = SwitchFiberBackendConnector(
          onUpload: (tx) async {
            uploadHandlerInvoked = true;
            capturedTx = tx;
          },
        );

        await connector.uploadData(db);

        // Verify onUpload was called with the queued transaction
        expect(uploadHandlerInvoked, isTrue);
        expect(capturedTx, isNotNull);
        expect(capturedTx!.crud.length, 1);
        expect(capturedTx!.crud.first.table, 'job_orders');
        expect(capturedTx!.crud.first.op, UpdateType.put);
        expect(capturedTx!.crud.first.opData?['ticket_number'], 'T-1001');
        expect(
            capturedTx!.crud.first.opData?['customer_name'], 'Juan Dela Cruz');

        // Verify that successful upload called transaction.complete(),
        // so the queue is now empty
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });

    test(
        'does NOT call transaction.complete() and propagates error when onUpload throws',
        () async {
      final db = await createDb();
      try {
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, status) VALUES (uuid(), ?, ?, ?)',
          ['T-1002', 'Maria Santos', 'in_progress'],
        );

        final connector = SwitchFiberBackendConnector(
          onUpload: (tx) async {
            throw Exception('Network 503: Service Unavailable');
          },
        );

        // Upload must bubble up the exception
        expect(
          () => connector.uploadData(db),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Network 503: Service Unavailable'),
            ),
          ),
        );

        // Crucial requirement: transaction.complete() was NOT called,
        // so the transaction remains in ps_crud for retry
        final pendingTx = await db.getNextCrudTransaction();
        expect(pendingTx, isNotNull);
        expect(pendingTx!.crud.first.table, 'job_orders');
        expect(pendingTx.crud.first.opData?['ticket_number'], 'T-1002');
      } finally {
        await db.close();
      }
    });

    test('supports setting and updating onUpload via setter', () async {
      final db = await createDb();
      try {
        await db.execute(
          'INSERT INTO service_orders (id, account_number, full_name, support_status) VALUES (uuid(), ?, ?, ?)',
          ['SO-5001', 'Pedro Penduko', 'pending'],
        );

        final connector = SwitchFiberBackendConnector();
        expect(connector.onUpload, isNull);

        bool setterHandlerCalled = false;
        connector.onUpload = (tx) async {
          setterHandlerCalled = true;
        };
        expect(connector.onUpload, isNotNull);

        await connector.uploadData(db);

        expect(setterHandlerCalled, isTrue);
        // Verified complete() called and queue cleared
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });

    test(
        'supports onEntryUpload callback and bubbles error if entry mutation throws',
        () async {
      final db = await createDb();
      try {
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, status) VALUES (uuid(), ?, ?, ?)',
          ['T-ERR-1', 'Fail Customer', 'scheduled'],
        );

        final connector = SwitchFiberBackendConnector(
          onEntryUpload: (entry) async {
            if (entry.table == 'job_orders') {
              throw Exception('Failed to upload job_order entry');
            }
          },
        );

        expect(
          () => connector.uploadData(db),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to upload job_order entry'),
            ),
          ),
        );

        // Transaction must remain intact for retry
        final pendingTx = await db.getNextCrudTransaction();
        expect(pendingTx, isNotNull);
      } finally {
        await db.close();
      }
    });

    test('completes transaction when all onEntryUpload calls succeed',
        () async {
      final db = await createDb();
      try {
        await db.execute(
          'INSERT INTO service_orders (id, account_number, full_name, support_status) VALUES (uuid(), ?, ?, ?)',
          ['SO-5002', 'Ana Cruz', 'resolved'],
        );

        final processedEntries = <CrudEntry>[];
        final connector = SwitchFiberBackendConnector(
          onEntryUpload: (entry) async {
            processedEntries.add(entry);
          },
        );

        await connector.uploadData(db);

        expect(processedEntries.length, 1);
        expect(processedEntries.first.table, 'service_orders');
        expect(processedEntries.first.opData?['account_number'], 'SO-5002');
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });

    test(
        'throws StateError and preserves mutations in ps_crud when no callbacks are provided',
        () async {
      final db = await createDb();
      try {
        await db.execute(
          'INSERT INTO job_orders (id, ticket_number, customer_name, status) VALUES (uuid(), ?, ?, ?)',
          ['T-DEF-1', 'Default Customer', 'completed'],
        );

        final connector = SwitchFiberBackendConnector();
        expect(connector.onUpload, isNull);
        expect(connector.onEntryUpload, isNull);

        expect(
          () => connector.uploadData(db),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(
                'No upload handler registered to process outbound CRUD transaction',
              ),
            ),
          ),
        );

        // Crucial requirement: transaction.complete() was NOT called,
        // and the mutation remains preserved in ps_crud for retry
        final pendingTx = await db.getNextCrudTransaction();
        expect(pendingTx, isNotNull);
        expect(pendingTx!.crud.first.table, 'job_orders');
        expect(pendingTx.crud.first.opData?['ticket_number'], 'T-DEF-1');
      } finally {
        await db.close();
      }
    });

    test(
        'processes multiple operations in transaction and respects onUpload priority over onEntryUpload',
        () async {
      final db = await createDb();
      try {
        // Enqueue batch writes in a single transaction
        await db.writeTransaction((tx) async {
          await tx.execute(
            'INSERT INTO job_orders (id, ticket_number, customer_name, status) VALUES (uuid(), ?, ?, ?)',
            ['T-BATCH-1', 'Customer One', 'scheduled'],
          );
          await tx.execute(
            'INSERT INTO service_orders (id, account_number, full_name, support_status) VALUES (uuid(), ?, ?, ?)',
            ['SO-BATCH-2', 'Customer Two', 'open'],
          );
        });

        bool onUploadCalled = false;
        bool onEntryUploadCalled = false;

        final connector = SwitchFiberBackendConnector(
          onUpload: (tx) async {
            onUploadCalled = true;
            expect(tx.crud.length, 2);
          },
          onEntryUpload: (entry) async {
            onEntryUploadCalled = true;
          },
        );

        await connector.uploadData(db);

        // onUpload takes precedence when provided
        expect(onUploadCalled, isTrue);
        expect(onEntryUploadCalled, isFalse);
        expect(await db.getNextCrudTransaction(), isNull);
      } finally {
        await db.close();
      }
    });
  });
}
