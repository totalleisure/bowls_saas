import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'secrets.dart';
import 'App/app.dart'; // <-- this assumes you have lib/App/app.dart

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    debugPrintStack(stackTrace: details.stack, label: 'FLUTTER ERROR STACK');
  };

  await Supabase.initialize(
    url: Secrets.supabaseUrl,
    anonKey: Secrets.supabaseAnonKey,
  );

  runApp(const BowlsApp());
}
