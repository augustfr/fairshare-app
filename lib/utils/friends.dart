import '../pages/qr_scanner.dart';
import '../pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import '../utils/nostr.dart';
import 'package:synchronized/synchronized.dart';
import './messages.dart';
import '../main.dart';

final _lock = Lock();

Future<List<String>> loadFriends() async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String> friendsList = [];

  friendsList = prefs.getStringList('friends') ?? [];

  return friendsList;
}

Future<bool> addFriend(String rawData, String? photoPath) async {
  final Map<String, dynamic> friendData = jsonDecode(rawData);

  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  String? privateKey;

  if (friendData['privateKey'] == null) {
    privateKey = prefs.getString('cycling_priv_key');
  } else {
    privateKey = friendData['privateKey'];
  }

  List<String> friendsList = [];

  await _lock.synchronized(() async {
    friendsList = prefs.getStringList('friends') ?? [];
    List<String> subscribedKeys = prefs.getStringList('subscribed_keys') ?? [];
    subscribedKeys.add(getPublicKey(privateKey));
    // Check if the friend is already in the list
    for (String friend in friendsList) {
      final Map<String, dynamic> existingFriend = jsonDecode(friend);
      if (existingFriend['privateKey'] == privateKey) {
        return false; // Friend is already in the list
      }
    }

    // Add the photo path to the friend data
    if (photoPath != null) {
      friendData['photoPath'] = photoPath;
    }
    friendsList.add(jsonEncode(friendData));

    int timestamp = DateTime.now().millisecondsSinceEpoch;
    int secondsTimestamp = (timestamp / 1000).round();

    await prefs.setStringList('subscribed_keys', subscribedKeys);
    await prefs.setStringList('friends', friendsList);
    await prefs.setString('cycling_pub_key', '');
    await setLatestLocationUpdate(secondsTimestamp, getPublicKey(privateKey));
    scannedPubKey = '';
    needsUpdate = true;
  });

  Vibrate.feedback(FeedbackType.success);
  needsUpdate = true;
  return true; // Friend added successfully
}

Future<void> setLatestReceivedEvent(int createdAt, String pubKey) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    String? jsonString = prefs.getString('latestEventTimestamps');
    if (jsonString != null) {
      latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
    }
    latestEventTimestamps[pubKey] = createdAt;
    String newString = json.encode(latestEventTimestamps);
    await prefs.setString('latestEventTimestamps', newString);
  });
}

Future<void> setLatestLocationUpdate(int createdAt, String pubKey) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  String? jsonString = prefs.getString('latestLocationTimestamps');
  if (jsonString != null) {
    latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
  }
  latestEventTimestamps[pubKey] = createdAt;
  String newString = json.encode(latestEventTimestamps);
  await prefs.setString('latestLocationTimestamps', newString);
}

Future<int?> getLatestLocationUpdate(String pubKey) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  String? jsonString = prefs.getString('latestLocationTimestamps');
  if (jsonString != null) {
    latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
  }
  return latestEventTimestamps[pubKey];
}

Future<int?> getLatestReceivedEvent(String pubKey) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  String? jsonString = prefs.getString('latestEventTimestamps');
  if (jsonString != null) {
    latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
  }
  return latestEventTimestamps[pubKey];
}

Future<void> removeLatestReceivedEvent(String pubKey) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  String? jsonString = prefs.getString('latestEventTimestamps');
  if (jsonString != null) {
    latestEventTimestamps = json.decode(jsonString) as Map<String, dynamic>;
    latestEventTimestamps.remove(pubKey);
    String newString = json.encode(latestEventTimestamps);
    await prefs.setString('latestEventTimestamps', newString);
  }
}

Future<void> cleanSubscriptions() async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    await prefs.remove('friends_subscription_id');
    List<String> friendsList = prefs.getStringList('friends') ?? [];
    List<String> subscribedKeys = prefs.getStringList('subscribed_keys') ?? [];
    bool modified = false;
    List<String> keysToRemove = [];

    Set<String> friendsPubKeys = friendsList
        .map((friend) => getPublicKey(jsonDecode(friend)['privateKey']))
        .toSet();

    for (final key in subscribedKeys) {
      if (!friendsPubKeys.contains(key)) {
        keysToRemove.add(key);
        modified = true;
      }
    }

    if (modified) {
      subscribedKeys.removeWhere((key) => keysToRemove.contains(key));
      await prefs.setStringList('subscribed_keys', subscribedKeys);
    }
  });
}

Future<void> removeFriend(int index) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
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
    await removeLatestReceivedEvent(pubKey);
    await clearMessageHistory(pubKey);
    needsUpdate = true;
  });
}

Future<void> removeAllFriends() async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  await _lock.synchronized(() async {
    await prefs.remove('subscribed_keys');
    await prefs.remove('friends');
    await prefs.remove('latestEventTimestamps');
    await prefs.remove('messagesHistory');
  });
  needsUpdate = true;
}

Future<List<int>> checkForUnreadMessages(friendsList) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;

  List<int> friendsWithUnreadMessages = [];
  for (int i = 0; i < friendsList.length; i++) {
    Map<String, dynamic> decodedFriend =
        jsonDecode(friendsList[i]) as Map<String, dynamic>;
    String publicKey = getPublicKey(decodedFriend['privateKey']);
    List<dynamic> messagesHistory = [];
    String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
    Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

    if (messagesHistoryMap.containsKey(publicKey)) {
      messagesHistory = messagesHistoryMap[publicKey] as List<dynamic>;
    }
    if (messagesHistory.isNotEmpty) {
      if (messagesHistory.last['type'] == 'received') {
        int currentMessageTimestamp = messagesHistory.last['timestamp'];
        if (currentMessageTimestamp >
            (decodedFriend['latestSeenMessage'] ?? 0)) {
          decodedFriend['hasUnreadMessages'] = true;
          friendsWithUnreadMessages.add(i);
        } else {
          decodedFriend['hasUnreadMessages'] = false;
        }
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
