import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_dates.dart';

/// Links the signed-in Supabase auth user to exactly one `customers` row.
///
/// Staff often create the customer at the counter (in the Laravel admin)
/// before the customer signs up, so that row has no `auth_id` yet. Resolution
/// order:
///   1. an active row where `auth_id = currentUser.id`;
///   2. an active, unlinked row whose email matches (case-insensitive), which
///      is claimed by setting `auth_id`;
///   3. otherwise a new row is inserted, always with `auth_id` set.
///
/// The customer's own `id` (uuid) must be used for every `customer_id`
/// foreign key, never the auth user id.
class CustomerAccountService {
  CustomerAccountService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  // Screens load several repositories at once; share one resolution per user
  // so concurrent first loads can never insert duplicate customer rows.
  static final _inFlight = <String, Future<Map<String, dynamic>?>>{};

  /// Active customer row for the current user, linking or creating it when
  /// needed. Returns `null` when signed out or when staff archived the account.
  Future<Map<String, dynamic>?> resolveCurrentCustomer() {
    final user = _supabase.auth.currentUser;
    if (user == null) return Future.value(null);
    final key = '${identityHashCode(_supabase)}:${user.id}';
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = _resolve(user).whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = future;
    return future;
  }

  /// Customer uuid for `customer_id` foreign keys.
  Future<String?> currentCustomerId() async =>
      (await resolveCurrentCustomer())?['id'] as String?;

  /// Active (not soft-deleted) customer row already linked to [authId].
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

  Future<Map<String, dynamic>?> _resolve(User user) async {
    final linked = await findActiveCustomer(user.id);
    if (linked != null) return linked;

    // An archived account is still linked to this auth user. Never create a
    // second row for it; staff must restore the archived customer instead.
    final archived = await _supabase
        .from('customers')
        .select('id')
        .eq('auth_id', user.id)
        .limit(1);
    if (archived.isNotEmpty) return null;

    final email = user.email?.trim() ?? '';
    // Only claim counter-created rows once the email address is verified, so
    // nobody can take over a customer's history by signing up with their email.
    if (email.isNotEmpty && user.emailConfirmedAt != null) {
      final claimed = await _claimByEmail(user.id, email);
      if (claimed != null) return claimed;
    }

    return _insert(user, email);
  }

  Future<Map<String, dynamic>?> _claimByEmail(
    String authId,
    String email,
  ) async {
    final candidates = await _supabase
        .from('customers')
        .select('id')
        .isFilter('auth_id', null)
        .isFilter('deleted_at', null)
        .ilike('email', _escapeLike(email))
        .order('created_at', ascending: true)
        .limit(1);
    if (candidates.isEmpty) return null;

    // `auth_id is null` keeps the claim atomic if two devices race.
    final claimed = await _supabase
        .from('customers')
        .update({
          'auth_id': authId,
          'updated_at': AppDates.toTimestampString(DateTime.now()),
        })
        .eq('id', candidates.first['id'] as String)
        .isFilter('auth_id', null)
        .select();
    if (claimed.isNotEmpty) return claimed.first;

    // Lost a race (or the write was denied): use whatever is linked now.
    return findActiveCustomer(authId);
  }

  Future<Map<String, dynamic>?> _insert(User user, String email) async {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    String? meta(String key) {
      final value = metadata[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final now = AppDates.toTimestampString(DateTime.now());
    try {
      return await _supabase
          .from('customers')
          .insert({
            'auth_id': user.id,
            'email': email.isEmpty ? null : email,
            'first_name': meta('first_name'),
            'last_name': meta('last_name'),
            'phone_no': meta('phone_no'),
            'address': meta('address'),
            'created_at': now,
            'updated_at': now,
          })
          .select()
          .single();
    } on PostgrestException catch (error) {
      // A unique constraint or database trigger may have created the row
      // between our lookup and insert; reuse it instead of failing.
      final existing = await findActiveCustomer(user.id);
      if (existing != null) return existing;
      debugPrint('Customer profile could not be created: ${error.message}');
      rethrow;
    }
  }

  // `ilike` treats `%` and `_` as wildcards; match the email literally.
  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
