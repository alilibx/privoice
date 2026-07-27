import 'package:flutter/material.dart';

/// Staggered fade/slide-in wrapper (no controller — safe under pumpAndSettle).
class AnimatedIn extends StatelessWidget {
  const AnimatedIn({super.key, required this.child, this.delayMs = 0});
  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + delayMs),
      curve: Curves.easeOut,
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: c),
      ),
      child: child,
    );
  }
}
