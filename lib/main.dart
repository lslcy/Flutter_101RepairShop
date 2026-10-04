import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

// App entry point - initializes Supabase then launches app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/Roboto-LICENSE.txt'));
  });

  await Supabase.initialize(
    url: 'https://oyzaakhgbrgsspuasrcb.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im95emFha2hnYnJnc3NwdWFzcmNiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyNzAxNjIsImV4cCI6MjEwNTg0NjE2Mn0.rymut2ITkElkMtFJ8ykF910Q6PAx0xjryWIemId1UIU',
  );

  runApp(const ProviderScope(child: RepairShopApp()));
}
