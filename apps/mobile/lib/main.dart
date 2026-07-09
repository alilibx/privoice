import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await SqfliteMeetingRepository.open();
  runApp(PrivoiceApp(repository: repository));
}

class PrivoiceApp extends StatelessWidget {
  const PrivoiceApp({super.key, required this.repository});

  final MeetingRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Privoice',
      debugShowCheckedModeBanner: false,
      theme: PrivoiceTheme.light(),
      darkTheme: PrivoiceTheme.dark(),
      home: HomeScreen(repository: repository),
    );
  }
}
