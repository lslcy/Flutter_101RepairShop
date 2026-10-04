import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/customer_account_service.dart';
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

  // Get current customer profile, linking a counter-created customer row or
  // creating one on first sign-in (see CustomerAccountService).
  Future<Customer?> getCurrentCustomer() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    var data = await _accounts.resolveCurrentCustomer();

    if (data == null) return null;

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
      if (data == null) return null;
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
    final updated = await _supabase
        .from('customers')
        .update({...customer.toJson(), 'address': address})
        .eq('id', customer.id)
        .isFilter('deleted_at', null)
        .select('id');
    if (updated.isEmpty) {
      throw StateError('Your profile could not be saved. Please try again.');
    }
  }

  // Get customer appliances (archived appliances are hidden)
  Future<List<Appliance>> getAppliances() async {
    final customer = await getCurrentCustomer();
    if (customer == null) return [];

    final data = await _supabase
        .from('appliances')
        .select()
        .eq('customer_id', customer.id)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return data.map(Appliance.fromJson).toList();
  }

  // Add a new appliance
  Future<void> addAppliance(Map<String, dynamic> applianceData) async {
    final customer = await getCurrentCustomer();
    if (customer == null) {
      throw StateError('Your profile is unavailable. Please sign in again.');
    }

    final status = applianceData['status']?.toString().trim() ?? '';
    await _supabase.from('appliances').insert({
      ...applianceData,
      'customer_id': customer.id,
      'status': status.isEmpty ? Appliance.defaultStatus : status,
      'appliance_size': Appliance.normalizeSize(
        applianceData['appliance_size'] as String?,
      ),
    });
  }
}
