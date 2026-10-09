import 'package:geocoding/geocoding.dart' as geocoding;

/// Editable address fields whose stored representation remains readable text.
class AddressParts {
  const AddressParts({
    this.houseUnit,
    this.street,
    this.barangay,
    this.city,
    this.province,
    this.postalCode,
    this.country,
    this.additionalDetails = const [],
  });

  final String? houseUnit;
  final String? street;
  final String? barangay;
  final String? city;
  final String? province;
  final String? postalCode;
  final String? country;

  /// Retains details in older free-text addresses that have no dedicated field.
  final List<String> additionalDetails;

  String combine() {
    final streetParts = _splitStreet(street, houseUnit: houseUnit);
    final house = streetParts.$1;
    final firstLine = [house, streetParts.$2].whereType<String>().join(
      house != null && (house.contains(',') || !_isNumericHouse(house))
          ? ', '
          : ' ',
    );
    final localArea = _clean(barangay);
    final storedBarangay = localArea == null || _isBarangay(localArea)
        ? localArea
        : 'Barangay $localArea';
    final seen = <String>{};
    final result = <String>[];
    for (final value in [
      firstLine,
      storedBarangay,
      city,
      ...additionalDetails,
      province,
      postalCode,
      country,
    ]) {
      final cleaned = _clean(value);
      if (cleaned != null && seen.add(cleaned.toLowerCase())) {
        result.add(cleaned);
      }
    }
    return result.join(', ');
  }

  /// GPS must provide a local detail and a city or province, not coordinates.
  bool get hasUsefulLocation {
    final areas = [city, province, country]
        .map(_clean)
        .whereType<String>()
        .map((value) => value.toLowerCase())
        .toSet();
    bool localDetail(String? value) {
      final cleaned = _clean(value);
      return _hasDetail(cleaned) && !areas.contains(cleaned!.toLowerCase());
    }

    return (localDetail(street) || localDetail(barangay)) &&
        (_hasDetail(city) || _hasDetail(province));
  }

  /// Prefer a result with more editable components when geocoding returns many.
  int get locationDetailScore => [
    houseUnit,
    street,
    barangay,
    city,
    province,
    postalCode,
  ].where((value) => _clean(value) != null).length;

  factory AddressParts.fromPlacemark(geocoding.Placemark placemark) {
    final house = _clean(placemark.subThoroughfare);
    final thoroughfare = _clean(placemark.thoroughfare);
    var street = _clean(placemark.street);
    final areaNames = [
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.country,
    ].map(_clean).whereType<String>().map((value) => value.toLowerCase());
    if (!_hasDetail(street) || areaNames.contains(street?.toLowerCase())) {
      street = thoroughfare;
    }
    final parsedStreet = street?.contains(',') == true
        ? AddressParts.fromString(street)
        : null;
    final streetParts = _splitStreet(
      parsedStreet?.street ?? street,
      houseUnit: house ?? parsedStreet?.houseUnit,
    );
    final district = _clean(placemark.subAdministrativeArea);
    final administrativeArea = _clean(placemark.administrativeArea);
    // PH native geocoders can return a province under subAdministrativeArea
    // and its region under administrativeArea.
    final provinceIsSubArea =
        placemark.isoCountryCode?.toUpperCase() == 'PH' &&
        district != null &&
        _looksLikeProvince(district) &&
        administrativeArea != null &&
        RegExp(
          r'\bregion\b',
          caseSensitive: false,
        ).hasMatch(administrativeArea);
    final city =
        _clean(placemark.locality) ??
        (provinceIsSubArea ? null : district) ??
        parsedStreet?.city;
    final province = provinceIsSubArea
        ? district
        : administrativeArea ?? parsedStreet?.province;
    return AddressParts(
      houseUnit: streetParts.$1,
      street: streetParts.$2,
      barangay: _clean(placemark.subLocality) ?? parsedStreet?.barangay,
      city: city,
      province: province,
      postalCode: _clean(placemark.postalCode) ?? parsedStreet?.postalCode,
      country: _clean(placemark.country) ?? parsedStreet?.country,
      additionalDetails: [
        ...?parsedStreet?.additionalDetails,
        if (provinceIsSubArea) administrativeArea,
        if (district != null &&
            district.toLowerCase() != city?.toLowerCase() &&
            district.toLowerCase() != province?.toLowerCase())
          district,
      ],
    );
  }

  /// Best-effort parsing of both free-text and earlier comma-separated fields.
  /// Identifiable components anchor the parse; absent fields do not shift all
  /// the following fields into the wrong inputs.
  factory AddressParts.fromString(String? address) {
    final pieces = (address ?? '')
        .split(',')
        .map(_clean)
        .whereType<String>()
        .toList();
    if (pieces.isEmpty) return const AddressParts();

    // Some existing geocoded addresses put the country and postcode together.
    // Split only a recognized country, rather than a street ending in a number.
    String? countryPostalCode;
    for (var index = 0; index < pieces.length; index++) {
      final match = RegExp(r'^(.+?)\s+(\d{4,6}(?:-\d{4})?)$')
          .firstMatch(pieces[index]);
      final reverse = RegExp(r'^(\d{4,6}(?:-\d{4})?)\s+(.+)$')
          .firstMatch(pieces[index]);
      if (match != null && _isCountry(match.group(1)!)) {
        countryPostalCode = match.group(2);
        pieces.replaceRange(index, index + 1, [
          match.group(1)!,
          match.group(2)!,
        ]);
        index++;
      } else if (reverse != null && _isCountry(reverse.group(2)!)) {
        countryPostalCode = reverse.group(1);
        pieces.replaceRange(index, index + 1, [
          reverse.group(1)!,
          reverse.group(2)!,
        ]);
        index++;
      }
    }

    String? takeWhere(bool Function(String) matches) {
      final index = pieces.indexWhere(matches);
      return index < 0 ? null : pieces.removeAt(index);
    }

    final country = takeWhere(_isCountry);
    // A lone number might be a house number, not a postal code.
    String? postalCode = countryPostalCode;
    for (var index = pieces.length - 1; index >= 0; index--) {
      if ((index > 0 || pieces[index] == countryPostalCode) &&
          RegExp(r'^\d{4,6}(?:-\d{4})?$').hasMatch(pieces[index])) {
        postalCode = pieces.removeAt(index);
        break;
      }
    }
    // Unit, building and block are one editable field, even when the original
    // author separated each detail with commas.
    var housePieceCount = 0;
    while (housePieceCount < pieces.length &&
        _isHouseOnly(pieces[housePieceCount])) {
      housePieceCount++;
    }
    if (housePieceCount > 1) {
      final house = pieces.take(housePieceCount).join(', ');
      pieces.replaceRange(0, housePieceCount, [house]);
    }
    final identifiedExtras = <String>[];
    pieces.removeWhere((piece) {
      final isExtra =
          _isAdditionalDetail(piece) &&
          !_looksLikeStreet(piece) &&
          !_isBarangay(piece) &&
          !_isHouseOnly(piece) &&
          !_isCity(piece) &&
          !_looksLikeProvince(piece);
      if (isExtra) identifiedExtras.add(piece);
      return isExtra;
    });
    final barangayIndex = pieces.indexWhere(_isBarangay);
    final cityIndex = pieces.indexWhere(_isCity);
    String? city;
    String? province;
    String? barangay;
    final extra = <String>[...identifiedExtras];
    List<String> prefix;

    if (cityIndex >= 0) {
      city = pieces[cityIndex];
      prefix = pieces.sublist(0, cityIndex);
      final suffix = pieces.sublist(cityIndex + 1);
      final provinceIndex = suffix.indexWhere(_looksLikeProvince);
      if (provinceIndex >= 0) {
        province = suffix.removeAt(provinceIndex);
      } else if (suffix.isNotEmpty && !_isAdditionalDetail(suffix.first)) {
        province = suffix.removeAt(0);
      }
      extra.addAll(suffix);
      final localIndex = prefix.indexWhere(_isBarangay);
      if (localIndex >= 0) barangay = prefix.removeAt(localIndex);
    } else if (barangayIndex >= 0) {
      barangay = pieces[barangayIndex];
      prefix = pieces.sublist(0, barangayIndex);
      final suffix = pieces.sublist(barangayIndex + 1);
      if (suffix.isNotEmpty) city = suffix.removeAt(0);
      if (suffix.isNotEmpty) province = suffix.removeAt(0);
      extra.addAll(suffix);
    } else {
      prefix = List.of(pieces);
      // Unlabelled city/municipality and province usually follow the street.
      final separateHouseAndStreet =
          prefix.length > 1 &&
          _isHouseOnly(prefix.first) &&
          _looksLikeStreet(prefix[1]);
      if (prefix.length >= (separateHouseAndStreet ? 4 : 3)) {
        province = prefix.removeLast();
        city = prefix.removeLast();
      } else if (separateHouseAndStreet && prefix.length == 3) {
        final area = prefix.removeLast();
        if (_looksLikeProvince(area)) {
          province = area;
        } else {
          city = area;
        }
      } else if (prefix.length == 2 && !_isHouseOnly(prefix.first)) {
        final area = prefix.removeLast();
        if (_looksLikeProvince(area)) {
          province = area;
          if (!_looksLikeStreet(prefix.first) &&
              !_isAdditionalDetail(prefix.first)) {
            city = prefix.removeLast();
          }
        } else {
          city = area;
        }
      } else if (prefix.length == 1 && !_looksLikeStreet(prefix.first)) {
        final area = prefix.first;
        if (_looksLikeProvince(area)) {
          province = prefix.removeLast();
        } else if (country != null) {
          city = prefix.removeLast();
        }
      }
    }

    String? house;
    if (prefix.length > 1 && _isHouseOnly(prefix.first)) {
      house = prefix.removeAt(0);
    }
    // A remaining component between a street and an identified city is often
    // an unlabelled barangay. Retain any further free-text details as well.
    if (barangay == null &&
        prefix.length > 1 &&
        _looksLikeStreet(prefix.first) &&
        !_isAdditionalDetail(prefix[1])) {
      barangay = prefix.removeAt(1);
    }
    final streetParts = _splitStreet(
      prefix.isEmpty ? null : prefix.removeAt(0),
      houseUnit: house,
    );
    extra.insertAll(0, prefix);
    return AddressParts(
      houseUnit: streetParts.$1,
      street: streetParts.$2,
      barangay: barangay,
      city: city,
      province: province,
      postalCode: postalCode,
      country: country,
      additionalDetails: extra,
    );
  }

  static (String?, String?) _splitStreet(String? value, {String? houseUnit}) {
    var house = _clean(houseUnit);
    var street = _clean(value);
    if (street == null) return (house, null);
    if (house != null) {
      final prefix = RegExp(
        '^${RegExp.escape(house)}(?:\\s+|\$)',
        caseSensitive: false,
      );
      street = _clean(street.replaceFirst(prefix, ''));
    } else {
      final leadingHouse = RegExp(
        r'^((?:#\s*)?\d+[A-Za-z]?(?:[-/]\w+)?)\s+(.+)$',
      ).firstMatch(street);
      if (leadingHouse != null) {
        house = _clean(leadingHouse.group(1));
        street = _clean(leadingHouse.group(2));
      } else if (_isHouseOnly(street)) {
        house = street;
        street = null;
      }
    }
    return (house, street);
  }

  static String? _clean(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static bool _hasDetail(String? value) =>
      value != null &&
      value.isNotEmpty &&
      !RegExp(r'^[\d\s.,+\-\u00b0\u2032\u2033/()]+$').hasMatch(value);

  static bool _isCity(String value) => RegExp(
    r'(?:\bcity$|^city\s+of\s|^municipality\s+of\s)',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _isBarangay(String value) => RegExp(
    r'^(?:barangay|brgy\.?|bgy\.?)\s+',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _looksLikeStreet(String value) =>
      RegExp(
        r'\b(?:street|st\.?|road|rd\.?|avenue|ave\.?|drive|highway|lane|blvd\.?|boulevard)\b',
        caseSensitive: false,
      ).hasMatch(value) ||
      RegExp(r'^#?\d+\s+\S').hasMatch(value);

  static bool _looksLikeProvince(String value) => RegExp(
    r'\b(?:province|norte|sur|oriental|occidental|metro manila)\b',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _isNumericHouse(String value) =>
      RegExp(r'^#?\d+[A-Za-z]?(?:[-/]\w+)?$').hasMatch(value);

  static bool _isHouseOnly(String value) => value
      .split(',')
      .every(
        (piece) => RegExp(
          r'^(?:#?\d+[A-Za-z]?(?:[-/]\w+)?|(?:unit|apt\.?|apartment|house|lot|block|blk\.?|building|bldg\.?)\s+\S+(?:\s+(?:lot|block|blk\.?)\s+\S+)*)$',
          caseSensitive: false,
        ).hasMatch(piece.trim()),
      );

  static bool _isAdditionalDetail(String value) => RegExp(
    r'(?:\bdistrict\b|\bregion\b|^(?:near|beside|behind|opposite|in front of)\b)',
    caseSensitive: false,
  ).hasMatch(value);

  static bool _isCountry(String value) => const {
    'philippines',
    'the philippines',
    'republic of the philippines',
    'united states',
    'united states of america',
    'usa',
    'canada',
    'australia',
    'singapore',
    'malaysia',
    'indonesia',
    'thailand',
    'vietnam',
    'japan',
    'new zealand',
    'united kingdom',
    'great britain',
  }.contains(value.toLowerCase());
}
