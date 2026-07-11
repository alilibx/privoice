import 'package:flutter/material.dart';

/// First-launch intro: 4 swipeable screens. The final page commits via [onDone]
/// (also reachable via Skip). Uses the app's R1 theme tokens.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_PageData>[
    _PageData(
      icon: Icons.graphic_eq_rounded,
      title: 'Capture every meeting',
      body: 'Record, transcribe, and summarize meetings into clean minutes '
          'and action items — all in one place.',
    ),
    _PageData(
      icon: Icons.lock_outline_rounded,
      title: 'Private by design',
      body: 'Speech-to-text and AI run entirely on your phone. Nothing is '
          'uploaded — your conversations never leave the device.',
    ),
    _PageData(
      icon: Icons.download_for_offline_outlined,
      title: 'Getting you set up',
      body: "We're downloading your on-device models (about 1.5 GB). You can "
          "start exploring now — best on Wi-Fi.",
    ),
    _PageData(
      icon: Icons.notifications_active_outlined,
      title: 'Keep you posted',
      body: 'We’ll show a progress notification while your models download, so '
          'you can use other apps and it keeps going in the background. '
          'You can allow notifications on the next screen.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
    } else {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _Page(data: _pages[i]),
              ),
            ),
            _Dots(count: _pages.length, index: _page, color: scheme.primary),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? 'Start' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  const _PageData({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

class _Page extends StatelessWidget {
  const _Page({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, size: 84, color: scheme.primary),
          const SizedBox(height: 32),
          Text(data.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(data.body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.color});
  final int count;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? color : color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
