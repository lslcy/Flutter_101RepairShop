import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';

final addressLocationServiceProvider = Provider<AddressLocationService>((ref) {
  return AddressLocationService();
});

enum LocationRecoveryAction { none, appSettings, locationSettings }

class AddressLocationException implements Exception {
  const AddressLocationException(
    this.message, {
    this.recoveryAction = LocationRecoveryAction.none,
  });

  final String message;
  final LocationRecoveryAction recoveryAction;

  @override
  String toString() => message;
}

/// Looks up a single address only when the user asks to use their location.
class AddressLocationService {
  AddressLocationService({
    GeolocatorPlatform? geolocator,
    Future<List<geocoding.Placemark>> Function(double, double)? reverseGeocode,
    bool? platformSupported,
    this.positionTimeout = const Duration(seconds: 20),
    this.geocodingTimeout = const Duration(seconds: 10),
  }) : _geolocator = geolocator ?? GeolocatorPlatform.instance,
       _reverseGeocode = reverseGeocode ?? _nativeReverseGeocode,
       isSupported =
           platformSupported ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS));

  final GeolocatorPlatform _geolocator;
  final Future<List<geocoding.Placemark>> Function(double, double)
  _reverseGeocode;
  final bool isSupported;
  final Duration positionTimeout;
  final Duration geocodingTimeout;

  Future<String> getCurrentAddress() async {
    if (!isSupported) {
      throw const AddressLocationException(
        'Phone location is available in the Android and iPhone apps. '
        'Please enter your address manually here.',
      );
    }

    try {
      if (!await _geolocator.isLocationServiceEnabled().timeout(
        positionTimeout,
      )) {
        throw const AddressLocationException(
          'Location services are off. Turn them on or enter your address manually.',
          recoveryAction: LocationRecoveryAction.locationSettings,
        );
      }
      var permission = await _geolocator.checkPermission().timeout(
        positionTimeout,
      );
      if (permission == LocationPermission.denied) {
        // Allow the user time to respond to the system permission prompt.
        permission = await _geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const AddressLocationException(
          'Location access is blocked. Allow it in app settings or '
          'enter your address manually.',
          recoveryAction: LocationRecoveryAction.appSettings,
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const AddressLocationException(
          'Location permission was not granted. You can try again or '
          'enter your address manually.',
        );
      }

      final position = await _geolocator
          .getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: positionTimeout,
            ),
          )
          .timeout(positionTimeout);
      final placemarks = await _reverseGeocode(
        position.latitude,
        position.longitude,
      ).timeout(geocodingTimeout);

      for (final placemark in placemarks) {
        final address = _formatAddress(placemark);
        if (address != null) return address;
      }
      throw const AddressLocationException(
        'We found your location but could not find a street address. '
        'Please enter your complete address manually.',
      );
    } on AddressLocationException {
      rethrow;
    } on LocationServiceDisabledException {
      throw const AddressLocationException(
        'Location services are off. Turn them on or enter your address manually.',
        recoveryAction: LocationRecoveryAction.locationSettings,
      );
    } on PermissionDeniedException {
      throw const AddressLocationException(
        'Location access is unavailable. Allow it in app settings or '
        'enter your address manually.',
        recoveryAction: LocationRecoveryAction.appSettings,
      );
    } on TimeoutException {
      throw const AddressLocationException(
        'Finding your address took too long. Try again or enter it manually.',
      );
    } on Exception {
      throw const AddressLocationException(
        'We could not find your address right now. '
        'Check your connection and try again, or enter it manually.',
      );
    }
  }

  Future<bool> openAppSettings() async {
    if (!isSupported) return false;
    try {
      return await _geolocator.openAppSettings().timeout(positionTimeout);
    } on Exception {
      return false;
    }
  }

  Future<bool> openLocationSettings() async {
    if (!isSupported) return false;
    try {
      return await _geolocator.openLocationSettings().timeout(positionTimeout);
    } on Exception {
      return false;
    }
  }

  static Future<List<geocoding.Placemark>> _nativeReverseGeocode(
    double latitude,
    double longitude,
  ) async {
    if (geocoding.GeocodingPlatformFactory.instance == null) {
      throw const AddressLocationException(
        'Address lookup is unavailable on this device. '
        'Please enter your address manually.',
      );
    }
    return geocoding.Geocoding().placemarkFromCoordinates(latitude, longitude);
  }

  static String? _formatAddress(geocoding.Placemark placemark) {
    final thoroughfare = _clean(placemark.thoroughfare);
    final streetNumber = _clean(placemark.subThoroughfare);
    var street = _clean(placemark.street);
    if (street == null || !_hasDetail(street)) {
      street = [streetNumber, thoroughfare].whereType<String>().join(' ');
    } else if (thoroughfare != null &&
        streetNumber != null &&
        street.toLowerCase() == thoroughfare.toLowerCase()) {
      street = '$streetNumber $street';
    }

    // City/country or raw coordinates alone cannot fill a required address.
    final hasLocalDetail =
        _hasDetail(street) || _hasDetail(placemark.subLocality);
    final hasArea = [
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
    ].any(_hasDetail);
    if (!hasLocalDetail || !hasArea) return null;

    final parts = <String>[];
    final seen = <String>{};
    for (final value in [
      street,
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.postalCode,
      placemark.country,
    ]) {
      for (final component in (value ?? '').split(',')) {
        final part = _clean(component);
        if (part != null && seen.add(part.toLowerCase())) parts.add(part);
      }
    }
    return parts.join(', ');
  }

  static String? _clean(String? value) {
    final cleaned = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static bool _hasDetail(String? value) {
    final cleaned = _clean(value);
    return cleaned != null &&
        !RegExp(r'^[\d\s.,+\-\u00b0\u2032\u2033/()]+$').hasMatch(cleaned);
  }
}
