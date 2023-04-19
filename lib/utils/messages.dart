import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import 'dart:convert';

final _lock = Lock();

Future<void> addReceivedMessage(
    String pubKey, String globalKey, String message, int timeStamp) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  Map<String, dynamic> receivedMessage = {
    'type': 'received',
    'globalKey': globalKey,
    'message': message.trim(),
    'timestamp': timeStamp,
  };

  List<dynamic> messagesHistory = [];
  if (prefs.getString(pubKey) != null) {
    messagesHistory = jsonDecode(prefs.getString(pubKey)!) as List<dynamic>;
  }

  messagesHistory.add(receivedMessage);
  prefs.setString(pubKey, jsonEncode(messagesHistory));
}

Future<void> addSentMessage(
    String pubKey, String globalKey, String message, int timeStamp) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  Map<String, dynamic> sentMessage = {
    'type': 'sent',
    'globalKey': globalKey,
    'message': message.trim(),
    'timestamp': timeStamp,
  };

  List<dynamic> messagesHistory = [];
  if (prefs.getString(pubKey) != null) {
    messagesHistory = jsonDecode(prefs.getString(pubKey)!) as List<dynamic>;
  }

  messagesHistory.add(sentMessage);
  prefs.setString(pubKey, jsonEncode(messagesHistory));
}

Future<void> clearMessageHistory(String pubKey) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove(pubKey);
  });
}
