import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import '../utils/nostr.dart';
import 'package:synchronized/synchronized.dart';

final _lock = Lock();

Future<List<String>> loadFriends() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String> friendsList = [];

  friendsList = prefs.getStringList('friends') ?? [];

  return friendsList;
}

Future<bool> addFriend(String rawData, String? photoPath) async {
  final Map<String, dynamic> friendData = jsonDecode(rawData);
  SharedPreferences prefs = await SharedPreferences.getInstance();

  List<String> friendsList = [];

  await _lock.synchronized(() async {
    friendsList = prefs.getStringList('friends') ?? [];
  });

  // Check if the friend is already in the list
  for (String friend in friendsList) {
    final Map<String, dynamic> existingFriend = jsonDecode(friend);
    if (existingFriend['privateKey'] == friendData['privateKey']) {
      return false; // Friend is already in the list
    }
  }

  // Add the photo path to the friend data
  if (photoPath != null) {
    friendData['photoPath'] = photoPath;
  }

  friendsList.add(jsonEncode(friendData));
  print('new friends list:');
  print(friendsList);
  await _lock.synchronized(() async {
    await prefs.setStringList('friends', friendsList);
  });

  // Update friendsList variable stored in SharedPreferences
  await loadFriends();

  Vibrate.feedback(FeedbackType.success);
  return true; // Friend added successfully
}

Future<void> removeAllFriends() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.remove('friends');
}

Future<List<int>> checkForUnreadMessages(friendsList) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();

  List<int> friendsWithUnreadMessages = [];
  String myGlobalKey = prefs.getString('global_key') ?? '';
  for (int i = 0; i < friendsList.length; i++) {
    Map<String, dynamic> decodedFriend =
        jsonDecode(friendsList[i]) as Map<String, dynamic>;
    String publicKey = getPublicKey(decodedFriend['privateKey']);

    List<String> eventsList = await getPreviousEvents(
      publicKeys: [publicKey],
      friendIndex: i,
      markAsRead: false,
    );
    if (eventsList.isNotEmpty) {
      String globalKey = getGlobalKey(eventsList.first);
      if (globalKey != myGlobalKey) {
        int currentMessageTimestamp = getTimestamp(eventsList.first);
        if (currentMessageTimestamp > (decodedFriend['latestMessage'] ?? 0)) {
          decodedFriend['hasUnreadMessages'] = true;
          friendsWithUnreadMessages.add(i);
        }
      } else {
        decodedFriend['hasUnreadMessages'] = false;
      }
      friendsList[i] = json.encode(decodedFriend);
      // Update SharedPreferences
      await _lock.synchronized(() async {
        prefs.setStringList('friends', friendsList);
      });
    }
  }

  return friendsWithUnreadMessages;
}
