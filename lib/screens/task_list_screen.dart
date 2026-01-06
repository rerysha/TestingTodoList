import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../providers/task_provider.dart';
import 'add_task_screen.dart';

class TaskListScreen extends StatefulWidget {
  @override
  _TaskListScreenState createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasLoaded) {
        _hasLoaded = true;
        context.read<TaskProvider>().loadTasksOfflineFirst();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final taskProvider = context.watch<TaskProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Tasks (${taskProvider.tasks.length})'),
            const SizedBox(height: 2),
            _buildSyncSubtitle(taskProvider),
          ],
        ),
        actions: [
          // Ikon status sync sederhana
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: taskProvider.isSyncing
                  ? const Icon(Icons.sync, color: Colors.yellowAccent)
                  : (taskProvider.unsyncedCount > 0
                        ? const Icon(
                            Icons.cloud_off,
                            color: Colors.orangeAccent,
                          )
                        : const Icon(
                            Icons.cloud_done,
                            color: Colors.greenAccent,
                          )),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => taskProvider.loadTasksOfflineFirst(),
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                taskProvider.logout();
              }
            },
          ),
        ],
      ),
      body: _buildBody(taskProvider),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddTaskScreen()),
          );

          if (result == true) {
            taskProvider.loadTasksOfflineFirst();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSyncSubtitle(TaskProvider taskProvider) {
    if (taskProvider.isTaskLoading && taskProvider.tasks.isEmpty) {
      return const Text('Memuat data lokal...', style: TextStyle(fontSize: 12));
    }

    if (taskProvider.isSyncing) {
      return const Text(
        'Sinkronisasi dengan server...',
        style: TextStyle(fontSize: 12),
      );
    }

    if (taskProvider.unsyncedCount > 0) {
      return Text(
        '${taskProvider.unsyncedCount} task belum tersinkron',
        style: const TextStyle(fontSize: 12),
      );
    }

    return const Text('Semua data tersinkron', style: TextStyle(fontSize: 12));
  }

  Widget _buildBody(TaskProvider taskProvider) {
    if (taskProvider.isTaskLoading && taskProvider.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (taskProvider.errorMessage != null && taskProvider.tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(taskProvider.errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => taskProvider.loadTasksOfflineFirst(),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    if (taskProvider.tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.task_alt, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Belum ada tasks', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('Tap + untuk menambah task pertama'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => taskProvider.loadTasksOfflineFirst(),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: taskProvider.tasks.length,
        itemBuilder: (context, index) {
          final task = taskProvider.tasks[index];
          return TaskCard(task: task);
        },
      ),
    );
  }
}

class TaskCard extends StatelessWidget {
  final Task task;

  const TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final isUnsynced = !task.isSynced;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Checkbox(
              value: task.completed,
              onChanged: (value) async {
                final success = await context.read<TaskProvider>().toggleTask(
                  task,
                );

                if (!success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gagal update task'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
            if (isUnsynced)
              const Positioned(
                right: 0,
                bottom: 0,
                child: Icon(
                  Icons.offline_bolt,
                  size: 14,
                  color: Colors.orangeAccent,
                ),
              ),
          ],
        ),
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.completed ? TextDecoration.lineThrough : null,
            color: task.completed ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description.isNotEmpty)
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (isUnsynced)
              const Text(
                'Belum terkirim ke server',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
          ],
        ),
        trailing: task.completed
            ? const Icon(Icons.check_circle, color: Colors.green)
            : PopupMenuButton(
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Hapus'),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Hapus Task'),
                        content: const Text('Yakin ingin menghapus task ini?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Batal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Hapus'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true && context.mounted) {
                      final success = await context
                          .read<TaskProvider>()
                          .deleteTask(task);

                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Task dihapus')),
                        );
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Gagal menghapus task'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
      ),
    );
  }
}
