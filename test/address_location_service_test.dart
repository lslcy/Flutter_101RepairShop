import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_101repairshop/core/services/address_location_service.dart';

void main() {
  late _FakeGeolocator locator;
  late List<Placemark> placemarks;
  late AddressLocationService service;
  var reverseGeocodeCalls = 0;

  setUp(() {
    locator = _FakeGeolocator();
    reverseGeocodeCalls = 0;
    placemarks = [
      const Placemark(
        street: '  Rizal Street  ',
        thoroughfare: 'Rizal Street',
        subThoroughfare: '12',
        subLocality: 'Barangay 1',
        locality: 'Davao City',
        subAdministrativeArea: 'davao city',
        administrativeArea: 'Davao del Sur',
        postalCode: '8000',
        country: 'Philippines',
      ),
    ];
    service = AddressLocationService(
      geolocator: locator,
      platformSupported: true,
      reverseGeocode: (latitude, longitude) async {
        reverseGeocodeCalls++;
        expect(latitude, 7.07);
        expect(longitude, 125.6);
        return placemarks;
      },
    );
  });

  Matcher addressError(
    String text, {
    LocationRecoveryAction recovery = LocationRecoveryAction.none,
  }) => isA<AddressLocationException>()
      .having((error) => error.message, 'message', contains(text))
      .having((error) => error.recoveryAction, 'recoveryAction', recovery);

  test('construction never accesses location or asks for permission', () {
    expect(locator.calls, isEmpty);
    expect(reverseGeocodeCalls, 0);
  });

  test(
    'one requested position produces a readable deduplicated address',
    () async {
      expect(
        await service.getCurrentAddress(),
        '12 Rizal Street, Barangay 1, Davao City, Davao del Sur, 8000, Philippines',
      );
      expect(locator.calls, ['enabled', 'permission', 'position']);
      expect(reverseGeocodeCalls, 1);
      expect(locator.settings?.accuracy, LocationAccuracy.high);
      expect(locator.settings?.timeLimit, const Duration(seconds: 20));
    },
  );

  test('requests permission once when initially denied', () async {
    locator.permission = LocationPermission.denied;
    locator.requestedPermission = LocationPermission.whileInUse;

    expect(await service.getCurrentAddress(), contains('12 Rizal Street'));
    expect(locator.calls, ['enabled', 'permission', 'request', 'position']);
  });

  test(
    'denial keeps manual entry available and never reads position',
    () async {
      locator.permission = LocationPermission.denied;
      locator.requestedPermission = LocationPermission.denied;

      await expectLater(
        service.getCurrentAddress(),
        throwsA(addressError('enter your address manually')),
      );
      expect(locator.calls, ['enabled', 'permission', 'request']);
      expect(reverseGeocodeCalls, 0);
    },
  );

  for (final deniedOnRequest in [false, true]) {
    test(
      'permanent denial offers app settings (request: $deniedOnRequest)',
      () async {
        locator.permission = deniedOnRequest
            ? LocationPermission.denied
            : LocationPermission.deniedForever;
        locator.requestedPermission = LocationPermission.deniedForever;

        await expectLater(
          service.getCurrentAddress(),
          throwsA(
            addressError(
              'app settings',
              recovery: LocationRecoveryAction.appSettings,
            ),
          ),
        );
        expect(locator.calls, isNot(contains('position')));
        expect(
          locator.calls.where((call) => call == 'request').length,
          deniedOnRequest ? 1 : 0,
        );
        expect(reverseGeocodeCalls, 0);
      },
    );
  }

  test(
    'disabled GPS offers location settings without a permission prompt',
    () async {
      locator.enabled = false;

      await expectLater(
        service.getCurrentAddress(),
        throwsA(
          addressError(
            'services are off',
            recovery: LocationRecoveryAction.locationSettings,
          ),
        ),
      );
      expect(locator.calls, ['enabled']);
      expect(reverseGeocodeCalls, 0);
    },
  );

  test('unsupported platforms never invoke native plugins', () async {
    final unsupportedService = AddressLocationService(
      geolocator: locator,
      platformSupported: false,
      reverseGeocode: (_, _) async => throw StateError('Must not geocode'),
    );

    await expectLater(
      unsupportedService.getCurrentAddress(),
      throwsA(addressError('enter your address manually')),
    );
    expect(await unsupportedService.openAppSettings(), isFalse);
    expect(await unsupportedService.openLocationSettings(), isFalse);
    expect(locator.calls, isEmpty);
  });

  test('position lookup times out with a manual entry fallback', () async {
    locator.pendingPosition = Completer<Position>().future;
    final timedService = AddressLocationService(
      geolocator: locator,
      platformSupported: true,
      positionTimeout: const Duration(milliseconds: 1),
      reverseGeocode: (_, _) async {
        fail('A timed-out position must not be reverse geocoded');
      },
    );

    await expectLater(
      timedService.getCurrentAddress(),
      throwsA(addressError('took too long')),
    );
    expect(locator.settings?.timeLimit, const Duration(milliseconds: 1));
  });

  test('reverse geocoding also has a bounded wait', () async {
    final timedService = AddressLocationService(
      geolocator: locator,
      platformSupported: true,
      geocodingTimeout: const Duration(milliseconds: 1),
      reverseGeocode: (_, _) => Completer<List<Placemark>>().future,
    );

    await expectLater(
      timedService.getCurrentAddress(),
      throwsA(addressError('took too long')),
    );
  });

  test('native geocoder/network failures produce a helpful fallback', () async {
    final failingService = AddressLocationService(
      geolocator: locator,
      platformSupported: true,
      reverseGeocode: (_, _) async => throw PlatformException(code: 'IO_ERROR'),
    );

    await expectLater(
      failingService.getCurrentAddress(),
      throwsA(addressError('enter it manually')),
    );
  });

  for (final inadequate in <List<Placemark>>[
    [],
    [const Placemark()],
    [const Placemark(locality: 'Davao City', country: 'Philippines')],
    [const Placemark(street: '7.07, 125.6', locality: 'Davao City')],
    [const Placemark(name: '7.07, 125.6', country: 'Philippines')],
    [const Placemark(street: '12', administrativeArea: 'Davao del Sur')],
  ]) {
    test(
      'incomplete geocoding results cannot fill the required address: $inadequate',
      () async {
        placemarks = inadequate;
        await expectLater(
          service.getCurrentAddress(),
          throwsA(addressError('complete address manually')),
        );
      },
    );
  }

  test('uses a later useful placemark after an incomplete result', () async {
    placemarks = [const Placemark(country: 'Philippines'), ...placemarks];
    expect(await service.getCurrentAddress(), startsWith('12 Rizal Street'));
  });

  test(
    'structured lookup returns separated components from one position',
    () async {
      final parts = await service.getCurrentAddressParts();
      expect(parts.houseUnit, '12');
      expect(parts.street, 'Rizal Street');
      expect(parts.barangay, 'Barangay 1');
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
      expect(parts.postalCode, '8000');
      expect(parts.country, 'Philippines');
      expect(locator.calls, ['enabled', 'permission', 'position']);
      expect(reverseGeocodeCalls, 1);
    },
  );

  test('structured lookup chooses the most complete useful result', () async {
    placemarks = [
      const Placemark(country: 'Philippines'),
      const Placemark(subLocality: 'Barangay 1', locality: 'Davao City'),
      ...placemarks,
    ];
    final parts = await service.getCurrentAddressParts();
    expect(parts.houseUnit, '12');
    expect(parts.street, 'Rizal Street');
    expect(parts.postalCode, '8000');
    expect(reverseGeocodeCalls, 1);
  });

  test(
    'structured lookup preserves a useful partial result to finish manually',
    () async {
      placemarks = [
        const Placemark(
          subLocality: 'Barangay Apokon',
          locality: 'Tagum City',
          country: 'Philippines',
        ),
      ];
      final parts = await service.getCurrentAddressParts();
      expect(parts.street, isNull);
      expect(parts.houseUnit, isNull);
      expect(parts.barangay, 'Barangay Apokon');
      expect(parts.city, 'Tagum City');
      expect(parts.province, isNull);
      expect(parts.country, 'Philippines');
    },
  );

  test(
    'concurrent text and structured requests share the native permission flow',
    () async {
      locator.permission = LocationPermission.denied;
      locator.requestedPermission = LocationPermission.whileInUse;
      final results = await Future.wait<Object>([
        service.getCurrentAddress(),
        service.getCurrentAddressParts(),
      ]);
      expect(results.first, startsWith('12 Rizal Street'));
      expect(locator.calls, ['enabled', 'permission', 'request', 'position']);
      expect(reverseGeocodeCalls, 1);
    },
  );

  test('a later explicit lookup reads a fresh position', () async {
    await service.getCurrentAddressParts();
    await service.getCurrentAddressParts();
    expect(locator.calls.where((call) => call == 'position').length, 2);
    expect(reverseGeocodeCalls, 2);
  });

  test('structured lookup uses the same permission denial recovery', () async {
    locator.permission = LocationPermission.deniedForever;
    await expectLater(
      service.getCurrentAddressParts(),
      throwsA(
        addressError(
          'app settings',
          recovery: LocationRecoveryAction.appSettings,
        ),
      ),
    );
    expect(locator.calls, ['enabled', 'permission']);
    expect(reverseGeocodeCalls, 0);
  });

  test(
    'structured lookup has no native calls on unsupported platforms',
    () async {
      final unsupported = AddressLocationService(
        geolocator: locator,
        platformSupported: false,
      );
      await expectLater(
        unsupported.getCurrentAddressParts(),
        throwsA(addressError('enter your address manually')),
      );
      expect(locator.calls, isEmpty);
    },
  );

  for (final inadequate in <List<Placemark>>[
    [],
    [const Placemark(country: 'Philippines')],
    [const Placemark(locality: 'Tagum City', country: 'Philippines')],
    [const Placemark(street: 'Tagum City', locality: 'Tagum City')],
    [const Placemark(street: '7.07, 125.6', locality: 'Davao City')],
  ]) {
    test(
      'structured lookup rejects city/country/coordinates only: $inadequate',
      () async {
        placemarks = inadequate;
        await expectLater(
          service.getCurrentAddressParts(),
          throwsA(addressError('complete address manually')),
        );
      },
    );
  }

  test(
    'reconstructs a street address when the street field is missing',
    () async {
      placemarks = [
        const Placemark(
          subThoroughfare: '15',
          thoroughfare: 'Mabini Street',
          locality: 'Davao City',
          country: 'Philippines',
        ),
      ];
      expect(
        await service.getCurrentAddress(),
        '15 Mabini Street, Davao City, Philippines',
      );
    },
  );

  test(
    'settings only open on an explicit call and failures return false',
    () async {
      expect(locator.calls, isEmpty);
      expect(await service.openAppSettings(), isTrue);
      expect(await service.openLocationSettings(), isTrue);
      expect(locator.calls, ['appSettings', 'locationSettings']);

      locator.settingsError = true;
      expect(await service.openAppSettings(), isFalse);
      expect(await service.openLocationSettings(), isFalse);
    },
  );

  test(
    'GPS disabled during acquisition still offers location settings',
    () async {
      locator.positionError = const LocationServiceDisabledException();

      await expectLater(
        service.getCurrentAddress(),
        throwsA(
          addressError(
            'services are off',
            recovery: LocationRecoveryAction.locationSettings,
          ),
        ),
      );
      expect(reverseGeocodeCalls, 0);
    },
  );
}

class _FakeGeolocator extends GeolocatorPlatform {
  final calls = <String>[];
  bool enabled = true;
  bool settingsError = false;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  LocationSettings? settings;
  Future<Position>? pendingPosition;
  Exception? positionError;

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('enabled');
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('request');
    return requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    calls.add('position');
    settings = locationSettings;
    if (positionError != null) throw positionError!;
    return pendingPosition ??
        Position(
          latitude: 7.07,
          longitude: 125.6,
          timestamp: DateTime(2026),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
  }

  @override
  Future<bool> openAppSettings() async {
    calls.add('appSettings');
    if (settingsError) throw PlatformException(code: 'unavailable');
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    calls.add('locationSettings');
    if (settingsError) throw PlatformException(code: 'unavailable');
    return true;
  }
}
