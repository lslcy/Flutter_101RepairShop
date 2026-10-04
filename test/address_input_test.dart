import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_101repairshop/core/services/address_location_service.dart';
import 'package:flutter_101repairshop/core/widgets/address_input.dart';
import 'package:flutter_101repairshop/core/widgets/app_button.dart';
import 'package:flutter_101repairshop/core/widgets/app_text_field.dart';
import 'package:flutter_101repairshop/features/auth/presentation/register_screen.dart';

const _manualAddress =
    'Unit 8, 45 Jacinto Street\nBarangay San Pedro\nDavao City, 8000';
const _locatedAddress = '123 Mabini Street, Barangay 1, Davao City, 8000';
const _requiredMessage = 'Enter your address or use your current location.';

class _LocationService extends AddressLocationService {
  _LocationService() : super(platformSupported: true);

  int lookupCount = 0;
  int appSettingsCount = 0;
  int locationSettingsCount = 0;
  Future<String> Function()? lookup;

  @override
  Future<String> getCurrentAddress() {
    lookupCount++;
    return lookup?.call() ?? Future.value(_locatedAddress);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCount++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCount++;
    return true;
  }
}

void main() {
  late TextEditingController controller;
  late GlobalKey<FormState> formKey;
  late _LocationService service;

  setUp(() {
    controller = TextEditingController();
    formKey = GlobalKey<FormState>();
    service = _LocationService();
  });

  tearDown(() => controller.dispose());

  Finder addressField() => find.descendant(
    of: find.byType(AddressInput),
    matching: find.byType(TextFormField),
  );

  Future<void> pumpInput(WidgetTester tester, {bool enabled = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [addressLocationServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: AddressInput(controller: controller, enabled: enabled),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('location lookup only starts when explicitly requested', (
    tester,
  ) async {
    controller.text = _manualAddress;
    await pumpInput(tester);

    expect(service.lookupCount, 0);
    expect(controller.text, _manualAddress);
    expect(find.text('Address (required)'), findsOneWidget);
    expect(find.text('Use my location'), findsOneWidget);
    expect(find.text('Use this address'), findsNothing);
  });

  testWidgets('manual multiline address validates and whitespace is rejected', (
    tester,
  ) async {
    await pumpInput(tester);

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(_requiredMessage), findsOneWidget);

    await tester.enterText(addressField(), '  \n  ');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(_requiredMessage), findsOneWidget);

    await tester.enterText(addressField(), _manualAddress);
    expect(formKey.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text(_requiredMessage), findsNothing);
    expect(controller.text, _manualAddress);
    expect(service.lookupCount, 0);
  });

  testWidgets(
    'denying location permission leaves manual address entry usable',
    (tester) async {
      const message =
          'Location permission was not granted. Enter your address manually.';
      service.lookup = () async =>
          throw const AddressLocationException(message);
      await pumpInput(tester);

      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(service.lookupCount, 1);
      expect(find.text(message), findsOneWidget);
      expect(controller.text, isEmpty);

      await tester.enterText(addressField(), _manualAddress);
      expect(formKey.currentState!.validate(), isTrue);
      expect(controller.text, _manualAddress);
      expect(service.lookupCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'located address is reviewed before applying and remains editable',
    (tester) async {
      controller.text = _manualAddress;
      final lookup = Completer<String>();
      service.lookup = () => lookup.future;
      await pumpInput(tester);

      await tapVisible(tester, find.text('Use my location'));
      expect(service.lookupCount, 1);
      expect(controller.text, _manualAddress);

      lookup.complete(_locatedAddress);
      await tester.pumpAndSettle();
      expect(find.text(_locatedAddress), findsOneWidget);
      expect(find.text('Use this address'), findsOneWidget);
      expect(controller.text, _manualAddress);

      await tapVisible(tester, find.text('Use this address'));
      await tester.pumpAndSettle();
      expect(controller.text, _locatedAddress);
      expect(formKey.currentState!.validate(), isTrue);

      const completedAddress = 'Unit 4, $_locatedAddress';
      await tester.enterText(addressField(), completedAddress);
      expect(controller.text, completedAddress);
      expect(formKey.currentState!.validate(), isTrue);
      expect(service.lookupCount, 1);
    },
  );

  testWidgets('typing while lookup runs is never overwritten by its result', (
    tester,
  ) async {
    final lookup = Completer<String>();
    service.lookup = () => lookup.future;
    await pumpInput(tester);

    await tapVisible(tester, find.text('Use my location'));
    await tester.enterText(addressField(), _manualAddress);
    lookup.complete(_locatedAddress);
    await tester.pumpAndSettle();

    expect(controller.text, _manualAddress);
    expect(find.text('Use this address'), findsOneWidget);
    expect(formKey.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to manual entry ignores a late location result', (
    tester,
  ) async {
    final lookup = Completer<String>();
    service.lookup = () => lookup.future;
    await pumpInput(tester);

    await tapVisible(tester, find.text('Use my location'));
    await tapVisible(tester, find.text('Enter manually'));
    await tester.enterText(addressField(), _manualAddress);
    lookup.complete(_locatedAddress);
    await tester.pumpAndSettle();

    expect(controller.text, _manualAddress);
    expect(find.text('Use my location'), findsOneWidget);
    expect(find.text('Address found'), findsNothing);
    expect(find.text('Use this address'), findsNothing);
    expect(service.lookupCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final action in [
    LocationRecoveryAction.appSettings,
    LocationRecoveryAction.locationSettings,
  ]) {
    testWidgets(
      'settings recovery opens ${action.name} without restarting lookup',
      (tester) async {
        service.lookup = () async => throw AddressLocationException(
          'Enable location or enter your address manually.',
          recoveryAction: action,
        );
        await pumpInput(tester);
        await tapVisible(tester, find.text('Use my location'));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Open settings'));
        await tester.pumpAndSettle();

        expect(
          service.appSettingsCount,
          action == LocationRecoveryAction.appSettings ? 1 : 0,
        );
        expect(
          service.locationSettingsCount,
          action == LocationRecoveryAction.locationSettings ? 1 : 0,
        );
        expect(service.lookupCount, 1);
        await tester.enterText(addressField(), _manualAddress);
        expect(formKey.currentState!.validate(), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'finishing lookup after disposal does not update disposed state',
    (tester) async {
      final lookup = Completer<String>();
      service.lookup = () => lookup.future;
      await pumpInput(tester);

      await tapVisible(tester, find.text('Use my location'));
      expect(service.lookupCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      lookup.complete(_locatedAddress);
      await tester.pump();
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration cannot submit otherwise valid details without an address',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            addressLocationServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> fill(String label, String value) async {
        final field = find.descendant(
          of: find.widgetWithText(AppTextField, label),
          matching: find.byType(TextFormField),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.pump();
      }

      await fill('First name', 'Alex');
      await fill('Last name', 'Reyes');
      await fill('Email address', 'alex@example.com');
      await fill('Password', 'secret123');
      await fill('Confirm password', 'secret123');
      await tapVisible(
        tester,
        find.widgetWithText(AppButton, 'Create account'),
      );
      await tester.pumpAndSettle();

      expect(find.text(_requiredMessage), findsOneWidget);
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(service.lookupCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
