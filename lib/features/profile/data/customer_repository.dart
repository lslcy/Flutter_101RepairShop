import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
import '../../../core/validation/customer_identity.dart';
import '../../shared/models/customer.dart';
import '../../shared/models/appliance.dart';

// Provides the customer repository
final customerRepositoryProvider = Provider((ref) => CustomerRepository());

// Signals a successful profile save to screens kept alive by the app shell.
final customerProfileRevisionProvider = StateProvider<int>((ref) => 0);

// Handles customer profile and appliance data
class CustomerRepository {
  CustomerRepository({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client,
      _accounts = CustomerAccountService(
        supabase: supabase ?? Supabase.instance.client,
      );

  final SupabaseClient _supabase;
  final CustomerAccountService _accounts;

  // Get the current customer profile (created by the sign-up DB trigger).
  // Returns `null` only when signed out; throws
  // [CustomerAccountMissingException] when no active row exists yet.
  Future<Customer?> getCurrentCustomer() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    Map<String, dynamic>? data = await _accounts.requireCurrentCustomer();

    // Email confirmation may prevent a customer write during signup, and older
    // account-creation triggers may not copy the address from auth metadata.
    // Import it after sign-in only if the database address has never been set.
    final signupAddress = user.userMetadata?['address'];
    if (data['address'] == null &&
        signupAddress is String &&
        signupAddress.trim().isNotEmpty) {
      final saved = await _supabase
          .from('customers')
          .update({'address': signupAddress.trim()})
          .eq('id', data['id'] as String)
          .eq('auth_id', user.id)
          .isFilter('address', null)
          .isFilter('deleted_at', null)
          .select();

      // Another device may have saved or cleared the address since our read.
      // The conditional update preserves that choice; return the latest row.
      data = saved.isEmpty
          ? await _accounts.findActiveCustomer(user.id)
          : saved.first;
      if (data == null) throw CustomerAccountMissingException();
      if (data['address'] == null) {
        throw StateError('Your address could not be saved. Please try again.');
      }
    }

    return Customer.fromJson(data);
  }

  // Update customer profile
  Future<void> updateProfile(Customer customer) async {
    final address = customer.address?.trim() ?? '';
    if (address.isEmpty) {
      throw ArgumentError('An address is required to save your profile.');
    }
    final identityError =
        CustomerIdentity.validateName(
          customer.firstName,
          fieldName: 'first name',
        ) ??
        CustomerIdentity.validateName(
          customer.lastName,
          fieldName: 'last name',
        ) ??
        CustomerIdentity.validateEmail(customer.email, required: false) ??
        CustomerIdentity.validateOptionalPhone(customer.phoneNo);
    if (identityError != null) throw ArgumentError(identityError);
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in again to save your details.');
    }
    final email = CustomerIdentity.normalizeEmail(customer.email ?? '');
    final updated = await _supabase
        .from('customers')
        .update({
          ...customer.toJson(),
          'first_name': CustomerIdentity.normalizeName(customer.firstName!),
          'last_name': CustomerIdentity.normalizeName(customer.lastName!),
          'email': email.isEmpty ? null : email,
          'phone_no': CustomerIdentity.normalizeOptionalPhone(customer.phoneNo),
          'address': address,
        })
        .eq('id', customer.id)
        .eq('auth_id', user.id)
        .isFilter('deleted_at', null)
        .select('id');
    if (updated.isEmpty) {
      throw StateError('Your profile could not be saved. Please try again.');
    }
  }

  // Get customer appliances (archived appliances are hidden)
  Future<List<Appliance>> getAppliances() async {
    final customerId = await _accounts.requireCustomerId();

    final data = await _supabase
        .from('appliances')
        .select()
        .eq('customer_id', customerId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return data.map(Appliance.fromJson).toList();
  }

  /// Columns a customer may set when registering an appliance. Everything
  /// else (`date_in`, `warranty_end`, later statuses) is managed by staff.
  static const _applianceColumns = {
    'brand',
    'product',
    'model_no',
    'serial_no',
    'category',
    'appliance_size',
  };

  // Add a new appliance
  Future<void> addAppliance(Map<String, dynamic> applianceData) async {
    final customerId = await _accounts.requireCustomerId();

    final row = <String, dynamic>{
      for (final entry in applianceData.entries)
        if (_applianceColumns.contains(entry.key))
          entry.key: entry.value is String && entry.value.trim().isEmpty
              ? null
              : entry.value,
    };

    // RLS returns zero rows instead of an error when it blocks a write, so an
    // empty result is treated as a failure rather than a fake success.
    final inserted = await _supabase
        .from('appliances')
        .insert({
          ...row,
          'customer_id': customerId,
          'status': Appliance.defaultStatus,
          'appliance_size': Appliance.normalizeSize(
            row['appliance_size'] as String?,
          ),
        })
        .select('id');
    if (inserted.isEmpty) {
      throw StateError('Your appliance could not be saved. Please try again.');
    }
  }
}
