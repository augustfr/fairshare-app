import 'package:fairshare/providers/chat.dart';
import 'package:fairshare/providers/friend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_config_plus/flutter_config_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/home_page.dart';

void sendApiKeyToNative() {
  const platform = MethodChannel('mapsApiKeyChannel');
  platform.invokeMethod(
      'setApiKey', {'apiKey': FlutterConfigPlus.get('GOOGLE_MAPS_API_KEY')});
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
  await FlutterConfigPlus.loadEnvVariables();
  sendApiKeyToNative();
  await SharedPreferencesHelper().init();
  await Geolocator.checkPermission();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (BuildContext context) => ChatProvider(),
        ),
        ChangeNotifierProvider(
          create: (BuildContext context) => FriendProvider(),
        ),
      ],
      child: MaterialApp(
        title: 'FairShare',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const HomePage(),
      ),
    );
  }
}
