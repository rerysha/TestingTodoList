import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/task_api.dart';
import 'local/task_local_db.dart';
import 'providers/task_provider.dart';
import 'screens/login_screen.dart';
import 'screens/task_list_screen.dart';

void main() {
  // Initialize services
  final apiService = TaskApiService();
  final localDb = TaskLocalDb();

  runApp(
    ChangeNotifierProvider(
      create: (context) {
        final taskProvider = TaskProvider(apiService, localDb);
        taskProvider.checkSession(); // Check saved session + load offline data
        return taskProvider;
      },
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline-First Tasks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Selector<TaskProvider, bool>(
        selector: (context, provider) => provider.isAuthLoading,
        builder: (context, isAuthLoading, child) {
          return Consumer<TaskProvider>(
            builder: (context, taskProvider, child) {
              if (isAuthLoading) {
                return Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              return taskProvider.isAuthenticated
                  ? TaskListScreen()
                  : LoginScreen();
            },
          );
        },
      ),
    );
  }
}
