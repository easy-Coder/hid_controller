import 'package:flutter/material.dart';

import 'controller/controller_store.dart';
import 'ui/dashboard.dart';

void main() => runApp(const ControllerLabApp());

class ControllerLabApp extends StatefulWidget {
  const ControllerLabApp({super.key});
  @override
  State<ControllerLabApp> createState() => _ControllerLabAppState();
}

class _ControllerLabAppState extends State<ControllerLabApp> {
  final store = ControllerStore();
  @override
  void initState() {
    super.initState();
    store.initialize();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Controller Lab',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101217),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFC4F277),
        brightness: Brightness.dark,
        primary: const Color(0xFFC4F277),
        surface: const Color(0xFF191C23),
      ),
      fontFamily: 'Helvetica Neue',
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    ),
    home: Dashboard(store: store),
  );
}
