import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:privoice_ai/privoice_ai.dart';
import 'package:privoice_core/privoice_core.dart';

import 'ai_model_paths.dart';
import 'ai_service.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await SqfliteMeetingRepository.open();
  await _maybeSeed(repository);
  await _maybeAiSelfTest();
  runApp(PrivoiceApp(repository: repository, ai: AiService()));
}

/// Debug-only: with a `.seed` sentinel present and no meetings yet, insert one
/// sample meeting so screens can be demoed without a mic. Never runs on a real
/// user's device (no sentinel there).
Future<void> _maybeSeed(MeetingRepository repo) async {
  try {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return;
    if (!File(p.join(ext.path, '.seed')).existsSync()) return;
    if ((await repo.all()).isNotEmpty) return;
    await repo.insert(Meeting(
      title: 'Product sync',
      createdAt: DateTime.now(),
      audioPath: '',
      durationMs: 132000,
      transcript:
          'Alice: Let us ship the beta on Friday. Bob: I will finish the login '
          'screen by Thursday. Alice: Carol, can you write the release notes? '
          'Carol: Yes, I will have them ready Friday morning. Bob: We also '
          'decided to postpone the analytics feature to next sprint.',
      minutes: '### Summary\n'
          'The team aligned on shipping the beta this Friday and assigned the '
          'remaining work.\n\n'
          '### Key points\n'
          '- Alice proposed shipping the beta on Friday.\n'
          '- Bob will finish the login screen by Thursday.\n'
          '- Carol will prepare the release notes.\n\n'
          '### Decisions\n'
          '- **Beta ships Friday.**\n'
          '- Analytics feature postponed to next sprint.\n\n'
          '### Action items\n'
          '- Bob: finish the login screen by Thursday\n'
          '- Carol: write release notes by Friday morning',
      actionItems: const [
        'Bob: finish the login screen by Thursday',
        'Carol: write release notes by Friday morning',
        'Ship the beta on Friday',
      ],
      status: MeetingStatus.done,
    ));
  } catch (_) {}
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
  const PrivoiceApp({super.key, required this.repository, required this.ai});

  final MeetingRepository repository;
  final AiService ai;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Privoice',
      debugShowCheckedModeBanner: false,
      theme: PrivoiceTheme.light(),
      darkTheme: PrivoiceTheme.dark(),
      home: HomeScreen(repository: repository, ai: ai),
    );
  }
}
