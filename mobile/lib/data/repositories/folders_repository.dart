import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../../domain/entities/folder.dart';
import '../datasources/local/app_database.dart';

abstract class FoldersRepository {
  Future<List<Folder>> getFolders({String? searchQuery});
  Future<Folder?> getFolderById(String id);
  Future<void> saveFolder(Folder folder);
  Future<void> deleteFolder(String id);
  Future<void> togglePin(String id);
  Future<void> moveNoteToFolder({required String noteId, required String? folderId});
  Future<void> removeNoteFromFolder(String noteId);
  Future<String?> copyAndSaveCoverImage(String folderId, String sourceFilePath);
}

class FoldersLocalRepository implements FoldersRepository {
  final Database? overrideDatabase;
  final String? userId;

  FoldersLocalRepository({
    this.overrideDatabase,
    this.userId,
  });

  Future<Database> get _db async =>
      AppDatabase.getDatabase(userId: userId, overrideDatabase: overrideDatabase);

  @override
  Future<List<Folder>> getFolders({String? searchQuery}) async {
    final db = await _db;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClauses.add('name LIKE ?');
      whereArgs.add('%${searchQuery.trim()}%');
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final rows = await db.query(
      'folders',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'is_pinned DESC, updated_at DESC',
    );

    if (rows.isEmpty) return [];

    // Query note counts per folder
    final countRows = await db.rawQuery('''
      SELECT project_id, COUNT(*) as count 
      FROM notes 
      WHERE is_deleted = 0 AND is_archived = 0 AND project_id IS NOT NULL 
      GROUP BY project_id
    ''');

    final countsMap = <String, int>{};
    for (final row in countRows) {
      final pid = row['project_id'] as String?;
      final count = (row['count'] as num?)?.toInt() ?? 0;
      if (pid != null) {
        countsMap[pid] = count;
      }
    }

    return rows.map((r) {
      final folderId = r['id'] as String;
      return Folder.fromMap(r, noteCount: countsMap[folderId] ?? 0);
    }).toList();
  }

  @override
  Future<Folder?> getFolderById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'folders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final countRow = await db.rawQuery(
      'SELECT COUNT(*) as count FROM notes WHERE is_deleted = 0 AND is_archived = 0 AND project_id = ?',
      [id],
    );
    final count = (countRow.first['count'] as num?)?.toInt() ?? 0;

    return Folder.fromMap(rows.first, noteCount: count);
  }

  @override
  Future<void> saveFolder(Folder folder) async {
    final db = await _db;
    await db.insert(
      'folders',
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteFolder(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      // 1. Unassign all notes from this folder (notes are never deleted!)
      await txn.update(
        'notes',
        {
          'project_id': null,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'project_id = ?',
        whereArgs: [id],
      );

      // 2. Fetch cover image to clean up local disk file if exists
      final folderRows = await txn.query(
        'folders',
        columns: ['cover_image_path'],
        where: 'id = ?',
        whereArgs: [id],
      );

      if (folderRows.isNotEmpty) {
        final path = folderRows.first['cover_image_path'] as String?;
        if (path != null && !kIsWeb) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
        }
      }

      // 3. Delete folder
      await txn.delete(
        'folders',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  @override
  Future<void> togglePin(String id) async {
    final db = await _db;
    final folder = await getFolderById(id);
    if (folder == null) return;

    await db.update(
      'folders',
      {
        'is_pinned': folder.isPinned ? 0 : 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> moveNoteToFolder({required String noteId, required String? folderId}) async {
    final db = await _db;
    await db.update(
      'notes',
      {
        'project_id': folderId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  @override
  Future<void> removeNoteFromFolder(String noteId) async {
    await moveNoteToFolder(noteId: noteId, folderId: null);
  }

  @override
  Future<String?> copyAndSaveCoverImage(String folderId, String sourceFilePath) async {
    if (kIsWeb) {
      // On web, picked files are ephemeral blob URLs or paths
      return sourceFilePath;
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final coversDir = Directory(join(docDir.path, 'zuri', 'folder_covers'));
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final ext = extension(sourceFilePath).isNotEmpty ? extension(sourceFilePath) : '.jpg';
      final fileName = 'folder_${folderId}_${DateTime.now().millisecondsSinceEpoch}$ext';
      final targetPath = join(coversDir.path, fileName);

      final sourceFile = File(sourceFilePath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(targetPath);
        return targetPath;
      }
      return null;
    } catch (e) {
      debugPrint('Error saving folder cover image: $e');
      return sourceFilePath;
    }
  }
}
