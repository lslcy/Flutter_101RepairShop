import 'package:supabase_flutter/supabase_flutter.dart';

/// Finds the `customers` row that belongs to the signed-in Supabase user.
///
/// Direct customer access is limited to the user's own row
/// (`auth_id = auth.uid()`); the app has no customer INSERT policy.
/// The signup trigger creates an owned row from registration metadata. External
/// users finish setup through the verified `complete_customer_profile` RPC.
/// Neither this lookup nor profile completion links a different customer's row
/// by an email or phone entered in a form.
///
/// The customer's own `id` (uuid) must be used for every `customer_id`
/// foreign key, never the auth user id.
class CustomerAccountService {
  CustomerAccountService({
    SupabaseClient? supabase,
    this.lookupTimeout = const Duration(seconds: 15),
  }) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  final Duration lookupTimeout;

  // Screens load several repositories at once; share one lookup per user.
  static final _inFlight = <String, Future<Map<String, dynamic>?>>{};

  /// Active customer row for the current user. Returns `null` when signed
  /// out, when the trigger has not created the row, or when staff archived it.
  Future<Map<String, dynamic>?> resolveCurrentCustomer() {
    final user = _supabase.auth.currentUser;
    if (user == null) return Future.value(null);
    final key = '${identityHashCode(_supabase)}:${user.id}';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    // Bound the shared future itself so a stalled request cannot make every
    // later retry wait on the same lookup after the screen has timed out.
    late final Future<Map<String, dynamic>?> future;
    future = findActiveCustomer(user.id)
        .timeout(lookupTimeout)
        .whenComplete(() {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        });
    _inFlight[key] = future;
    return future;
  }

  /// Customer uuid for `customer_id` foreign keys, or `null` if unavailable.
  Future<String?> currentCustomerId() async =>
      (await resolveCurrentCustomer())?['id'] as String?;

  /// Like [resolveCurrentCustomer] but throws instead of returning `null`:
  /// [StateError] when signed out, [CustomerAccountMissingException] when no
  /// active customer row exists for the signed-in user.
  Future<Map<String, dynamic>> requireCurrentCustomer() async {
    if (_supabase.auth.currentUser == null) {
      throw StateError('Please sign in again.');
    }
    final row = await resolveCurrentCustomer();
    if (row == null) throw CustomerAccountMissingException();
    return row;
  }

  /// Customer uuid, throwing like [requireCurrentCustomer].
  Future<String> requireCustomerId() async =>
      (await requireCurrentCustomer())['id'] as String;

  /// Active (not soft-deleted) customer row linked to [authId].
  Future<Map<String, dynamic>?> findActiveCustomer(
    String authId, {
    String columns = '*',
  }) async {
    final rows = await _supabase
        .from('customers')
        .select(columns)
        .eq('auth_id', authId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }
}

/// No `customers` row with `auth_id = auth.uid()` (not created yet by the
/// sign-up trigger, or archived by staff). Screens show [message] instead of
/// crashing.
class CustomerAccountMissingException implements Exception {
  CustomerAccountMissingException();

  static const text = 'Your account is being set up. Please contact the shop.';

  String get message => text;

  @override
  String toString() => text;
}
