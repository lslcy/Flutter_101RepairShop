import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_101repairshop/core/validation/customer_identity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_101repairshop/core/theme/app_theme.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/core/widgets/address_input.dart';
import 'package:flutter_101repairshop/features/profile/data/customer_repository.dart';
import 'package:flutter_101repairshop/features/profile/presentation/edit_profile_screen.dart';
import 'package:flutter_101repairshop/features/profile/presentation/profile_screen.dart';
import 'package:flutter_101repairshop/features/shared/models/customer.dart';

const _originalAddress =
    'Unit 1204, Building Three, 123 Mabini Street, Barangay San Antonio, '
    'Buhangin District, Davao City, Davao del Sur, Philippines 8000';
const _updatedAddress =
    'Unit 8, 45 Jacinto Street, Barangay San Pedro, Tagum City, Davao del Norte, 8100';

class _Customers extends CustomerRepository {
  Customer current = Customer(
    id: 'customer-id',
    authId: 'auth-id',
    firstName: 'Alex',
    lastName: 'Reyes',
    email: 'alex.reyes@example.com',
    phoneNo: '09171234567',
    address: _originalAddress,
    profilePicture: 'https://example.com/avatars/customer.png',
    createdAt: DateTime.utc(2024, 1, 2),
    updatedAt: DateTime.utc(2025, 3, 4),
  );
  final saved = <Customer>[];
  Object? saveError;

  @override
  Future<Customer?> getCurrentCustomer() async {
    return current;
  }

  @override
  Future<void> updateProfile(Customer customer) async {
    if (saveError != null) throw saveError!;
    saved.add(customer);
    current = customer;
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

  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  Finder addressField() => find.descendant(
    of: find.widgetWithText(AppTextField, 'Street / subdivision'),
    matching: find.byType(TextFormField),
  );

  Future<void> pumpProfile(
    WidgetTester tester,
    _Customers customers, {
    Size size = const Size(380, 800),
    double textScale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (context, state) => const EditProfileScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(customers)],
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark ? AppTheme.dark : AppTheme.light,
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

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Saving separate address fields preserves customer data and refreshes the profile',
    (tester) async {
      final customers = _Customers();
      final original = customers.current;
      await pumpProfile(tester, customers);
      expect(find.text(_originalAddress), findsOneWidget);
      await tapVisible(tester, find.text('Edit address'));

      for (final entry in {
        'House / unit no. (optional)': 'Unit 8',
        'Street / subdivision': '45 Jacinto Street',
        'Barangay': 'Barangay San Pedro',
        'City / municipality (required)': 'Tagum City',
        'Province (required)': 'Davao del Norte',
        'Postal code (optional)': '8100',
      }.entries) {
        final target = find.descendant(
          of: find.widgetWithText(AppTextField, entry.key),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(target);
        await tester.enterText(target, entry.value);
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, find.text('Save changes'));

      expect(customers.saved, hasLength(1));
      final saved = customers.saved.single;
      for (final part in _updatedAddress.split(', ')) {
        expect(saved.address, contains(part));
      }
      expect(saved.id, original.id);
      expect(saved.authId, original.authId);
      expect(saved.profilePicture, original.profilePicture);
      expect(saved.createdAt, original.createdAt);
      expect(saved.updatedAt, original.updatedAt);
      expect(saved.firstName, original.firstName);
      expect(saved.lastName, original.lastName);
      expect(saved.email, original.email);
      expect(
        saved.phoneNo,
        CustomerIdentity.normalizeOptionalPhone(original.phoneNo),
      );
      expect(find.byType(EditProfileScreen), findsNothing);
      expect(find.text(saved.address!), findsOneWidget);
      expect(find.text(_originalAddress), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Clearing the required address shows validation and preserves saved data',
    (tester) async {
      final customers = _Customers();
      await pumpProfile(tester, customers);
      await tapVisible(tester, find.text('Edit address'));
      await tester.ensureVisible(addressField());
      await tester.enterText(addressField(), '  ');
      final barangay = find.descendant(
        of: find.widgetWithText(AppTextField, 'Barangay'),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(barangay);
      await tester.enterText(barangay, '  ');
      await tapVisible(tester, find.text('Save changes'));

      expect(customers.saved, isEmpty);
      expect(customers.current.address, _originalAddress);
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.text('Enter a street or barangay.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Profile and address editor fit 320px with large text in dark mode',
    (tester) async {
      await pumpProfile(
        tester,
        _Customers(),
        size: const Size(320, 720),
        textScale: 1.5,
        dark: true,
      );
      await tester.ensureVisible(find.text(_originalAddress));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text('Edit address'));

      expect(find.text('Personal information'), findsOneWidget);
      await tester.ensureVisible(addressField());
      await tester.pumpAndSettle();
      expect(
        tester.widget<AddressInput>(find.byType(AddressInput)).controller.text,
        _originalAddress,
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Profile validation follows visible field order', (tester) async {
    final customers = _Customers();
    await pumpProfile(tester, customers, size: const Size(320, 720));
    await tapVisible(tester, find.text('Edit address'));
    final firstName = find.descendant(
      of: find.widgetWithText(AppTextField, 'First name'),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(firstName);
    await tester.enterText(firstName, ' ');
    await tester.ensureVisible(addressField());
    await tester.enterText(addressField(), ' ');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save changes'));
    final input = tester.widget<EditableText>(
      find.descendant(of: firstName, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
    expect(find.text('Enter your first name').hitTestable(), findsOneWidget);
    expect(customers.saved, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('profile editor rejects invalid contacts and focuses them', (
    tester,
  ) async {
    final customers = _Customers();
    await pumpProfile(tester, customers);
    await tapVisible(tester, find.text('Edit address'));
    Finder input(String label) => find.descendant(
      of: find.widgetWithText(AppTextField, label),
      matching: find.byType(TextFormField),
    );
    final email = input('Contact email');
    await tester.ensureVisible(email);
    await tester.enterText(email, 'invalid@example..com');
    await tapVisible(tester, find.text('Save changes'));
    expect(customers.saved, isEmpty);
    expect(
      find.text('Enter a valid email address').hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: email, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );

    await tester.enterText(email, 'alex@example.com');
    final phone = input('Phone number (optional)');
    await tester.ensureVisible(phone);
    await tester.enterText(phone, '12345');
    await tapVisible(tester, find.text('Save changes'));
    expect(customers.saved, isEmpty);
    expect(
      find.text('Enter a valid phone number').hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: phone, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate profile contact keeps the saved identity and shows a useful error',
    (tester) async {
      final customers = _Customers();
      customers.saveError = const PostgrestException(
        message: 'duplicate key value violates unique constraint "customers_phone_no_unique"',
        code: '23505',
      );
      await pumpProfile(tester, customers);
      await tapVisible(tester, find.text('Edit address'));
      await tapVisible(tester, find.text('Save changes'));

      expect(customers.saved, isEmpty);
      expect(find.byType(EditProfileScreen), findsOneWidget);
      expect(find.textContaining('already'), findsOneWidget);
      expect(customers.current.phoneNo, '09171234567');
      expect(tester.takeException(), isNull);
    },
  );
}
