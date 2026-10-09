import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Checks public provider configuration before opening Google's browser flow.
/// Results are read each time so a newly enabled provider works immediately.
class AuthProviderSettings {
  AuthProviderSettings({
    required this.endpoint,
    required this.publicKey,
    this.httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  });

  final Uri endpoint;
  final String publicKey;
  final http.Client? httpClient;
  final Duration requestTimeout;

  Future<void> requireGoogleSignIn() async {
    final client = httpClient ?? http.Client();
    try {
      final response = await client
          .get(endpoint, headers: {'apikey': publicKey})
          .timeout(requestTimeout);
      if (response.statusCode != 200) throw _unavailable();
      final Object? settings;
      try {
        settings = jsonDecode(response.body);
      } on FormatException {
        throw _unavailable();
      }
      final external = settings is Map ? settings['external'] : null;
      final google = external is Map ? external['google'] : null;
      if (google == false) {
        throw const AuthException(
          'Google provider is not enabled.',
          code: 'provider_disabled',
        );
      }
      if (google != true) throw _unavailable();
    } finally {
      // Injected clients belong to their caller; owned clients close even if a
      // request fails or times out. A later attempt creates a fresh client.
      if (httpClient == null) client.close();
    }
  }

  AuthException _unavailable() => const AuthException(
    'Google sign-in is temporarily unavailable. Please try again.',
    code: 'provider_unavailable',
  );
}
