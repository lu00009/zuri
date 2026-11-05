import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../domain/entities/note.dart';
import '../datasources/local/app_database.dart';
import '../datasources/local/sync_queue_data_source.dart';

abstract class NotesRepository {
  Future<List<Note>> getNotes({
    bool includeArchived = false,
    String? searchQuery,
    String? tag,
    String? projectId,
  });

  Future<Note?> getNoteById(String id);

  Future<void> saveNote(Note note, {bool isRemoteSync = false});

  Future<void> togglePin(String id);

  Future<void> setArchived(String id, bool isArchived);

  Future<void> deleteNote(String id, {bool softDelete = true, bool isRemoteSync = false});

  Future<List<String>> getAllTags();

  Future<List<String>> getAllProjects();

  Future<void> clearAllLocalData();
}

class NotesLocalRepository implements NotesRepository {
  final Database? overrideDb;
  final String? userId;
  final SyncQueueDataSource _syncQueue;

  NotesLocalRepository({this.overrideDb, this.userId, SyncQueueDataSource? syncQueue})
      : _syncQueue = syncQueue ?? SyncQueueDataSource(overrideDb: overrideDb, userId: userId);

  Future<Database> get _db async => AppDatabase.getDatabase(userId: userId, overrideDatabase: overrideDb);

  @override
  Future<List<Note>> getNotes({
    bool includeArchived = false,
    String? searchQuery,
    String? tag,
    String? projectId,
  }) async {
    final db = await _db;
    final whereClauses = <String>['is_deleted = 0'];
    final whereArgs = <dynamic>[];

    // Archive filter
    whereClauses.add('is_archived = ?');
    whereArgs.add(includeArchived ? 1 : 0);

    // Project filter
    if (projectId != null && projectId.isNotEmpty) {
      whereClauses.add('project_id = ?');
      whereArgs.add(projectId);
    }

    // Text search query
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClauses.add('(title LIKE ? OR content LIKE ?)');
      final term = '%${searchQuery.trim()}%';
      whereArgs.addAll([term, term]);
    }

    // Tag filter: if a tag is specified, filter by subquery
    if (tag != null && tag.trim().isNotEmpty) {
      whereClauses.add('id IN (SELECT note_id FROM note_tags WHERE tag = ?)');
      whereArgs.add(tag.trim().toLowerCase());
    }

    final whereString = whereClauses.join(' AND ');

    final noteMaps = await db.query(
      'notes',
      where: whereString,
      whereArgs: whereArgs,
      orderBy: 'is_pinned DESC, updated_at DESC',
    );

    if (noteMaps.isEmpty) {
      return [];
    }

    // Fetch tags in batch
    final noteIds = noteMaps.map((m) => m['id'] as String).toList();
    final tagsByNoteId = await _fetchTagsForNotes(db, noteIds);

    return noteMaps.map((map) {
      final id = map['id'] as String;
      final tags = tagsByNoteId[id] ?? [];
      return Note.fromMap(map, tags: tags);
    }).toList();
  }

  @override
  Future<Note?> getNoteById(String id) async {
    final db = await _db;
    final maps = await db.query(
      'notes',
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) {
      return null;
    }

    final tags = await _fetchTagsForNote(db, id);
    return Note.fromMap(maps.first, tags: tags);
  }

  @override
  Future<void> saveNote(Note note, {bool isRemoteSync = false}) async {
    final db = await _db;

    // Determine if this was an existing note to set CREATE vs UPDATE
    final existing = await getNoteById(note.id);

    await db.transaction((txn) async {
      // 1. Insert or update note record
      await txn.insert(
        'notes',
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Replace tags
      await txn.delete(
        'note_tags',
        where: 'note_id = ?',
        whereArgs: [note.id],
      );

      for (final tag in note.tags) {
        final cleanTag = tag.trim().toLowerCase();
        if (cleanTag.isNotEmpty) {
          await txn.insert(
            'note_tags',
            {'note_id': note.id, 'tag': cleanTag},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });

    // 3. If local user mutation, enqueue to sync queue
    if (!isRemoteSync) {
      final opType = (existing != null) ? 'UPDATE' : 'CREATE';
      await _syncQueue.enqueue(
        entityId: note.id,
        opType: opType,
        clientVersion: note.serverVersion,
        payload: {
          'title': note.title,
          'content': note.content,
          'project_id': note.projectId,
          'tags': note.tags,
          'is_pinned': note.isPinned,
          'is_archived': note.isArchived,
        },
      );
    }
  }

  @override
  Future<void> togglePin(String id) async {
    final note = await getNoteById(id);
    if (note != null) {
      final updated = note.copyWith(
        isPinned: !note.isPinned,
        updatedAt: DateTime.now(),
      );
      await saveNote(updated);
    }
  }

  @override
  Future<void> setArchived(String id, bool isArchived) async {
    final note = await getNoteById(id);
    if (note != null) {
      final updated = note.copyWith(
        isArchived: isArchived,
        isPinned: isArchived ? false : note.isPinned,
        updatedAt: DateTime.now(),
      );
      await saveNote(updated);
    }
  }

  @override
  Future<void> deleteNote(String id, {bool softDelete = true, bool isRemoteSync = false}) async {
    final db = await _db;
    final note = await getNoteById(id);

    if (softDelete) {
      await db.update(
        'notes',
        {
          'is_deleted': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    }

    if (!isRemoteSync && note != null) {
      await _syncQueue.enqueue(
        entityId: id,
        opType: 'DELETE',
        clientVersion: note.serverVersion,
        payload: {},
      );
    }
  }

  @override
  Future<List<String>> getAllTags() async {
    final db = await _db;
    final results = await db.rawQuery('''
      SELECT DISTINCT nt.tag 
      FROM note_tags nt
      JOIN notes n ON n.id = nt.note_id
      WHERE n.is_deleted = 0
      ORDER BY nt.tag ASC
    ''');
    return results.map((row) => row['tag'] as String).toList();
  }

  @override
  Future<List<String>> getAllProjects() async {
    final db = await _db;
    final results = await db.rawQuery('''
      SELECT DISTINCT project_id 
      FROM notes 
      WHERE is_deleted = 0 AND project_id IS NOT NULL AND project_id != ''
      ORDER BY project_id ASC
    ''');
    return results.map((row) => row['project_id'] as String).toList();
  }

  Future<List<String>> _fetchTagsForNote(DatabaseExecutor db, String noteId) async {
    final results = await db.query(
      'note_tags',
      columns: ['tag'],
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'tag ASC',
    );
    return results.map((row) => row['tag'] as String).toList();
  }

  Future<Map<String, List<String>>> _fetchTagsForNotes(
    DatabaseExecutor db,
    List<String> noteIds,
  ) async {
    if (noteIds.isEmpty) return {};

    final placeholders = List.filled(noteIds.length, '?').join(',');
    final results = await db.query(
      'note_tags',
      columns: ['note_id', 'tag'],
      where: 'note_id IN ($placeholders)',
      whereArgs: noteIds,
      orderBy: 'tag ASC',
    );

    final map = <String, List<String>>{};
    for (final row in results) {
      final noteId = row['note_id'] as String;
      final tag = row['tag'] as String;
      map.putIfAbsent(noteId, () => []).add(tag);
    }
    return map;
  }

  @override
  Future<void> clearAllLocalData() async {
    await AppDatabase.clearAllData(userId: userId, overrideDatabase: overrideDb);
  }
}
