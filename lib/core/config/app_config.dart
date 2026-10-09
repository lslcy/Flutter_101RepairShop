// Shared service URLs and build-time Laravel configuration.
//
// Provide values with `--dart-define`, for example:
//   flutter run --dart-define=LARAVEL_BASE_URL=https://admin.101repairshop.com
// or keep them in a JSON file and use `--dart-define-from-file=config.json`.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = 'https://oyzaakhgbrgsspuasrcb.supabase.co';

  /// Root URL of the Laravel web admin (no trailing slash required).
  /// Used to resolve files uploaded from the web admin, such as
  /// `storage/customer-profiles/abc.jpg`.
  static const laravelBaseUrl = String.fromEnvironment('LARAVEL_BASE_URL');

  /// Turns a stored media value into a loadable URL.
  ///
  /// Full URLs (Supabase Storage, `http...`) are returned unchanged. Relative
  /// paths from the web admin are prefixed with [laravelBaseUrl]. Returns
  /// `null` when there is nothing loadable, so callers can show a placeholder.
  static String? resolveMediaUrl(String? value, {String? baseUrl}) {
    final path = value?.trim() ?? '';
    if (path.isEmpty) return null;
    if (path.toLowerCase().startsWith('http')) return path;

    var base = (baseUrl ?? laravelBaseUrl).trim();
    if (base.isEmpty) return null;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    var relative = path;
    while (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    return '$base/$relative';
  }
}
