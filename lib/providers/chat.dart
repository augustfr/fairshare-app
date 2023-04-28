import 'dart:convert';

import 'package:fairshare/pages/chat_page.dart';
import 'package:fairshare/utils/nostr.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

class ChatProvider extends ChangeNotifier {
  String? shareKey;
  int? friendIndex;
  List<Message> messages = [];

  void init(String key, int index) {
    shareKey = key;
    friendIndex = index;
    notifyListeners();
  }

  Future<void> load() async {
    if (shareKey == null || friendIndex == null) return;
    List<Message> fetchedMessages = [];
    String publicKey = getPublicKey(shareKey);

    // Fetch messages from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
    Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);
    if (messagesHistoryMap.containsKey(publicKey)) {
      List<dynamic> messagesHistory =
          messagesHistoryMap[publicKey] as List<dynamic>;
      DateTime? previousDate;
      DateTime? previousShownTimestamp;

      for (var message in messagesHistory) {
        DateTime currentMessageDate =
            DateTime.fromMillisecondsSinceEpoch(message['timestamp'] * 1000);
        bool showDate = false;
        bool showTime = false;

        if (previousDate == null ||
            currentMessageDate.day != previousDate.day ||
            currentMessageDate.month != previousDate.month ||
            currentMessageDate.year != previousDate.year) {
          showDate = true;
          showTime = true;
          previousShownTimestamp = currentMessageDate;
        }

        if (previousShownTimestamp == null ||
            currentMessageDate.difference(previousShownTimestamp).inMinutes >=
                10) {
          showTime = true;
          previousShownTimestamp = currentMessageDate;
        }
        fetchedMessages.add(Message(
            type: message['type'], // 'sent' or 'received'
            media: message['media'] == 'image'
                ? 'image'
                : null, // 'image' for images, null for text messages
            text: message['media'] == 'text'
                ? message['message']
                : message['media'] == null
                    ? message['message']
                    : null, // set to 'message' if media is null (text message)
            image: message['media'] == 'image' ? message['image'] : null,
            globalKey: message['globalKey'],
            timestamp: message['timestamp'],
            showDate: showDate, // Set showDate property based on comparison
            showTime:
                showTime)); // Set showTime property based on time difference

        previousDate = currentMessageDate;
      }
    }

    // Sort messages by timestamp
    fetchedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    // Clear existing messages and update UI with the fetched messages

    messages.clear();
    messages.addAll(fetchedMessages);

    if (fetchedMessages.isNotEmpty) {
      await Lock().synchronized(() async {
        int latestSeenMessageTimestamp = fetchedMessages.last.timestamp;
        List<String> friendsList = prefs.getStringList('friends') ?? [];
        Map<String, dynamic> friendData =
            jsonDecode(friendsList[friendIndex!]) as Map<String, dynamic>;
        friendData['latestSeenMessage'] = latestSeenMessageTimestamp;
        friendsList[friendIndex!] = json.encode(friendData);
        await prefs.setStringList('friends', friendsList);
        // needsUpdate = true;
        // needsChatListUpdate = true;
      });
    }

    notifyListeners();
  }

  void clear() {
    shareKey = null;
    friendIndex = null;
    messages.clear();
    notifyListeners();
  }
}
