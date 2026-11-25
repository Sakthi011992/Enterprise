import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/token_ext.dart';

/// A grey block that pulses in opacity. No shimmer.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 16});

  final double? width;
  final double height;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(begin: 0.45, end: 1.0).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ext = context.ext;
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: ext.neutralSubtle,
          borderRadius: BorderRadius.circular(t.radius.sm),
        ),
      ),
    );
  }
}

/// Stacked rows of [SkeletonBox] for a table or list that is loading.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 6});

  final int rows;

  static const _widths = <double>[280, 200, 240, 160];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
            child: SkeletonBox(width: _widths[i % _widths.length]),
          ),
      ],
    );
  }
}

/// Shows [child] only after 300 ms, so fast loads never flash a skeleton.
class DelayedSkeleton extends StatefulWidget {
  const DelayedSkeleton({super.key, required this.child});

  final Widget child;

  @override
  State<DelayedSkeleton> createState() => _DelayedSkeletonState();
}

class _DelayedSkeletonState extends State<DelayedSkeleton> {
  static const _delay = Duration(milliseconds: 300);

  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible ? widget.child : const SizedBox.shrink();
}
