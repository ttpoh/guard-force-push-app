import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final boot = await bootstrap();
  runApp(MyApp(initialSettings: boot.settings));
}
