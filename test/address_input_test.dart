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
    'Unit 8, 45 Jacinto Street, Barangay San Pedro, Tagum City, Davao del Norte, 8100';
const _locatedParts = AddressParts(
  houseUnit: '123',
  street: 'Mabini Street',
  barangay: 'Barangay 1',
  city: 'Tagum City',
  province: 'Davao del Norte',
  postalCode: '8100',
);

class _LocationService extends AddressLocationService {
  _LocationService() : super(platformSupported: true);

  int lookupCount = 0;
  int appSettingsCount = 0;
  int locationSettingsCount = 0;
  Future<AddressParts> Function()? lookup;

  @override
  Future<AddressParts> getCurrentAddressParts() {
    lookupCount++;
    return lookup?.call() ?? Future.value(_locatedParts);
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

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextFormField),
  );

  String fieldText(WidgetTester tester, String label) =>
      tester.widget<TextFormField>(field(label)).controller!.text;

  Future<void> pumpInput(
    WidgetTester tester, {
    bool enabled = true,
    TextEditingController? addressController,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [addressLocationServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: AddressInput(
                  controller: addressController ?? controller,
                  enabled: enabled,
                ),
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

  Future<void> enterField(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
    await tester.pump();
  }

  Future<void> fillManual(WidgetTester tester) async {
    for (final entry in {
      'House / unit no. (optional)': 'Unit 8',
      'Street / subdivision': '45 Jacinto Street',
      'Barangay': 'Barangay San Pedro',
      'City / municipality (required)': 'Tagum City',
      'Province (required)': 'Davao del Norte',
      'Postal code (optional)': '8100',
    }.entries) {
      await enterField(tester, entry.key, entry.value);
    }
  }

  testWidgets(
    'separate fields do not request location or rewrite saved address',
    (tester) async {
      controller.text = _manualAddress;
      await pumpInput(tester);

      expect(service.lookupCount, 0);
      expect(controller.text, _manualAddress);
      expect(find.byType(TextFormField), findsNWidgets(6));
      expect(field('House / unit no. (optional)'), findsOneWidget);
      expect(field('Street / subdivision'), findsOneWidget);
      expect(field('Barangay'), findsOneWidget);
      expect(field('City / municipality (required)'), findsOneWidget);
      expect(field('Province (required)'), findsOneWidget);
      expect(field('Postal code (optional)'), findsOneWidget);
      expect(find.text('Use my location'), findsOneWidget);
      expect(find.text('Use this address'), findsNothing);
    },
  );

  for (final legacy in [
    '12 Mabini Street, Davao City',
    'Unit 8, 45 Jacinto Street\nBarangay San Pedro\nDavao City, 8000',
    'Unit 1204, Building Three, 123 Mabini Street, Barangay San Antonio, '
        'Buhangin District, Davao City, Davao del Sur, Philippines 8000',
  ]) {
    testWidgets(
      'opening a legacy address keeps every original detail: $legacy',
      (tester) async {
        controller.text = legacy;
        await pumpInput(tester);
        expect(controller.text, legacy);
        expect(formKey.currentState!.validate(), isTrue);
        expect(service.lookupCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'focusing a legacy address without edits does not rewrite its saved text',
    (tester) async {
      const legacy = '12 Mabini Street, Davao City';
      controller.text = legacy;
      await pumpInput(tester);

      await tapVisible(tester, field('Street / subdivision'));
      final streetController = tester
          .widget<TextFormField>(field('Street / subdivision'))
          .controller!;
      streetController.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tapVisible(tester, field('City / municipality (required)'));
      await tester.pumpAndSettle();

      expect(controller.text, legacy);
      expect(fieldText(tester, 'Province (required)'), isEmpty);
      expect(formKey.currentState!.validate(), isTrue);
      expect(service.lookupCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacing the parent controller resets every field and ignores old lookup',
    (tester) async {
      controller.text = _manualAddress;
      final lookup = Completer<AddressParts>();
      service.lookup = () => lookup.future;
      await pumpInput(tester);
      await tapVisible(tester, find.text('Use my location'));

      final replacement = TextEditingController(
        text: '18 Bonifacio Road, Barangay 2, Davao City, Davao del Sur',
      );
      addTearDown(replacement.dispose);
      await pumpInput(tester, addressController: replacement);
      lookup.complete(_locatedParts);
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'House / unit no. (optional)'), '18');
      expect(fieldText(tester, 'Street / subdivision'), 'Bonifacio Road');
      expect(fieldText(tester, 'Barangay'), 'Barangay 2');
      expect(fieldText(tester, 'City / municipality (required)'), 'Davao City');
      expect(fieldText(tester, 'Province (required)'), 'Davao del Sur');
      expect(fieldText(tester, 'Postal code (optional)'), isEmpty);
      expect(
        replacement.text,
        '18 Bonifacio Road, Barangay 2, Davao City, Davao del Sur',
      );
      expect(controller.text, _manualAddress);
      expect(formKey.currentState!.validate(), isTrue);
      expect(find.text('Use my location'), findsOneWidget);
      expect(service.lookupCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'GPS house number does not overwrite a house from an existing saved address',
    (tester) async {
      controller.text = _manualAddress;
      await pumpInput(tester);
      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'House / unit no. (optional)'), 'Unit 8');
      expect(fieldText(tester, 'Street / subdivision'), 'Mabini Street');
      expect(controller.text, contains('Unit 8'));
      expect(controller.text, isNot(contains('123')));
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving and reopening a prefixed unit preserves it when GPS reports a house',
    (tester) async {
      await pumpInput(tester);
      await fillManual(tester);
      final savedAddress = controller.text;
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpInput(tester);
      expect(controller.text, savedAddress);
      expect(fieldText(tester, 'House / unit no. (optional)'), 'Unit 8');

      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'House / unit no. (optional)'), 'Unit 8');
      expect(fieldText(tester, 'Street / subdivision'), 'Mabini Street');
      expect(controller.text, contains('Unit 8'));
      expect(controller.text, isNot(contains('123')));
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'required address rejects whitespace and manual fields remain usable',
    (tester) async {
      await pumpInput(tester);
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      for (final label in [
        'Street / subdivision',
        'Barangay',
        'City / municipality (required)',
        'Province (required)',
      ]) {
        await enterField(tester, label, '  ');
      }
      expect(formKey.currentState!.validate(), isFalse);

      await fillManual(tester);
      expect(formKey.currentState!.validate(), isTrue);
      expect(controller.text, contains('Unit 8'));
      expect(controller.text, contains('45 Jacinto Street'));
      expect(controller.text, contains('Barangay San Pedro'));
      expect(controller.text, contains('Tagum City'));
      expect(controller.text, contains('Davao del Norte'));
      expect(controller.text, contains('8100'));
      expect(service.lookupCount, 0);
    },
  );

  testWidgets('house and postal code are optional', (tester) async {
    await pumpInput(tester);
    for (final entry in {
      'Street / subdivision': 'Mabini Street',
      'Barangay': 'Barangay 1',
      'City / municipality (required)': 'Tagum City',
      'Province (required)': 'Davao del Norte',
    }.entries) {
      await enterField(tester, entry.key, entry.value);
    }
    expect(formKey.currentState!.validate(), isTrue);
    expect(fieldText(tester, 'House / unit no. (optional)'), isEmpty);
    expect(fieldText(tester, 'Postal code (optional)'), isEmpty);
  });

  testWidgets('barangay can identify a local address when there is no street', (
    tester,
  ) async {
    await pumpInput(tester);
    await enterField(tester, 'Barangay', 'Barangay 1');
    await enterField(tester, 'City / municipality (required)', 'Tagum City');
    await enterField(tester, 'Province (required)', 'Davao del Norte');
    expect(formKey.currentState!.validate(), isTrue);
    expect(fieldText(tester, 'Street / subdivision'), isEmpty);
    expect(controller.text, contains('Barangay 1'));
  });

  testWidgets(
    'denying location leaves manual fields and saved text unchanged',
    (tester) async {
      const message =
          'Location permission was not granted. Enter your address manually.';
      service.lookup = () async =>
          throw const AddressLocationException(message);
      await pumpInput(tester);
      await fillManual(tester);
      final savedText = controller.text;

      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpAndSettle();
      expect(service.lookupCount, 1);
      expect(find.text(message), findsOneWidget);
      expect(controller.text, savedText);
      expect(fieldText(tester, 'Street / subdivision'), '45 Jacinto Street');
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial GPS address remains incomplete until the missing city is entered',
    (tester) async {
      service.lookup = () async => const AddressParts(
        street: 'Mabini Street',
        province: 'Davao del Norte',
      );
      await pumpInput(tester);
      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'Street / subdivision'), 'Mabini Street');
      expect(fieldText(tester, 'City / municipality (required)'), isEmpty);
      expect(fieldText(tester, 'Province (required)'), 'Davao del Norte');
      expect(
        find.text('Location found. Fill in the missing address details below.'),
        findsOneWidget,
      );
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Enter your city or municipality.'), findsOneWidget);
      expect(controller.text, contains('Mabini Street'));

      await enterField(tester, 'City / municipality (required)', 'Tagum City');
      expect(formKey.currentState!.validate(), isTrue);
      expect(controller.text, contains('Tagum City'));
      expect(fieldText(tester, 'House / unit no. (optional)'), isEmpty);
      expect(service.lookupCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('location fills each field automatically and remains editable', (
    tester,
  ) async {
    final lookup = Completer<AddressParts>();
    service.lookup = () => lookup.future;
    await pumpInput(tester);
    await tapVisible(tester, find.text('Use my location'));
    expect(service.lookupCount, 1);
    expect(controller.text, isEmpty);

    lookup.complete(_locatedParts);
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'House / unit no. (optional)'), '123');
    expect(fieldText(tester, 'Street / subdivision'), 'Mabini Street');
    expect(fieldText(tester, 'Barangay'), 'Barangay 1');
    expect(fieldText(tester, 'City / municipality (required)'), 'Tagum City');
    expect(fieldText(tester, 'Province (required)'), 'Davao del Norte');
    expect(fieldText(tester, 'Postal code (optional)'), '8100');
    expect(find.text('Use this address'), findsNothing);
    expect(controller.text, contains('Mabini Street'));
    expect(formKey.currentState!.validate(), isTrue);

    await enterField(tester, 'House / unit no. (optional)', 'Unit 4');
    expect(fieldText(tester, 'House / unit no. (optional)'), 'Unit 4');
    expect(controller.text, contains('Unit 4'));
    expect(formKey.currentState!.validate(), isTrue);
    expect(service.lookupCount, 1);
  });

  testWidgets(
    'location without a house number preserves the manually entered unit',
    (tester) async {
      service.lookup = () async => const AddressParts(
        street: 'Mabini Street',
        barangay: 'Barangay 1',
        city: 'Tagum City',
        province: 'Davao del Norte',
      );
      await pumpInput(tester);
      await enterField(
        tester,
        'House / unit no. (optional)',
        'Unit 4, Building A',
      );
      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpAndSettle();

      expect(
        fieldText(tester, 'House / unit no. (optional)'),
        'Unit 4, Building A',
      );
      expect(fieldText(tester, 'Street / subdivision'), 'Mabini Street');
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('typing while lookup runs invalidates its late result', (
    tester,
  ) async {
    final lookup = Completer<AddressParts>();
    service.lookup = () => lookup.future;
    await pumpInput(tester);

    await tapVisible(tester, find.text('Use my location'));
    await fillManual(tester);
    final typedAddress = controller.text;
    lookup.complete(_locatedParts);
    await tester.pumpAndSettle();

    expect(controller.text, typedAddress);
    expect(fieldText(tester, 'House / unit no. (optional)'), 'Unit 8');
    expect(fieldText(tester, 'Street / subdivision'), '45 Jacinto Street');
    expect(formKey.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to manual entry ignores a late location result', (
    tester,
  ) async {
    final lookup = Completer<AddressParts>();
    service.lookup = () => lookup.future;
    await pumpInput(tester);

    await tapVisible(tester, find.text('Use my location'));
    await tapVisible(tester, find.text('Enter manually'));
    await fillManual(tester);
    final typedAddress = controller.text;
    lookup.complete(_locatedParts);
    await tester.pumpAndSettle();

    expect(controller.text, typedAddress);
    expect(find.text('Use my location'), findsOneWidget);
    expect(find.text('Use this address'), findsNothing);
    expect(service.lookupCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final action in [
    LocationRecoveryAction.appSettings,
    LocationRecoveryAction.locationSettings,
  ]) {
    testWidgets(
      'settings recovery opens ${action.name} without repeating lookup',
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
        await fillManual(tester);
        expect(formKey.currentState!.validate(), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'asynchronous parent controller hydration updates separate fields',
    (tester) async {
      await pumpInput(tester);
      controller.text = _manualAddress;
      await tester.pumpAndSettle();

      expect(controller.text, _manualAddress);
      expect(fieldText(tester, 'Street / subdivision'), contains('Jacinto'));
      expect(fieldText(tester, 'City / municipality (required)'), 'Tagum City');
      expect(service.lookupCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving and reopening without house or postal keeps field meanings',
    (tester) async {
      await pumpInput(tester);
      await enterField(tester, 'Street / subdivision', 'Mabini Street');
      await enterField(tester, 'Barangay', 'Barangay 1');
      await enterField(tester, 'City / municipality (required)', 'Tagum City');
      await enterField(tester, 'Province (required)', 'Davao del Norte');
      final saved = controller.text;
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpInput(tester);

      expect(controller.text, saved);
      expect(fieldText(tester, 'House / unit no. (optional)'), isEmpty);
      expect(fieldText(tester, 'Street / subdivision'), 'Mabini Street');
      expect(fieldText(tester, 'Barangay'), 'Barangay 1');
      expect(fieldText(tester, 'City / municipality (required)'), 'Tagum City');
      expect(fieldText(tester, 'Province (required)'), 'Davao del Norte');
      expect(fieldText(tester, 'Postal code (optional)'), isEmpty);
      expect(formKey.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled inputs ignore lookup results and cannot start another',
    (tester) async {
      final lookup = Completer<AddressParts>();
      service.lookup = () => lookup.future;
      await pumpInput(tester);
      await tapVisible(tester, find.text('Use my location'));
      await pumpInput(tester, enabled: false);
      lookup.complete(_locatedParts);
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      for (final widget in tester.widgetList<AppTextField>(
        find.byType(AppTextField),
      )) {
        expect(widget.enabled, isFalse);
      }
      expect(service.lookupCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'finishing lookup after disposal does not update disposed state',
    (tester) async {
      final lookup = Completer<AddressParts>();
      service.lookup = () => lookup.future;
      await pumpInput(tester);

      await tapVisible(tester, find.text('Use my location'));
      await tester.pumpWidget(const SizedBox.shrink());
      lookup.complete(_locatedParts);
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

      for (final entry in {
        'First name': 'Alex',
        'Last name': 'Reyes',
        'Email address': 'alex@example.com',
        'Password': 'Secret1!23',
        'Confirm password': 'Secret1!23',
      }.entries) {
        await enterField(tester, entry.key, entry.value);
      }
      await tapVisible(
        tester,
        find.widgetWithText(AppButton, 'Create account'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(service.lookupCount, 0);
      final street = tester.widget<EditableText>(
        find.descendant(
          of: field('Street / subdivision'),
          matching: find.byType(EditableText),
        ),
      );
      expect(street.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
