import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> displayNotification(
    String title, String message, int index) async {
  print('received');
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails('your_channel_id', 'your_channel_name',
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
