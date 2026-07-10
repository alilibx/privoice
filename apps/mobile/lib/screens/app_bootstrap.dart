import 'package:flutter/material.dart';
import 'package:privoice_core/privoice_core.dart';

import '../ai_service.dart';
import '../model_manager.dart';
import '../settings.dart';
import 'home_screen.dart';
import 'onboarding_flow.dart';

/// First-launch router: onboarding until complete, then the app. Kicks off the
/// background model download (resumes any partial install on later launches).
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    required this.repository,
    required this.ai,
    required this.themeMode,
    this.modelManager,
  });

  final MeetingRepository repository;
  final AiService ai;
  final ValueNotifier<ThemeMode> themeMode;
  final ModelManager? modelManager;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool? _onboarded;

  ModelManager get _manager => widget.modelManager ?? ModelManager.instance;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final done = await SettingsService.onboardingComplete();
    if (done) _manager.ensureDefaultSet(); // fire-and-forget resume
    if (mounted) setState(() => _onboarded = done);
  }

  Future<void> _finishOnboarding() async {
    await SettingsService.setOnboardingComplete(true);
    _manager.ensureDefaultSet(); // fire-and-forget start
    if (mounted) setState(() => _onboarded = true);
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = _onboarded;
    if (onboarded == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!onboarded) {
      return OnboardingFlow(onDone: _finishOnboarding);
    }
    return HomeScreen(
      repository: widget.repository,
      ai: widget.ai,
      themeMode: widget.themeMode,
      modelManager: _manager,
    );
  }
}
