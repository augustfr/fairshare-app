import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

Future onNotificationClick(String? payload) async {
  print('Notification clicked with payload: $payload');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const IOSInitializationSettings initializationSettingsIOS =
      IOSInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid, iOS: initializationSettingsIOS);
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onSelectNotification: onNotificationClick,
  );

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
