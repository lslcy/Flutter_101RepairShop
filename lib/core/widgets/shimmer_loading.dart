import 'dart:async';

import 'package:flutter/material.dart';

/// Content-shaped placeholders with honest status and reduced-motion support.
class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({super.key, this.label = 'Loading details...'});
  final String label;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: _LoadingPlaceholder(
          label: label,
          itemCount: 3,
          showHeading: true,
        ),
      ),
    ),
  );
}

class ShimmerListLoading extends StatelessWidget {
  const ShimmerListLoading({
    super.key,
    this.itemCount = 3,
    this.label = 'Loading items...',
  });
  final int itemCount;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: _LoadingPlaceholder(
      label: label,
      itemCount: itemCount,
      showHeading: false,
    ),
  );
}

class _LoadingPlaceholder extends StatefulWidget {
  const _LoadingPlaceholder({
    required this.label,
    required this.itemCount,
    required this.showHeading,
  });
  final String label;
  final int itemCount;
  final bool showHeading;

  @override
  State<_LoadingPlaceholder> createState() => _LoadingPlaceholderState();
}

class _LoadingPlaceholderState extends State<_LoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _animation.stop();
    } else if (!_animation.isAnimating) {
      _animation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            _slow
                ? 'Still loading. This is taking longer than usual.'
                : widget.label,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, _) {
              final color = Color.lerp(
                colors.surfaceContainerHighest,
                colors.surfaceContainerLow,
                _animation.value,
              )!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showHeading) ...[
                    FractionallySizedBox(
                      widthFactor: 0.55,
                      child: _box(color, 24),
                    ),
                    const SizedBox(height: 24),
                  ],
                  for (var index = 0; index < widget.itemCount; index++) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: 40, child: _box(color, 40)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _box(color, 14),
                                const SizedBox(height: 10),
                                FractionallySizedBox(
                                  widthFactor: 0.65,
                                  child: _box(color, 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < widget.itemCount - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _box(Color color, double height) => Container(
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
