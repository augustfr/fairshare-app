import 'dart:convert';

import 'package:fairshare/pages/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'friends.dart';

Future onNotificationClick(BuildContext context, String? payload) async {
  if (payload == null) {
    return;
  }
  final friendIndex = int.parse(payload);
  List<String> friendsList = await loadFriends();
  if (friendsList.isEmpty) {
    return;
  }

  if (friendsList.length < friendIndex + 1) {
    return;
  }

  final friend = friendsList[friendIndex];
  Map<String, dynamic> decodedFriend =
      jsonDecode(friend) as Map<String, dynamic>;
  String name = decodedFriend['name'];
  String privateKey = decodedFriend['privateKey'];

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ChatPage(
        friendName: name,
        sharedKey: privateKey,
        friendIndex: friendIndex,
      ),
    ),
  );
}

Future<void> initializeNotifications(BuildContext context) async {
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
    onSelectNotification: (String? payload) =>
        onNotificationClick(context, payload),
  );
}

Future<void> displayNotification(
    String title, String message, int index) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
          'com.august.FairShare.message_notifications', 'Message Notifications',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          autoCancel: true,
          enableLights: true,
          enableVibration: true,
          ticker: 'ticker');
  const IOSNotificationDetails iOSPlatformChannelSpecifics =
      IOSNotificationDetails();
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics);
  await flutterLocalNotificationsPlugin.show(
    index, // Notification ID
    title, // Notification title
    message, // Notification message
    platformChannelSpecifics, // Notification details
    payload: index.toString(),
  );
}
