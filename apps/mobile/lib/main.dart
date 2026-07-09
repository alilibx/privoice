import 'package:flutter/material.dart';

import 'spike_screen.dart';

void main() => runApp(const PrivoiceApp());

class PrivoiceApp extends StatelessWidget {
  const PrivoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Privoice',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const SpikeScreen(),
    );
  }
}
