import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

Future<void> addReceivedMessage(
    String pubKey, String globalKey, String message, int timeStamp) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  Map<String, dynamic> receivedMessage = {
    'type': 'received',
    'global_key': globalKey,
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
    'global_key': globalKey,
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
