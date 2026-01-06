import 'package:flutter/material.dart';

import '../api/task_api.dart';
import '../local/task_local_db.dart';
import '../models/task.dart';

class TaskProvider extends ChangeNotifier {
  final TaskApiService _apiService;
  final TaskLocalDb _localDb;

  TaskProvider(this._apiService, this._localDb);

  // =========================
  // Auth state
  // =========================
  bool _isAuthenticated = false;
  bool _isAuthLoading = true;
  bool _isTaskLoading = false;
  String? _email;
  String? _userId;
  String? _errorMessage;

  // =========================
  // Task state
  // =========================
  List<Task> _tasks = [];

  // Optional: status koneksi / sync sederhana
  bool _isSyncing = false;

  // =========================
  // Getters
  // =========================
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isAuthLoading; // Backward compatibility
  bool get isAuthLoading => _isAuthLoading;
  bool get isTaskLoading => _isTaskLoading;
  bool get isSyncing => _isSyncing;
  String? get email => _email;
  String? get userId => _userId;
  String? get errorMessage => _errorMessage;
  List<Task> get tasks => _tasks;

  /// Jumlah task yang belum tersinkron ke server
  int get unsyncedCount =>
      _tasks.where((task) => task.isSynced == false).length;

  // =========================
  // AUTH FLOW
  // =========================

  // Check saved session on app start
  Future<void> checkSession() async {
    _isAuthLoading = true;
    notifyListeners();

    final session = await _apiService.loadSession();
    if (session != null) {
      _isAuthenticated = true;
      _email = session['email'];
      _userId = session['userId'];
      // Setelah session valid, langsung load tasks offline-first
      await loadTasksOfflineFirst();
    }

    _isAuthLoading = false;
    notifyListeners();
  }

  // Login
  Future<bool> login(String email, String password) async {
    _errorMessage = null;
    _isAuthLoading = true;
    notifyListeners();

    final result = await _apiService.login(email, password);

    _isAuthLoading = false;

    if (result != null) {
      _isAuthenticated = true;
      _email = result['user']['email'];
      _userId = result['user']['id'];

      // Setelah login sukses, sync data dari server ke lokal
      await loadTasksOfflineFirst();

      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Login gagal. Periksa email dan password.';
      notifyListeners();
      return false;
    }
  }

  // Register
  Future<bool> register(String email, String password) async {
    _errorMessage = null;
    _isAuthLoading = true;
    notifyListeners();

    final result = await _apiService.register(email, password);

    _isAuthLoading = false;

    if (result != null) {
      _isAuthenticated = true;
      _email = result['user']['email'];
      _userId = result['user']['id'].toString();

      // User baru: tidak ada data lama di lokal, tapi tetap panggil sync
      await loadTasksOfflineFirst();

      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Registrasi gagal. Coba email lain.';
      notifyListeners();
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    await _apiService.logout();
    await _localDb.clearAll();

    _isAuthenticated = false;
    _email = null;
    _userId = null;
    _tasks = [];
    notifyListeners();
  }

  // =========================
  // TASK OPERATIONS (OFFLINE-FIRST)
  // =========================

  /// Load tasks dengan strategi offline-first:
  /// 1) Tampilkan dulu data dari SQLite
  /// 2) Coba sync dengan server (Supabase)
  Future<void> loadTasksOfflineFirst() async {
    if (_userId == null) return;

    _isTaskLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Baca dari lokal terlebih dahulu
      _tasks = await _localDb.getAllTasks();
      notifyListeners();

      // 2. Coba sync dengan server
      _isSyncing = true;
      notifyListeners();

      // Ambil semua tasks dari server
      final remoteTasks = await _apiService.getTasks();

      // Map hasil remote agar punya userId & flag isSynced true
      final normalizedRemote = remoteTasks.map((t) {
        return t.copyWith(userId: _userId!, isSynced: true);
      }).toList();

      // Ganti isi tabel lokal dengan data server
      await _localDb.replaceAllTasks(normalizedRemote);

      // Baca ulang dari lokal setelah sync
      _tasks = await _localDb.getAllTasks();
      _errorMessage = null;
    } catch (e) {
      // Kalau gagal sync (misalnya offline), tetap pakai data lokal
      _errorMessage = 'Gagal sinkronisasi dengan server (mode offline).';
    }

    _isSyncing = false;
    _isTaskLoading = false;
    notifyListeners();
  }

  /// Menambah task baru:
  /// - Selalu disimpan ke SQLite
  /// - Jika online, coba kirim ke server dan update flag isSynced
  Future<bool> addTask(String title, String description) async {
    if (_userId == null) return false;

    _errorMessage = null;

    // 1. Simpan ke lokal terlebih dahulu (optimistic)
    final localTask = Task(
      title: title,
      description: description,
      userId: _userId!,
      completed: false,
      isSynced: false,
      createdAt: DateTime.now(),
    );

    final localId = await _localDb.insertTask(localTask);
    final insertedTask = localTask.copyWith(localId: localId);

    // Update list di memori
    _tasks.insert(0, insertedTask);
    notifyListeners();

    // 2. Coba kirim ke server
    try {
      final createdOnServer = await _apiService.createTask(insertedTask);

      if (createdOnServer != null) {
        // Update record lokal: set serverId & isSynced = true
        final syncedTask = insertedTask.copyWith(
          serverId: createdOnServer.serverId,
          isSynced: true,
          createdAt: createdOnServer.createdAt ?? insertedTask.createdAt,
        );

        await _localDb.updateTask(syncedTask);

        // Update di list in-memory
        final index = _tasks.indexWhere(
          (t) => t.localId == insertedTask.localId,
        );
        if (index != -1) {
          _tasks[index] = syncedTask;
        }

        notifyListeners();
        return true;
      } else {
        // Gagal create ke server, tetap ada di lokal dengan isSynced = false
        _errorMessage = 'Task disimpan lokal tetapi gagal ke server.';
        notifyListeners();
        return true; // dari sudut pandang user, tetap berhasil tersimpan
      }
    } catch (e) {
      // Network error, tetap anggap sukses di lokal
      _errorMessage = 'Mode offline: task disimpan lokal.';
      notifyListeners();
      return true;
    }
  }

  /// Toggle completed:
  /// - Update status di SQLite
  /// - Jika punya serverId dan online, update juga di server
  Future<bool> toggleTask(Task task) async {
    // 1. Update lokal (optimistic)
    final updatedLocal = task.copyWith(
      completed: !task.completed,
      isSynced: false, // akan diset true jika sync ke server sukses
    );

    await _localDb.updateTask(updatedLocal);

    final index = _tasks.indexWhere((t) => t.localId == task.localId);
    if (index != -1) {
      _tasks[index] = updatedLocal;
      notifyListeners();
    }

    // 2. Coba update ke server jika ada serverId
    if (task.serverId == null) {
      // Belum pernah tersinkron, cukup lokal saja
      return true;
    }

    try {
      final success = await _apiService.updateTask(
        updatedLocal.copyWith(
          // Pastikan id yang dikirim adalah serverId
          serverId: task.serverId,
        ),
      );

      if (success) {
        final syncedTask = updatedLocal.copyWith(isSynced: true);

        await _localDb.updateTask(syncedTask);

        final idx = _tasks.indexWhere((t) => t.localId == syncedTask.localId);
        if (idx != -1) {
          _tasks[idx] = syncedTask;
          notifyListeners();
        }

        return true;
      } else {
        _errorMessage = 'Gagal mengupdate task di server.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Mode offline: perubahan hanya tersimpan lokal.';
      notifyListeners();
      return true;
    }
  }

  /// Delete task:
  /// - Hapus dari SQLite
  /// - Jika punya serverId dan online, hapus juga di server
  Future<bool> deleteTask(Task task) async {
    if (task.localId == null) return false;

    // 1. Hapus di lokal terlebih dahulu
    await _localDb.deleteTask(task.localId!);
    _tasks.removeWhere((t) => t.localId == task.localId);
    notifyListeners();

    // 2. Jika tidak punya serverId, selesai di sini
    if (task.serverId == null) {
      return true;
    }

    // 3. Hapus di server
    try {
      final success = await _apiService.deleteTask(task.serverId!);
      if (!success) {
        _errorMessage = 'Gagal menghapus task di server.';
        notifyListeners();
      }
      return success;
    } catch (e) {
      _errorMessage = 'Mode offline: task hanya terhapus di lokal.';
      notifyListeners();
      return true;
    }
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
