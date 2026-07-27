import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:privoice_ai/privoice_ai.dart';
import 'package:privoice_core/privoice_core.dart';

import 'ai_model_paths.dart';
import 'ai_service.dart';
import 'dev_sentinels.dart';
import 'screens/app_bootstrap.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only a running/progress notification (the foreground-service notification).
  // No per-file `complete`/`error` pop: with a multi-file model set the plugin
  // fires those per download task, which falsely announced "Models ready" when
  // just the first file finished. The in-app Home banner is the source of
  // truth for overall readiness and errors.
  FileDownloader().configureNotification(
    running: const TaskNotification('Downloading models', '{progress}'),
    progressBar: true,
  );
  await FileDownloader().configure(
    androidConfig: [(Config.runInForeground, true)],
  );
  // start() persists task state to the plugin DB (doTrackTasks defaults to
  // true) and reschedules any tasks the OS killed, resuming delivery of
  // their background updates — this is what lets an interrupted model
  // download recover after process death instead of restarting from zero.
  await FileDownloader().start(doRescheduleKilledTasks: true);
  final repository = await SqfliteMeetingRepository.open();
  final themeMode = ValueNotifier<ThemeMode>(await SettingsService.themeMode());
  await _maybeSeed(repository);
  await _maybeAiSelfTest();
  runApp(PrivoiceApp(repository: repository, ai: AiService(), themeMode: themeMode));
}

/// Debug-only: with a `.seed` sentinel present and no meetings yet, insert one
/// sample meeting so screens can be demoed without a mic. Never runs on a real
/// user's device (no sentinel there).
Future<void> _maybeSeed(MeetingRepository repo) async {
  try {
    final ext = await devSentinelDir();
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
        ActionItem(text: 'Bob: finish the login screen by Thursday'),
        ActionItem(text: 'Carol: write release notes by Friday morning'),
        ActionItem(text: 'Ship the beta on Friday'),
      ],
      status: MeetingStatus.done,
    ));
  } catch (_) {}
}

/// Sentinel-gated on-device LLM proof: with a `.ai_selftest` file present and
/// the GGUF model in place, summarize a canned transcript and record timing +
/// output. No sentinel → normal app.
///
/// Results go to BOTH stdout and `ai_selftest_result.txt` beside the sentinel.
/// The file matters on iOS: `print` in a release build goes to os_log, which
/// modern macOS cannot stream from a connected device (`log stream` dropped
/// `--device`) and which `devicectl ... --console` does not capture either.
/// A file can be pulled off the device with:
///
/// ```
///   xcrun devicectl device copy from --device DEVICE_ID \
///     --domain-type appDataContainer --domain-identifier BUNDLE_ID \
///     --source Documents/ai_selftest_result.txt --destination ./result.txt
/// ```
///
/// It also reports load time separately from generation time, because the two
/// have completely different causes when this is slow.
Future<void> _maybeAiSelfTest() async {
  File? out;
  try {
    final ext = await devSentinelDir();
    if (ext == null) return;
    if (!File(p.join(ext.path, '.ai_selftest')).existsSync()) return;
    out = File(p.join(ext.path, 'ai_selftest_result.txt'));
    final model = await AiModelLocator.llama();
    if (model == null) {
      _selfTestReport(out, 'AI_SELFTEST model missing');
      return;
    }
    const transcript =
        'Alice: Let us ship the beta on Friday. Bob: I will finish the login '
        'screen by Thursday. Alice: Carol, can you write the release notes? '
        'Carol: Yes, I will have them ready Friday morning. Bob: We also '
        'decided to postpone the analytics feature to next sprint.';
    final engine = OnDeviceAiEngine(model);

    // Warm-up is the model load + backend init; timing it separately is what
    // distinguishes "slow to start" from "slow to generate".
    final loadSw = Stopwatch()..start();
    await engine.warmUp();
    loadSw.stop();

    final genSw = Stopwatch()..start();
    final minutes = await engine.summarize(transcript);
    genSw.stop();

    _selfTestReport(
      out,
      'AI_SELFTEST model=${p.basename(model)} '
      'loadMs=${loadSw.elapsedMilliseconds} '
      'genMs=${genSw.elapsedMilliseconds} '
      'chars=${minutes.length}\n'
      'AI_SELFTEST_OUT ${minutes.replaceAll('\n', ' | ')}',
    );
    await engine.dispose();
  } catch (e) {
    _selfTestReport(out, 'AI_SELFTEST error=$e');
  }
}

void _selfTestReport(File? out, String line) {
  // ignore: avoid_print
  print(line);
  try {
    out?.writeAsStringSync('$line\n', flush: true);
  } catch (_) {
    // Best effort: stdout already carries it where logs are readable.
  }
}

class PrivoiceApp extends StatelessWidget {
  const PrivoiceApp({
    super.key,
    required this.repository,
    required this.ai,
    required this.themeMode,
  });

  final MeetingRepository repository;
  final AiService ai;
  final ValueNotifier<ThemeMode> themeMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Privoice',
        debugShowCheckedModeBanner: false,
        theme: PrivoiceTheme.light(),
        darkTheme: PrivoiceTheme.dark(),
        themeMode: mode,
        home: AppBootstrap(
          repository: repository,
          ai: ai,
          themeMode: themeMode,
        ),
      ),
    );
  }
}
