import '../pages/home_page.dart';
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
    List<String> subscribedKeys = prefs.getStringList('subscribed_keys') ?? [];
    subscribedKeys.add(getPublicKey(friendData['privateKey']));
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
    await prefs.setStringList('subscribed_keys', subscribedKeys);
    await prefs.setStringList('friends', friendsList);
    await prefs.setString('cycling_pub_key', '');
  });

  Vibrate.feedback(FeedbackType.success);
  needsUpdate = true;
  return true; // Friend added successfully
}

Future<void> setLatestReceivedEvent(int createdAt, String pubKey) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('latestEventTimestamps');
    if (jsonString != null) {
      latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
    }
    latestEventTimestamps[pubKey] = createdAt;
    String newString = json.encode(latestEventTimestamps);
    await prefs.setString('latestEventTimestamps', newString);
  });
}

Future<int?> getLatestReceivedEvent(String pubKey) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? jsonString = prefs.getString('latestEventTimestamps');
  if (jsonString != null) {
    latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
  }
  return latestEventTimestamps[pubKey];
}

Future<void> removeLatestReceivedEvent(String pubKey) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? jsonString = prefs.getString('latestEventTimestamps');
  if (jsonString != null) {
    latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
    latestEventTimestamps.remove(pubKey);
    String newString = json.encode(latestEventTimestamps);
    await prefs.setString('latestEventTimestamps', newString);
  }
}

Future<void> removeAllLatestEvents() async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove('latestEventTimestamps');
  });
}

Future<void> removeFriend(int index) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> friendsList = prefs.getStringList('friends') ?? [];
    List<String> subscribedKeys = prefs.getStringList('subscribed_keys') ?? [];
    String pubKey = getPublicKey(jsonDecode(friendsList[index])['privateKey']);

    // Check if pubKey exists in subscribedKeys and remove it if it does.
    if (subscribedKeys.contains(pubKey)) {
      subscribedKeys.remove(pubKey);
      await prefs.setStringList('subscribed_keys', subscribedKeys);
    }

    friendsList.removeAt(index);
    await prefs.setStringList('friends', friendsList);
    print('attempting to remove');
    await removeLatestReceivedEvent(pubKey);
    needsUpdate = true;
  });
}

Future<void> removeAllFriends() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.remove('subscribed_keys');
  await prefs.remove('friends');
  await removeAllLatestEvents();
  needsUpdate = true;
}

Future<List<int>> checkForUnreadMessages(friendsList) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();

  List<int> friendsWithUnreadMessages = [];
  String myGlobalKey = prefs.getString('global_key') ?? '';
  for (int i = 0; i < friendsList.length; i++) {
    Map<String, dynamic> decodedFriend =
        jsonDecode(friendsList[i]) as Map<String, dynamic>;
    String publicKey = getPublicKey(decodedFriend['privateKey']);

    // List<String> eventsList = await getPreviousEvents(
    //   publicKeys: [publicKey],
    //   friendIndex: i,
    //   markAsRead: false,
    // );
    // if (eventsList.isNotEmpty) {
    //   String globalKey = getGlobalKey(eventsList.first);
    //   if (globalKey != myGlobalKey) {
    //     int currentMessageTimestamp = getTimestamp(eventsList.first);
    //     if (currentMessageTimestamp > (decodedFriend['latestMessage'] ?? 0)) {
    //       decodedFriend['hasUnreadMessages'] = true;
    //       friendsWithUnreadMessages.add(i);
    //     }
    //   } else {
    //     decodedFriend['hasUnreadMessages'] = false;
    //   }
    //   friendsList[i] = json.encode(decodedFriend);
    //   // Update SharedPreferences
    //   await _lock.synchronized(() async {
    //     prefs.setStringList('friends', friendsList);
    //   });
    // }
  }

  return friendsWithUnreadMessages;
}
