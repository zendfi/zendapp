import 'dart:async';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static AppDatabase? _instance;
  static Database? _db;

  AppDatabase._();

  static AppDatabase get instance {
    _instance ??= AppDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'zend_pool_messages.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pool_messages (
            id TEXT PRIMARY KEY,
            pool_id TEXT NOT NULL,
            client_id TEXT,
            server_id TEXT,
            sender_user_id TEXT,
            sender_zendtag TEXT,
            sender_avatar_url TEXT,
            message_type TEXT NOT NULL,
            content TEXT,
            contribution_id TEXT,
            voice_note_url TEXT,
            voice_note_duration_seconds INTEGER,
            waveform_data TEXT,
            local_status TEXT NOT NULL DEFAULT 'delivered',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pool_message_reactions (
            message_id TEXT NOT NULL,
            emoji TEXT NOT NULL,
            count INTEGER NOT NULL,
            reacted_by_me INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (message_id, emoji)
          )
        ''');
        await db.execute('''
          CREATE TABLE pool_sync_cursors (
            pool_id TEXT PRIMARY KEY,
            oldest_fetched_server_id TEXT,
            last_synced_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pool_messages_pool_id ON pool_messages(pool_id)',
        );
        await db.execute(
          'CREATE INDEX idx_pool_messages_created_at ON pool_messages(created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_pool_messages_client_id ON pool_messages(client_id)',
        );
        await db.execute(
          'CREATE INDEX idx_pool_messages_server_id ON pool_messages(server_id)',
        );
        await db.execute(
          'CREATE INDEX idx_pool_messages_local_status ON pool_messages(local_status)',
        );
      },
    );
  }

  Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }
}
