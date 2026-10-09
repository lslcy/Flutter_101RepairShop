import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
import '../../../core/validation/customer_identity.dart';
import '../../shared/models/customer.dart';

/// External sign-ins collect the same required details as email registration.
/// Profile creation stays on the server and can only target auth.uid().
class SignInProfileService {
  SignInProfileService(this.client);
  final SupabaseClient client;

  Future<Customer?> load() async {
    final row = await CustomerAccountService(supabase: client)
        .resolveCurrentCustomer();
    return row == null ? null : Customer.fromJson(row);
  }

  Future<void> complete({
    required String firstName,
    required String lastName,
    required String address,
  }) async {
    if (firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        address.trim().isEmpty) {
      throw ArgumentError('Enter your name and address to continue.');
    }
    final nameError =
        CustomerIdentity.validateName(firstName, fieldName: 'first name') ??
        CustomerIdentity.validateName(lastName, fieldName: 'last name');
    if (nameError != null) throw ArgumentError(nameError);
    if (client.auth.currentUser == null) {
      throw const AuthException('Sign in again to save your details.');
    }
    await client
        .rpc(
          'complete_customer_profile',
          params: {
            'p_first_name': CustomerIdentity.normalizeName(firstName),
            'p_last_name': CustomerIdentity.normalizeName(lastName),
            'p_address': address.trim(),
          },
        )
        .timeout(const Duration(seconds: 15));
  }

  static bool isComplete(Customer? customer) =>
      customer != null &&
      (customer.firstName?.trim().isNotEmpty ?? false) &&
      (customer.lastName?.trim().isNotEmpty ?? false) &&
      (customer.address?.trim().isNotEmpty ?? false);

  static bool isExternalUser(User? user) {
    final providers = user?.appMetadata['providers'];
    final provider = user?.appMetadata['provider'];
    return provider == 'google' ||
        provider == 'phone' ||
        (providers is List &&
            (providers.contains('google') || providers.contains('phone')));
  }
}
