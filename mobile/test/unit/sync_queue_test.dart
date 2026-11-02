import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pocketbrain/data/datasources/local/sync_queue_data_source.dart';

void main() {
  late Database testDb;
  late SyncQueueDataSource queue;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sync_operations (
              op_id TEXT PRIMARY KEY,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              op_type TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT
            )
          ''');
        },
      ),
    );
    queue = SyncQueueDataSource(overrideDb: testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  group('SyncQueueDataSource', () {
    test('enqueues mutations with stable UUIDs and tracks pending count', () async {
      expect(await queue.getPendingCount(), 0);

      final opId1 = await queue.enqueue(
        entityId: 'note-123',
        opType: 'CREATE',
        clientVersion: 0,
        payload: {'title': 'Offline Note'},
      );

      final opId2 = await queue.enqueue(
        entityId: 'note-456',
        opType: 'UPDATE',
        clientVersion: 1,
        payload: {'title': 'Updated Note'},
      );

      expect(opId1, isNotEmpty);
      expect(opId2, isNotEmpty);
      expect(await queue.getPendingCount(), 2);

      final pending = await queue.getPendingOperations();
      expect(pending.length, 2);
      expect(pending[0].opId, opId1);
      expect(pending[0].entityId, 'note-123');
      expect(pending[0].opType, 'CREATE');
      expect(pending[0].payload['title'], 'Offline Note');

      expect(pending[1].opId, opId2);
      expect(pending[1].clientVersion, 1);

      // Remove opId1 after successful push
      await queue.removeOperation(opId1);
      expect(await queue.getPendingCount(), 1);

      final remaining = await queue.getPendingOperations();
      expect(remaining.length, 1);
      expect(remaining[0].opId, opId2);
    });

    test('records failures and increments attempt counter', () async {
      final opId = await queue.enqueue(
        entityId: 'note-789',
        opType: 'DELETE',
        payload: {},
      );

      await queue.recordFailure(opId, 'Network Timeout 504');

      final pending = await queue.getPendingOperations();
      expect(pending.first.attempts, 1);
      expect(pending.first.lastError, 'Network Timeout 504');
    });
  });
}
