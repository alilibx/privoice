import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_ai/privoice_ai.dart';
import 'package:privoice_core/privoice_core.dart';

import 'ai_model_paths.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await SqfliteMeetingRepository.open();
  await _maybeAiSelfTest();
  runApp(PrivoiceApp(repository: repository));
}

/// Sentinel-gated on-device LLM proof: with a `.ai_selftest` file present and
/// the GGUF model in place, summarize a canned transcript and log timing +
/// output (read via logcat). No sentinel → normal app.
Future<void> _maybeAiSelfTest() async {
  try {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return;
    if (!File(p.join(ext.path, '.ai_selftest')).existsSync()) return;
    final model = await AiModelLocator.llama();
    if (model == null) {
      // ignore: avoid_print
      print('AI_SELFTEST model missing');
      return;
    }
    const transcript =
        'Alice: Let us ship the beta on Friday. Bob: I will finish the login '
        'screen by Thursday. Alice: Carol, can you write the release notes? '
        'Carol: Yes, I will have them ready Friday morning. Bob: We also '
        'decided to postpone the analytics feature to next sprint.';
    final engine = OnDeviceAiEngine(model);
    final sw = Stopwatch()..start();
    final minutes = await engine.summarize(transcript);
    sw.stop();
    // ignore: avoid_print
    print('AI_SELFTEST ms=${sw.elapsedMilliseconds} chars=${minutes.length}');
    // ignore: avoid_print
    print('AI_SELFTEST_OUT ${minutes.replaceAll('\n', ' | ')}');
    await engine.dispose();
  } catch (e) {
    // ignore: avoid_print
    print('AI_SELFTEST error=$e');
  }
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
