import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import '../main.dart';

import 'dart:convert';

final _lock = Lock();

Future<void> addReceivedMessage(
    String pubKey, String globalKey, String message, int timeStamp) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  Map<String, dynamic> receivedMessage = {
    'type': 'received',
    'globalKey': globalKey,
    'message': message.trim(),
    'timestamp': timeStamp,
  };

  String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
  Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

  List<dynamic> messagesHistory = messagesHistoryMap[pubKey] ?? [];
  messagesHistory.add(receivedMessage);

  messagesHistoryMap[pubKey] = messagesHistory;
  prefs.setString('messagesHistory', jsonEncode(messagesHistoryMap));
}

Future<void> addSentMessage(
    String pubKey, String globalKey, String message, int timeStamp) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  Map<String, dynamic> sentMessage = {
    'type': 'sent',
    'globalKey': globalKey,
    'message': message.trim(),
    'timestamp': timeStamp,
  };

  String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
  Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

  List<dynamic> messagesHistory = messagesHistoryMap[pubKey] ?? [];
  messagesHistory.add(sentMessage);

  messagesHistoryMap[pubKey] = messagesHistory;
  prefs.setString('messagesHistory', jsonEncode(messagesHistoryMap));
}

Future<void> addSentImage(
    String pubKey, String globalKey, String base64Image, int timeStamp) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  Map<String, dynamic> sentImage = {
    'type': 'sent',
    'media': 'image',
    'globalKey': globalKey,
    'image': base64Image.trim(),
    'timestamp': timeStamp,
  };

  String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
  Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

  List<dynamic> messagesHistory = messagesHistoryMap[pubKey] ?? [];
  messagesHistory.add(sentImage);

  messagesHistoryMap[pubKey] = messagesHistory;
  prefs.setString('messagesHistory', jsonEncode(messagesHistoryMap));
}

Future<void> addReceivedImage(
    String pubKey, String globalKey, String base64Image, int timeStamp) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  Map<String, dynamic> sentImage = {
    'type': 'received',
    'media': 'image',
    'globalKey': globalKey,
    'image': base64Image.trim(),
    'timestamp': timeStamp,
  };

  String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
  Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

  List<dynamic> messagesHistory = messagesHistoryMap[pubKey] ?? [];
  messagesHistory.add(sentImage);

  messagesHistoryMap[pubKey] = messagesHistory;
  prefs.setString('messagesHistory', jsonEncode(messagesHistoryMap));
}

Future<void> clearMessageHistory(String pubKey) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
    Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

    messagesHistoryMap.remove(pubKey);
    prefs.setString('messagesHistory', jsonEncode(messagesHistoryMap));
  });
}
