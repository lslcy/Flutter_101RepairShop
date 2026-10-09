import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/notification_service.dart';
import 'features/auth/data/auth_flow_controller.dart';

// App entry point - initializes Supabase then launches app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/Roboto-LICENSE.txt'));
  });

  await Supabase.initialize(
    authOptions: FlutterAuthClientOptions(
      persistSession: true,
      detectSessionInUriPredicate: AuthCallbackTracker.detect,
    ),
    postgrestOptions: const PostgrestClientOptions(
      requestTimeout: Duration(seconds: 15),
    ),
    url: AppConfig.supabaseUrl,
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95emFha2hnYnJnc3NwdWFzcmNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNzAxNjIsImV4cCI6MjEwNTg0NjE2Mn0.rymut2ITkElkMtFJ8ykF910Q6PAx0xjryWIemId1UIU',
  );

  try {
    await NotificationService.instance.init();
  } catch (error) {
    debugPrint('Notification initialization unavailable: $error');
  }

  runApp(const ProviderScope(child: RepairShopApp()));

  // Keep reminders scoped to the current account and appointment status.
  NotificationService.instance.startSessionSync();
}
