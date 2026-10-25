import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/presentation/app_shell.dart';

/// Root widget of the Dockyard client.
///
/// There is no login route: connection details are stored locally and the
/// daemon session is established in the background by the live controller.
class DockyardApp extends StatelessWidget {
  const DockyardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dockyard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}
