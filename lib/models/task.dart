class Task {
  final int? localId;
  final String title;
  final String description;
  final bool completed;
  final String userId;
  final DateTime? createdAt;
  final int? serverId;
  final bool isSynced;

  Task({
    this.localId,
    this.serverId,
    required this.title,
    this.description = '',
    this.completed = false,
    required this.userId,
    this.createdAt,
    this.isSynced = false,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'title': title,
      'description': description,
      'completed': completed,
      'user_id': userId,
      'created_at': createdAt?.toIso8601String(),
    };

    // Hanya include 'id' untuk update operation (bukan create)
    if (serverId != null) {
      json['id'] = serverId;
    }

    return json;
  }

  /// Digunakan ketika menerima response JSON dari Supabase [file:11].
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      // di P9: id: json['id']
      serverId: json['id'] as int?,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      completed: (json['completed'] ?? false) as bool,
      userId: json['user_id'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,

      // Data dari server dianggap sudah tersinkron.
      isSynced: true,
    );
  }

  // ===================================================================
  // Bagian 2: Konversi untuk SQLite (local DB)
  // ===================================================================

  /// Konversi Task ke Map untuk disimpan ke tabel SQLite.
  /// Nama kolom bisa disesuaikan dengan skema tabel lokal.
  Map<String, dynamic> toMap() {
    return {
      'local_id': localId,
      'server_id': serverId,
      'title': title,
      'description': description,
      'completed': completed ? 1 : 0,
      'user_id': userId,
      'created_at': createdAt?.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  /// Membuat Task dari hasil query SQLite (Map).
  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      localId: map['local_id'] as int?,
      serverId: map['server_id'] as int?,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      completed: (map['completed'] ?? 0) == 1,
      userId: map['user_id'] ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      isSynced: (map['is_synced'] ?? 0) == 1,
    );
  }

  // ===================================================================
  // Bagian 3: Helper untuk copyWith (memudahkan update sebagian field)
  // ===================================================================

  Task copyWith({
    int? localId,
    int? serverId,
    String? title,
    String? description,
    bool? completed,
    String? userId,
    DateTime? createdAt,
    bool? isSynced,
  }) {
    return Task(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      title: title ?? this.title,
      description: description ?? this.description,
      completed: completed ?? this.completed,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}
