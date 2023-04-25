import 'package:fairshare/utils/notification_helper.dart';
import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_config/flutter_config.dart';
import 'package:flutter/services.dart';

void sendApiKeyToNative() {
  const platform = MethodChannel('mapsApiKeyChannel');
  platform.invokeMethod(
      'setApiKey', {'apiKey': FlutterConfig.get('GOOGLE_MAPS_API_KEY')});
}

class SharedPreferencesHelper {
  static final SharedPreferencesHelper _instance =
      SharedPreferencesHelper._internal();
  late SharedPreferences prefs;

  factory SharedPreferencesHelper() {
    return _instance;
  }

  SharedPreferencesHelper._internal();

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterConfig.loadEnvVariables();
  sendApiKeyToNative();
  await initializeNotifications();
  await SharedPreferencesHelper().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FairShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}
