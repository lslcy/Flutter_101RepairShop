import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_101repairshop/core/models/address_parts.dart';

void main() {
  group('readable address storage', () {
    test('house and street form one line without a duplicated number', () {
      const parts = AddressParts(
        houseUnit: ' 12 ',
        street: '12 Rizal Street',
        barangay: 'Barangay 1',
        city: 'Davao City',
        province: 'Davao del Sur',
        postalCode: '8000',
        country: 'Philippines',
      );
      expect(
        parts.combine(),
        '12 Rizal Street, Barangay 1, Davao City, Davao del Sur, 8000, Philippines',
      );
    });

    test('empty optional fields do not add empty comma-separated segments', () {
      const parts = AddressParts(
        street: ' Mabini   Street ',
        city: 'Davao City',
        province: ' ',
      );
      expect(parts.combine(), 'Mabini Street, Davao City');
    });

    test('house and street containing commas retain their detail', () {
      const parts = AddressParts(
        houseUnit: 'Unit 5, Block 3',
        street: 'Mabini Street, near the school',
        city: 'Tagum City',
      );
      expect(
        parts.combine(),
        'Unit 5, Block 3, Mabini Street, near the school, Tagum City',
      );
    });

    test('duplicate area names are only stored once', () {
      const parts = AddressParts(
        barangay: 'Barangay 1',
        city: 'Davao City',
        additionalDetails: ['davao city'],
        province: 'Davao del Sur',
      );
      expect(parts.combine(), 'Barangay 1, Davao City, Davao del Sur');
    });
  });

  group('legacy address parsing', () {
    test('empty values produce empty fields', () {
      for (final value in [null, '', '  ,  , ']) {
        final parts = AddressParts.fromString(value);
        expect(parts.combine(), isEmpty);
        expect(parts.hasUsefulLocation, isFalse);
      }
    });

    test('a short street and city address does not shift city into street', () {
      final parts = AddressParts.fromString('12 Mabini Street, Davao City');
      expect(parts.houseUnit, '12');
      expect(parts.street, 'Mabini Street');
      expect(parts.barangay, isNull);
      expect(parts.city, 'Davao City');
      expect(parts.province, isNull);
      expect(parts.combine(), '12 Mabini Street, Davao City');
    });

    test('city and country retain their meaning with no local detail', () {
      final parts = AddressParts.fromString('Quezon City, Philippines');
      expect(parts.houseUnit, isNull);
      expect(parts.street, isNull);
      expect(parts.city, 'Quezon City');
      expect(parts.country, 'Philippines');
      expect(parts.hasUsefulLocation, isFalse);
      expect(parts.combine(), 'Quezon City, Philippines');
    });

    test('complete legacy text separates house from street', () {
      const address =
          '10 Rizal Street, Barangay 1, Davao City, Davao del Sur, 8000, Philippines';
      final parts = AddressParts.fromString(address);
      expect(parts.houseUnit, '10');
      expect(parts.street, 'Rizal Street');
      expect(parts.barangay, 'Barangay 1');
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
      expect(parts.postalCode, '8000');
      expect(parts.country, 'Philippines');
      expect(parts.combine(), address);
    });

    test('preliminary six-separated fields remain compatible', () {
      final parts = AddressParts.fromString(
        '12, Mabini Street, Barangay 1, Davao City, Davao del Sur, 8000',
      );
      expect(parts.houseUnit, '12');
      expect(parts.street, 'Mabini Street');
      expect(parts.barangay, 'Barangay 1');
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
      expect(parts.postalCode, '8000');
      expect(
        parts.combine(),
        '12 Mabini Street, Barangay 1, Davao City, Davao del Sur, 8000',
      );
    });

    test('a four-digit house number is not consumed as the postal code', () {
      final parts = AddressParts.fromString(
        '1234, Mabini Street, Barangay 1, Davao City, Davao del Sur, 8000',
      );
      expect(parts.houseUnit, '1234');
      expect(parts.postalCode, '8000');
      final withoutPostal = AddressParts.fromString(
        '1234, Mabini Street, Barangay 1, Davao City, Davao del Sur',
      );
      expect(withoutPostal.houseUnit, '1234');
      expect(withoutPostal.postalCode, isNull);
    });

    test('omitted barangay and house do not shift province or postal code', () {
      final parts = AddressParts.fromString(
        'Rizal Avenue, Tagum City, Davao del Norte, 8100, Philippines',
      );
      expect(parts.houseUnit, isNull);
      expect(parts.street, 'Rizal Avenue');
      expect(parts.barangay, isNull);
      expect(parts.city, 'Tagum City');
      expect(parts.province, 'Davao del Norte');
      expect(parts.postalCode, '8100');
    });

    test('unlabelled municipality follows a recognized barangay', () {
      final parts = AddressParts.fromString(
        'Rizal Street, Brgy. Poblacion, Carmen, Davao del Norte, 8101',
      );
      expect(parts.street, 'Rizal Street');
      expect(parts.barangay, 'Brgy. Poblacion');
      expect(parts.city, 'Carmen');
      expect(parts.province, 'Davao del Norte');
    });

    test('unlabelled municipality and province can follow a street', () {
      final parts = AddressParts.fromString(
        'Rizal Street, Carmen, Davao del Norte, 8101',
      );
      expect(parts.street, 'Rizal Street');
      expect(parts.city, 'Carmen');
      expect(parts.province, 'Davao del Norte');
    });

    test(
      'omitted city can leave street and province available to complete',
      () {
        final parts = AddressParts.fromString('Rizal Street, Davao del Norte');
        expect(parts.street, 'Rizal Street');
        expect(parts.city, isNull);
        expect(parts.province, 'Davao del Norte');
        expect(parts.hasUsefulLocation, isTrue);
      },
    );

    test(
      'a unit and street with omitted city keep the correct field types',
      () {
        final parts = AddressParts.fromString(
          'Unit 5, Mabini Street, Davao del Norte',
        );
        expect(parts.houseUnit, 'Unit 5');
        expect(parts.street, 'Mabini Street');
        expect(parts.city, isNull);
        expect(parts.province, 'Davao del Norte');
      },
    );

    test('extra legacy details survive an edit and recombination', () {
      final parts = AddressParts.fromString(
        'Unit 5, Block 3, Rizal Street, near school, Barangay 1, Tagum City, Davao del Norte, 8100, Philippines',
      );
      final combined = parts.combine();
      for (final text in [
        'Unit 5',
        'Block 3',
        'Rizal Street',
        'near school',
        'Barangay 1',
        'Tagum City',
        'Davao del Norte',
        '8100',
        'Philippines',
      ]) {
        expect(combined, contains(text));
      }
    });

    test('unit, building, street and district keep their field meanings', () {
      final parts = AddressParts.fromString(
        'Unit 1204, Building Three, 123 Mabini Street, Barangay San Antonio, '
        'Buhangin District, Davao City, Davao del Sur, Philippines 8000',
      );
      expect(parts.houseUnit, 'Unit 1204, Building Three');
      // The street's number is separate from the customer's unit number.
      expect(parts.street, '123 Mabini Street');
      expect(parts.barangay, 'Barangay San Antonio');
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
      expect(parts.additionalDetails, ['Buhangin District']);
      expect(parts.country, 'Philippines');
      expect(parts.postalCode, '8000');
      expect(parts.combine(), contains('123 Mabini Street'));
      expect(parts.combine(), contains('Buhangin District'));
    });

    test('an unprefixed barangay with no street keeps its field on reopen', () {
      const original = AddressParts(
        barangay: 'Mankilam',
        city: 'Tagum City',
        province: 'Davao del Norte',
      );
      final reopened = AddressParts.fromString(original.combine());
      expect(
        original.combine(),
        'Barangay Mankilam, Tagum City, Davao del Norte',
      );
      expect(reopened.street, isNull);
      expect(reopened.houseUnit, isNull);
      expect(reopened.barangay, 'Barangay Mankilam');
      expect(reopened.city, 'Tagum City');
      expect(reopened.province, 'Davao del Norte');
      expect(reopened.hasUsefulLocation, isTrue);
    });

    test('a multi-part house survives reopening with no barangay', () {
      const original = AddressParts(
        houseUnit: 'Unit 8, Block 3',
        street: 'Mabini Street',
        city: 'Tagum City',
        province: 'Davao del Norte',
      );
      final reopened = AddressParts.fromString(original.combine());
      expect(reopened.houseUnit, original.houseUnit);
      expect(reopened.street, original.street);
      expect(reopened.barangay, isNull);
      expect(reopened.city, original.city);
      expect(reopened.province, original.province);
      expect(reopened.combine(), original.combine());
    });

    test('a unit and numbered street keep both numbers when reopening', () {
      const original = AddressParts(
        houseUnit: 'Unit 8',
        street: '45 Jacinto Street',
        city: 'Tagum City',
      );
      final reopened = AddressParts.fromString(original.combine());
      expect(reopened.houseUnit, 'Unit 8');
      expect(reopened.street, '45 Jacinto Street');
      expect(reopened.combine(), original.combine());
    });

    test('multi-part house and street keep an unlabelled municipality', () {
      final parts = AddressParts.fromString(
        'Unit 8, Block 3, Mabini Street, Carmen, Davao del Norte',
      );
      expect(parts.houseUnit, 'Unit 8, Block 3');
      expect(parts.street, 'Mabini Street');
      expect(parts.city, 'Carmen');
      expect(parts.province, 'Davao del Norte');
      expect(parts.barangay, isNull);
    });

    test('district and landmark are retained without guessing barangay', () {
      final parts = AddressParts.fromString(
        'Mabini Street, Buhangin District, near the school, Davao City, '
        'Davao del Sur',
      );
      expect(parts.street, 'Mabini Street');
      expect(parts.barangay, isNull);
      expect(parts.additionalDetails, ['Buhangin District', 'near the school']);
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
    });

    test('an identifiable province can follow district after city', () {
      final parts = AddressParts.fromString(
        'Mabini Street, Davao City, Buhangin District, Davao del Sur',
      );
      expect(parts.street, 'Mabini Street');
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
      expect(parts.additionalDetails, ['Buhangin District']);
    });

    test('a locality and recognizable province are not a street', () {
      final parts = AddressParts.fromString('Carmen, Davao del Norte');
      expect(parts.houseUnit, isNull);
      expect(parts.street, isNull);
      expect(parts.barangay, isNull);
      expect(parts.city, 'Carmen');
      expect(parts.province, 'Davao del Norte');
      expect(parts.hasUsefulLocation, isFalse);
    });

    for (final address in ['Philippines 8000', '8000 Philippines']) {
      test('country and postal code parse without a street: $address', () {
        final parts = AddressParts.fromString(address);
        expect(parts.country, 'Philippines');
        expect(parts.postalCode, '8000');
        expect(parts.houseUnit, isNull);
        expect(parts.street, isNull);
        expect(parts.city, isNull);
      });
    }

    test('a province and country are not parsed as a street', () {
      final parts = AddressParts.fromString('Davao del Norte, Philippines');
      expect(parts.street, isNull);
      expect(parts.province, 'Davao del Norte');
      expect(parts.country, 'Philippines');
      expect(parts.hasUsefulLocation, isFalse);
    });
  });

  group('placemark components', () {
    test('extracts PH components and strips house number from the street', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          street: ' 12 Rizal Street ',
          subThoroughfare: '12',
          thoroughfare: 'Rizal Street',
          subLocality: 'Barangay 1',
          locality: 'Davao City',
          subAdministrativeArea: 'davao city',
          administrativeArea: 'Davao del Sur',
          postalCode: '8000',
          country: 'Philippines',
        ),
      );
      expect(parts.houseUnit, '12');
      expect(parts.street, 'Rizal Street');
      expect(parts.barangay, 'Barangay 1');
      expect(parts.city, 'Davao City');
      expect(parts.province, 'Davao del Sur');
      expect(parts.postalCode, '8000');
      expect(parts.country, 'Philippines');
      expect(parts.additionalDetails, isEmpty);
      expect(parts.hasUsefulLocation, isTrue);
    });

    test('reconstructs street from thoroughfare without duplicating house', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          subThoroughfare: '15',
          thoroughfare: 'Mabini Street',
          locality: 'Davao City',
          country: 'Philippines',
        ),
      );
      expect(parts.houseUnit, '15');
      expect(parts.street, 'Mabini Street');
      expect(parts.combine(), '15 Mabini Street, Davao City, Philippines');
    });

    test(
      'a house number embedded in street can be extracted without a hint',
      () {
        final parts = AddressParts.fromPlacemark(
          const Placemark(street: '12-A Rizal Street', locality: 'Tagum City'),
        );
        expect(parts.houseUnit, '12-A');
        expect(parts.street, 'Rizal Street');
      },
    );

    test('barangay and city remain useful when no street was returned', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          subLocality: 'Barangay Apokon',
          locality: 'Tagum City',
          country: 'Philippines',
        ),
      );
      expect(parts.street, isNull);
      expect(parts.barangay, 'Barangay Apokon');
      expect(parts.city, 'Tagum City');
      expect(parts.hasUsefulLocation, isTrue);
    });

    test('street and province remain useful when city was not returned', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          thoroughfare: 'Rizal Street',
          administrativeArea: 'Davao del Norte',
        ),
      );
      expect(parts.street, 'Rizal Street');
      expect(parts.city, isNull);
      expect(parts.province, 'Davao del Norte');
      expect(parts.hasUsefulLocation, isTrue);
    });

    test('falls back from a city-only street field to a real thoroughfare', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          street: 'Tagum City',
          thoroughfare: 'Rizal Street',
          locality: 'Tagum City',
        ),
      );
      expect(parts.street, 'Rizal Street');
      expect(parts.hasUsefulLocation, isTrue);
    });

    test(
      'a comma-separated geocoder street does not duplicate house or areas',
      () {
        final parts = AddressParts.fromPlacemark(
          const Placemark(
            street: '12 Rizal Street, Barangay 1, Tagum City, Davao del Norte',
            locality: 'Tagum City',
            administrativeArea: 'Davao del Norte',
          ),
        );
        expect(parts.houseUnit, '12');
        expect(parts.street, 'Rizal Street');
        expect(parts.barangay, 'Barangay 1');
        expect(
          parts.combine(),
          '12 Rizal Street, Barangay 1, Tagum City, Davao del Norte',
        );
      },
    );

    test('PH province in sub-area preserves the administrative region', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          isoCountryCode: 'PH',
          thoroughfare: 'Mabini Street',
          locality: 'Tagum City',
          subAdministrativeArea: 'Davao del Norte',
          administrativeArea: 'Davao Region',
          country: 'Philippines',
        ),
      );
      expect(parts.street, 'Mabini Street');
      expect(parts.city, 'Tagum City');
      expect(parts.province, 'Davao del Norte');
      expect(parts.additionalDetails, ['Davao Region']);
      final reopened = AddressParts.fromString(parts.combine());
      expect(reopened.city, parts.city);
      expect(reopened.province, 'Davao del Norte');
      expect(reopened.additionalDetails, ['Davao Region']);
    });

    test('PH province is not substituted into a missing city', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          isoCountryCode: 'PH',
          thoroughfare: 'Mabini Street',
          subAdministrativeArea: 'Davao del Norte',
          administrativeArea: 'Davao Region',
        ),
      );
      expect(parts.city, isNull);
      expect(parts.province, 'Davao del Norte');
      expect(parts.hasUsefulLocation, isTrue);
      final reopened = AddressParts.fromString(parts.combine());
      expect(reopened.city, isNull);
      expect(reopened.street, 'Mabini Street');
      expect(reopened.province, 'Davao del Norte');
      expect(reopened.additionalDetails, ['Davao Region']);
    });

    test('GPS number shared by house and street is stored only once', () {
      final parts = AddressParts.fromPlacemark(
        const Placemark(
          subThoroughfare: '123',
          street: '123 Mabini Street',
          locality: 'Tagum City',
        ),
      );
      expect(parts.houseUnit, '123');
      expect(parts.street, 'Mabini Street');
      expect(parts.combine(), '123 Mabini Street, Tagum City');
    });

    for (final inadequate in [
      const Placemark(),
      const Placemark(country: 'Philippines'),
      const Placemark(locality: 'Tagum City', country: 'Philippines'),
      const Placemark(street: 'Tagum City', locality: 'Tagum City'),
      const Placemark(street: '7.07, 125.6', locality: 'Tagum City'),
      const Placemark(street: '12', administrativeArea: 'Davao del Norte'),
      const Placemark(street: 'Rizal Street', country: 'Philippines'),
    ]) {
      test(
        'rejects a placemark without useful local and area detail: $inadequate',
        () {
          expect(
            AddressParts.fromPlacemark(inadequate).hasUsefulLocation,
            isFalse,
          );
        },
      );
    }
  });
}
