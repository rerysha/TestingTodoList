import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

/// Helper class untuk mengelola database lokal (SQLite)
/// yang menyimpan data Task secara offline.
class TaskLocalDb {
  static const String _dbName = 'tasks_offline.db';
  static const int _dbVersion = 1;

  static const String _tableTasks = 'tasks_local';

  static Database? _database;

  // Singleton pattern (opsional, tapi memudahkan reuse instance)
  static final TaskLocalDb instance = TaskLocalDb._internal();

  TaskLocalDb._internal();

  factory TaskLocalDb() {
    return instance;
  }

  // ===================================================================
  // Inisialisasi & Open Database
  // ===================================================================

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    // openDatabase akan membuat file DB jika belum ada.
    return await openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  // Membuat tabel pada saat database pertama kali dibuat.
  FutureOr<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableTasks (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER,
        title TEXT NOT NULL,
        description TEXT,
        completed INTEGER NOT NULL DEFAULT 0,
        user_id TEXT NOT NULL,
        created_at TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ===================================================================
  // Operasi CRUD ke SQLite
  // ===================================================================

  /// Mengambil semua task dari SQLite, diurutkan dari yang terbaru.
  Future<List<Task>> getAllTasks() async {
    final db = await database;

    final maps = await db.query(_tableTasks, orderBy: 'created_at DESC');

    return maps.map((map) => Task.fromMap(map)).toList();
  }

  /// Mengambil semua task yang belum tersinkron ke server (is_synced = 0).
  Future<List<Task>> getUnsyncedTasks() async {
    final db = await database;

    final maps = await db.query(
      _tableTasks,
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );

    return maps.map((map) => Task.fromMap(map)).toList();
  }

  /// Insert task baru ke SQLite.
  /// Mengembalikan local_id (primary key) yang di-generate SQLite.
  Future<int> insertTask(Task task) async {
    final db = await database;

    // Pastikan createdAt terisi jika null.
    final toInsert = task.copyWith(createdAt: task.createdAt ?? DateTime.now());

    final id = await db.insert(
      _tableTasks,
      toInsert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    return id;
  }

  /// Update task berdasarkan local_id.
  /// Digunakan untuk update completed, serverId, dan isSynced.
  Future<int> updateTask(Task task) async {
    if (task.localId == null) return 0;

    final db = await database;

    return await db.update(
      _tableTasks,
      task.toMap(),
      where: 'local_id = ?',
      whereArgs: [task.localId],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Menghapus task dari SQLite berdasarkan local_id.
  Future<int> deleteTask(int localId) async {
    final db = await database;

    return await db.delete(
      _tableTasks,
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  /// Menghapus semua task dan mengisi ulang dari data server
  /// (misalnya setelah full sync sukses).
  Future<void> replaceAllTasks(List<Task> tasks) async {
    final db = await database;
    final batch = db.batch();

    // Kosongkan tabel.
    batch.delete(_tableTasks);

    // Insert ulang dengan isSynced = true (data dari server).
    for (final task in tasks) {
      final syncedTask = task.copyWith(localId: null, isSynced: true);

      batch.insert(
        _tableTasks,
        syncedTask.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Opsional: clear semua data lokal (misalnya saat logout).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(_tableTasks);
  }
}
