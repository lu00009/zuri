import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'app_database.dart';

class SyncOperationRecord {
  final String opId;
  final String entityType;
  final String entityId;
  final String opType;
  final int clientVersion;
  final Map<String, dynamic> payload;
  final int createdAt;
  final int attempts;
  final String? lastError;

  const SyncOperationRecord({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.opType,
    required this.clientVersion,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  Map<String, dynamic> toPushPayload() {
    return {
      'op_id': opId,
      'entity_type': entityType,
      'entity_id': entityId,
      'op_type': opType,
      'client_version': clientVersion,
      'client_updated_at': DateTime.fromMillisecondsSinceEpoch(createdAt).toUtc().toIso8601String(),
      'payload': payload,
    };
  }
}

class SyncQueueDataSource {
  final Database? overrideDb;
  final String? userId;

  SyncQueueDataSource({this.overrideDb, this.userId});

  Future<Database> get _db async => AppDatabase.getDatabase(userId: userId, overrideDatabase: overrideDb);

  Future<String> enqueue({
    required String entityId,
    required String opType,
    int clientVersion = 0,
    required Map<String, dynamic> payload,
    String entityType = 'note',
  }) async {
    final db = await _db;
    final opId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Attach client_version to payload for serialization
    final enrichedPayload = Map<String, dynamic>.from(payload);
    enrichedPayload['_client_version'] = clientVersion;

    await db.insert(
      'sync_operations',
      {
        'op_id': opId,
        'entity_type': entityType,
        'entity_id': entityId,
        'op_type': opType,
        'payload': jsonEncode(enrichedPayload),
        'created_at': now,
        'attempts': 0,
        'last_error': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return opId;
  }

  Future<List<SyncOperationRecord>> getPendingOperations({int limit = 50}) async {
    final db = await _db;
    final maps = await db.query(
      'sync_operations',
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return maps.map((row) {
      final payloadRaw = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final clientVer = (payloadRaw['_client_version'] as int?) ?? 0;

      return SyncOperationRecord(
        opId: row['op_id'] as String,
        entityType: row['entity_type'] as String,
        entityId: row['entity_id'] as String,
        opType: row['op_type'] as String,
        clientVersion: clientVer,
        payload: payloadRaw,
        createdAt: row['created_at'] as int,
        attempts: row['attempts'] as int? ?? 0,
        lastError: row['last_error'] as String?,
      );
    }).toList();
  }

  Future<int> getPendingCount() async {
    final db = await _db;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM sync_operations');
    return (res.first['count'] as int?) ?? 0;
  }

  Future<void> removeOperation(String opId) async {
    final db = await _db;
    await db.delete('sync_operations', where: 'op_id = ?', whereArgs: [opId]);
  }

  Future<void> recordFailure(String opId, String error) async {
    final db = await _db;
    await db.rawUpdate('''
      UPDATE sync_operations 
      SET attempts = attempts + 1, last_error = ? 
      WHERE op_id = ?
    ''', [error, opId]);
  }
}
