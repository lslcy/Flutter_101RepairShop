import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_card.dart';
import 'package:flutter_101repairshop/core/widgets/shimmer_loading.dart';

void main() {
  testWidgets('button remains labeled while saving and blocks duplicate taps', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AppButton(
            label: 'Save changes',
            loadingLabel: 'Saving changes...',
            isLoading: true,
            onPressed: () => presses++,
          ),
        ),
      ),
    );
    expect(find.text('Saving changes...'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    final size = tester.getSize(find.byType(ElevatedButton));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(presses, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('small interactive cards retain a comfortable target', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: AppCard(
              padding: EdgeInsets.zero,
              onTap: () => presses++,
              child: const Icon(Icons.add_outlined, size: 16),
            ),
          ),
        ),
      ),
    );
    final target = find.byType(InkWell);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
    await tester.tap(target);
    expect(presses, 1);
  });

  testWidgets(
    'loading stays still for reduced motion and explains a longer wait',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ShimmerListLoading(
                  label: 'Loading repairs...',
                  itemCount: 2,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Loading repairs...'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(
        find.text('Still loading. This is taking longer than usual.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('light and dark typography share one family and readable contrast', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Roboto');
      expect(theme.textTheme.titleLarge!.fontFamily, 'Roboto');
      expect(theme.textTheme.bodyMedium!.fontSize, 16);
      final colors = theme.colorScheme;
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
      }

      expect(
        contrast(colors.onSurface, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onSurfaceVariant, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.onPrimary, colors.primary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
