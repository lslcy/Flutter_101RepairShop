import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/profile/presentation/add_appliance_screen.dart';
import 'package:flutter_101repairshop/features/profile/presentation/appliances_screen.dart';
import 'package:flutter_101repairshop/features/shared/models/appliance.dart';

class _Customers extends CustomerRepository {
  List<Appliance> appliances = [];
  final submissions = <Map<String, dynamic>>[];
  bool failLoad = false;
  bool failSave = false;
  int loads = 0;
  Completer<void>? saving;

  @override
  Future<List<Appliance>> getAppliances() async {
    loads++;
    if (failLoad) throw StateError('offline');
    return appliances;
  }

  @override
  Future<void> addAppliance(Map<String, dynamic> data) async {
    submissions.add(Map<String, dynamic>.from(data));
    await saving?.future;
    if (failSave) throw StateError('offline');
    appliances = [
      Appliance(
        id: 1,
        customerId: 'customer',
        brand: data['brand'] as String,
        product: data['product'] as String,
        modelNo: data['model_no'] as String?,
        category: data['category'] as String?,
        applianceSize: data['appliance_size'] as String?,
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'test-key',
      debug: false,
    );
  });

  tearDownAll(() async => Supabase.instance.dispose());

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );

  Future<void> pumpAppliances(
    WidgetTester tester,
    _Customers customers, {
    Size size = const Size(380, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/profile/appliances',
      routes: [
        GoRoute(
          path: '/profile/appliances',
          builder: (_, _) => const AppliancesScreen(),
        ),
        GoRoute(
          path: '/profile/appliances/add',
          builder: (_, _) => const AddApplianceScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(customers)],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder addButton() => find.widgetWithText(AppButton, 'Add appliance');

  testWidgets(
    'Appliance validation rejects whitespace and focuses the first required field',
    (tester) async {
      final customers = _Customers();
      await pumpAppliances(tester, customers);
      await tapVisible(tester, addButton());
      await tester.enterText(field('Brand (required)'), '   ');
      await tapVisible(tester, addButton());

      expect(customers.submissions, isEmpty);
      expect(find.text('Enter the appliance brand.'), findsOneWidget);
      expect(find.text('Enter the type of product.'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('Brand (required)'),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.enterText(field('Brand (required)'), 'Samsung');
      await tapVisible(tester, addButton());
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('Product (required)'),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(customers.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed appliance save retains the draft and retry prevents duplicate submission',
    (tester) async {
      final customers = _Customers()..failSave = true;
      await pumpAppliances(tester, customers);
      await tapVisible(tester, addButton());
      await tester.enterText(field('Brand (required)'), '  Samsung  ');
      await tester.enterText(field('Product (required)'), '  Refrigerator  ');
      await tapVisible(tester, addButton());

      expect(
        find.text(
          'Could not add your appliance. Your details are still here. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('Brand (required)'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '  Samsung  ',
      );
      expect(customers.submissions, hasLength(1));

      final pending = Completer<void>();
      customers
        ..failSave = false
        ..saving = pending;
      await tester.ensureVisible(addButton());
      await tester.tap(addButton());
      await tester.pump();
      expect(find.text('Adding appliance...'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(customers.submissions, hasLength(2));
      expect(customers.submissions.last['brand'], 'Samsung');
      expect(customers.submissions.last['product'], 'Refrigerator');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(customers.submissions, hasLength(2));

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AddApplianceScreen), findsNothing);
      expect(find.text('Samsung Refrigerator'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Appliance errors recover and an empty list supports pull-to-refresh',
    (tester) async {
      final customers = _Customers()..failLoad = true;
      await pumpAppliances(tester, customers);
      expect(find.text('Appliances unavailable'), findsOneWidget);
      expect(find.text('No appliances yet'), findsNothing);
      customers.failLoad = false;
      await tapVisible(tester, find.text('Try again'));
      expect(find.text('No appliances yet'), findsOneWidget);

      customers.appliances = [
        Appliance(
          id: 1,
          customerId: 'customer',
          brand: 'LG',
          product: 'Washing machine',
        ),
      ];
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(customers.loads, 3);
      expect(find.text('LG Washing machine'), findsOneWidget);
    },
  );

  testWidgets(
    'Appliance dropdowns and details fit 320px at twice the text size',
    (tester) async {
      final customers = _Customers()
        ..appliances = [
          Appliance(
            id: 1,
            customerId: 'customer',
            brand: 'Samsung',
            product: 'Large washing machine',
            modelNo: 'WW90T554DAN',
            serialNo: '123456789',
            category: 'Washing Machine',
            applianceSize: 'Extra Large',
          ),
        ];
      await pumpAppliances(
        tester,
        customers,
        size: const Size(320, 720),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Samsung Large washing machine'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tapVisible(tester, find.text('Samsung Large washing machine'));
      await tester.ensureVisible(find.text('Serial number'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byTooltip('Close appliance details'));
      await tapVisible(tester, addButton());
      expect(tester.takeException(), isNull);

      final category = find.byType(DropdownButtonFormField<String>).first;
      await tapVisible(tester, category);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Washing Machine').last);
      expect(tester.takeException(), isNull);

      final size = find.byType(DropdownButtonFormField<String>).last;
      await tapVisible(tester, size);
      await tapVisible(tester, find.text('Extra Large').last);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(addButton());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
