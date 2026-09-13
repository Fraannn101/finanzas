import 'package:flutter/material.dart';

class FinanzasApp extends StatelessWidget {
  const FinanzasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finanzas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF12A150)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12A150),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _Placeholder(),
    );
  }
}

/// Marcador de posición hasta la tarea 23, que trae la pantalla real.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Finanzas')),
      );
}
