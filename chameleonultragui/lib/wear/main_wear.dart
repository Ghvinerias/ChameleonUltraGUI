import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/wear/app.dart';
import 'package:chameleonultragui/wear/connection/wear_connection.dart';
import 'package:chameleonultragui/wear/services/wear_services.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = SharedPreferencesProvider();
  await prefs.load();
  final connection = WearConnection()..attach();
  runApp(
    WearServicesScope(
      services: WearServices(prefs: prefs, connection: connection),
      child: const WearApp(),
    ),
  );
}
