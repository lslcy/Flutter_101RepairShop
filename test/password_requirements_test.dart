import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/password_requirements.dart';

void main() {
  const labels = <String, String>{
    'length': 'At least 8 characters',
    'special': 'At least 1 special character',
    'uppercase': 'At least 1 uppercase letter',
    'number': 'At least 1 number',
  };

  Finder requirement(String rule) =>
      find.byKey(ValueKey('password_requirement_$rule'));

  Future<void> pumpRequirements(
    WidgetTester tester, {
    required String password,
    bool showErrors = false,
    bool isEditing = false,
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: PasswordRequirements(
              password: password,
              showErrors: showErrors,
              isEditing: isEditing,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectStatus(
    WidgetTester tester,
    String rule, {
    required String status,
    required IconData icon,
  }) {
    final row = requirement(rule);
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(icon)),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(row),
      matchesSemantics(
        label: 'Password requirement$status: ${labels[rule]}',
        isLiveRegion: true,
      ),
    );
  }

  testWidgets('empty passwords hide guidance before interaction', (
    tester,
  ) async {
    await pumpRequirements(tester, password: '');
    for (final rule in labels.keys) {
      expect(requirement(rule), findsNothing);
    }
  });

  testWidgets('focusing an empty password offers neutral guidance', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRequirements(tester, password: '', isEditing: true);
    for (final rule in labels.keys) {
      expectStatus(tester, rule, status: '', icon: Icons.info_outline);
    }
    handle.dispose();
  });

  testWidgets(
    'each requirement updates independently as the password changes',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRequirements(tester, password: 'seven!');
      expectStatus(
        tester,
        'special',
        status: ' met',
        icon: Icons.check_circle_outline,
      );
      for (final rule in ['length', 'uppercase', 'number']) {
        expectStatus(
          tester,
          rule,
          status: ' not met',
          icon: Icons.cancel_outlined,
        );
      }

      await pumpRequirements(tester, password: 'Password1');
      for (final rule in ['length', 'uppercase', 'number']) {
        expectStatus(
          tester,
          rule,
          status: ' met',
          icon: Icons.check_circle_outline,
        );
      }
      expectStatus(
        tester,
        'special',
        status: ' not met',
        icon: Icons.cancel_outlined,
      );

      await pumpRequirements(tester, password: 'Password1!');
      for (final rule in labels.keys) {
        expect(requirement(rule), findsNothing);
      }

      await pumpRequirements(tester, password: 'Password1');
      expectStatus(
        tester,
        'special',
        status: ' not met',
        icon: Icons.cancel_outlined,
      );

      await pumpRequirements(tester, password: '', isEditing: true);
      for (final rule in labels.keys) {
        expectStatus(tester, rule, status: '', icon: Icons.info_outline);
      }

      await pumpRequirements(tester, password: '');
      for (final rule in labels.keys) {
        expect(requirement(rule), findsNothing);
      }
      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );

  testWidgets('submitting an empty password exposes unmet requirements', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRequirements(tester, password: '', showErrors: true);
    for (final rule in labels.keys) {
      expectStatus(
        tester,
        rule,
        status: ' not met',
        icon: Icons.cancel_outlined,
      );
    }
    handle.dispose();
  });

  testWidgets(
    'valid passwords hide guidance despite focus or submitted errors',
    (tester) async {
      for (final isEditing in [false, true]) {
        for (final showErrors in [false, true]) {
          await pumpRequirements(
            tester,
            password: 'Password1!',
            isEditing: isEditing,
            showErrors: showErrors,
          );
          for (final rule in labels.keys) {
            expect(requirement(rule), findsNothing);
          }
        }
      }
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'checklist wraps and scrolls at 320px and 200% text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: PasswordRequirements(password: 'Password1'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in labels.values) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.text(label));
          expect(rect.right, lessThanOrEqualTo(296));
          expect(rect.left, greaterThanOrEqualTo(24));
          expect(rect.bottom, lessThan(568));
        }
        expect(
          tester.getSize(find.text(labels['special']!)).height,
          greaterThan(28),
        );
      },
    );

    testWidgets(
      'status colors distinguish met, unmet and neutral requirements in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        Color textColor(String rule) => tester
            .widget<Text>(
              find.descendant(
                of: requirement(rule),
                matching: find.byType(Text),
              ),
            )
            .style!
            .color!;

        await pumpRequirements(
          tester,
          password: '',
          isEditing: true,
          dark: dark,
        );
        final neutral = textColor('special');
        await pumpRequirements(tester, password: 'Password1', dark: dark);
        final unmet = textColor('special');
        final met = textColor('length');
        expect(unmet, isNot(neutral));
        expect(met, isNot(neutral));
        expect(met, isNot(unmet));

        final context = tester.element(find.byType(PasswordRequirements));
        final background = Theme.of(context).scaffoldBackgroundColor;
        double contrast(Color foreground) {
          final first = foreground.computeLuminance();
          final second = background.computeLuminance();
          return first > second
              ? (first + 0.05) / (second + 0.05)
              : (second + 0.05) / (first + 0.05);
        }

        expect(contrast(met), greaterThanOrEqualTo(4.5));
        expect(contrast(unmet), greaterThanOrEqualTo(4.5));
      },
    );
  }
}
