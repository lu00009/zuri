import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  static final Map<String, Database> _databases = {};
  static const String _defaultDbName = 'pocketbrain_default.db';

  static String _resolveDbName(String? userId) {
    if (userId == null || userId.trim().isEmpty) {
      return _defaultDbName;
    }
    final sanitized = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'pocketbrain_$sanitized.db';
  }

  /// Returns the database instance for the specified user, initializing if necessary.
  static Future<Database> getDatabase({String? userId, Database? overrideDatabase}) async {
    if (overrideDatabase != null) {
      return overrideDatabase;
    }
    final dbName = _resolveDbName(userId);
    if (_databases.containsKey(dbName) && _databases[dbName]!.isOpen) {
      return _databases[dbName]!;
    }

    _initFfiIfNeeded();

    final dbPath = await _resolveDatabasePath(dbName);
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _onCreate,
    );
    _databases[dbName] = db;
    return db;
  }

  static void _initFfiIfNeeded() {
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<String> _resolveDatabasePath(String dbName) async {
    if (kIsWeb) {
      return dbName;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final databasesPath = await getDatabasesPath();
      return join(databasesPath, dbName);
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      return join(docDir.path, 'pocketbrain', dbName);
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    // 1. Notes table
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        project_id TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        server_version INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 2. Note Tags table (Many-to-many relationship)
    await db.execute('''
      CREATE TABLE note_tags (
        note_id TEXT NOT NULL,
        tag TEXT NOT NULL,
        PRIMARY KEY (note_id, tag),
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');

    // 3. Sync Operations Queue (offline mutation tracking)
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

    // Indexes for fast querying, filtering, and sorting
    await db.execute('CREATE INDEX idx_notes_updated_at ON notes(updated_at DESC)');
    await db.execute('CREATE INDEX idx_notes_status ON notes(is_deleted, is_archived, is_pinned)');
    await db.execute('CREATE INDEX idx_notes_project ON notes(project_id)');
    await db.execute('CREATE INDEX idx_note_tags_tag ON note_tags(tag)');
    await db.execute('CREATE INDEX idx_sync_created_at ON sync_operations(created_at ASC)');
  }

  /// Clears all local user data from tables on logout or account switch
  static Future<void> clearAllData({String? userId, Database? overrideDatabase}) async {
    final db = await getDatabase(userId: userId, overrideDatabase: overrideDatabase);
    await db.transaction((txn) async {
      await txn.delete('note_tags');
      await txn.delete('notes');
      await txn.delete('sync_operations');
    });
  }

  /// Closes database for clean testing teardown
  static Future<void> close() async {
    for (final db in _databases.values) {
      if (db.isOpen) {
        await db.close();
      }
    }
    _databases.clear();
  }
}
