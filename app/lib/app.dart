import 'package:flutter/material.dart';

/// Root widget of the Dockyard client.
///
/// Routing, providers, and the authenticated shell are attached here as the
/// features are implemented.
class DockyardApp extends StatelessWidget {
  const DockyardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dockyard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7490)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('Dockyard')),
      ),
    );
  }
}
