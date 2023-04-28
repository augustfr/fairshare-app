import 'dart:async';
import 'dart:convert';

import 'package:fairshare/providers/friend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import 'package:tuple/tuple.dart';

import './messages.dart';
import '../main.dart';
import '../pages/qr_scanner.dart';
import '../utils/nostr.dart';

final _lock = Lock();

Future<List<String>> loadFriends() async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String> friendsList = [];

  friendsList = prefs.getStringList('friends') ?? [];

  return friendsList;
}

Future<List<String>> getFriendInfo(String pubKey) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String> friendsList = [];

  friendsList = prefs.getStringList('friends') ?? [];

  int index = friendsList.indexWhere(
      (friend) => getPublicKey(jsonDecode(friend)['privateKey']) == pubKey);

  if (index != -1) {
    final String friendName = jsonDecode(friendsList[index])['name'];
    final String privKey = jsonDecode(friendsList[index])['privateKey'];
    return [friendName, index.toString(), privKey];
  }

  return ['', '-1', ''];
}

Future<bool> addFriend(
    BuildContext context, String rawData, String? photoPath) async {
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
  });

  Vibrate.feedback(FeedbackType.success);
  Provider.of<FriendProvider>(context, listen: false).load(showLoading: false);
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

Future<void> setLatestReceivedEventSig(String eventSig, String pubKey) async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    String? jsonString = prefs.getString('latestEventSigs');
    if (jsonString != null) {
      latestEventSigs = json.decode(jsonString) as Map<String, dynamic>;
    }
    latestEventSigs[pubKey] = eventSig;
    String newString = json.encode(latestEventSigs);
    await prefs.setString('latestEventSigs', newString);
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

Future<Tuple2<int?, String?>> getLatestReceivedEvent(String pubKey) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  String? jsonStringTimestamps = prefs.getString('latestEventTimestamps');
  String? jsonStringSigs = prefs.getString('latestEventSigs');
  int? latestEventTimestamp;
  String? latestEventSig;

  if (jsonStringTimestamps != null) {
    latestEventTimestamps =
        json.decode(jsonStringTimestamps) as Map<String, dynamic>;
    latestEventTimestamp = latestEventTimestamps[pubKey];
  }
  if (jsonStringSigs != null) {
    latestEventSigs = json.decode(jsonStringSigs) as Map<String, dynamic>;
    latestEventSig = latestEventSigs[pubKey];
  }

  return Tuple2<int?, String?>(latestEventTimestamp, latestEventSig);
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

Future<void> cleanLocalStorage() async {
  await _lock.synchronized(() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    await prefs.remove('friends_subscription_id');
    List<String> friendsList = prefs.getStringList('friends') ?? [];
    List<String> subscribedKeys = prefs.getStringList('subscribed_keys') ?? [];
    List<String> keysToRemove = [];

    Set<String> friendsPubKeys = friendsList
        .map((friend) => getPublicKey(jsonDecode(friend)['privateKey']))
        .toSet();

    // Combine keys from all shared preferences storage lists
    Set<String> allKeys = {};

    String? jsonStringLocationTimestamps =
        prefs.getString('latestLocationTimestamps');
    String? jsonStringEventSigs = prefs.getString('latestEventSigs');
    String? jsonStringEventTimestamps =
        prefs.getString('latestEventTimestamps');

    Map<String, dynamic> latestLocationTimestamps =
        jsonStringLocationTimestamps != null
            ? json.decode(jsonStringLocationTimestamps) as Map<String, dynamic>
            : {};
    Map<String, dynamic> latestEventSigs = jsonStringEventSigs != null
        ? json.decode(jsonStringEventSigs) as Map<String, dynamic>
        : {};
    Map<String, dynamic> latestEventTimestamps =
        jsonStringEventTimestamps != null
            ? json.decode(jsonStringEventTimestamps) as Map<String, dynamic>
            : {};

    allKeys.addAll(subscribedKeys);
    allKeys.addAll(latestLocationTimestamps.keys);
    allKeys.addAll(latestEventSigs.keys);
    allKeys.addAll(latestEventTimestamps.keys);

    // Identify keys to remove
    for (final key in allKeys) {
      if (!friendsPubKeys.contains(key)) {
        keysToRemove.add(key);
      }
    }

    // Remove keys from subscribedKeys
    int initialSubscribedKeysLength = subscribedKeys.length;
    subscribedKeys.removeWhere((key) => keysToRemove.contains(key));
    bool modified = initialSubscribedKeysLength != subscribedKeys.length;

    if (modified) {
      await prefs.setStringList('subscribed_keys', subscribedKeys);
    }

    // Remove keys from other shared preferences storage lists
    List<Map<String, dynamic>> mapsToClean = [
      latestLocationTimestamps,
      latestEventSigs,
      latestEventTimestamps,
    ];

    List<String> prefKeys = [
      'latestLocationTimestamps',
      'latestEventSigs',
      'latestEventTimestamps',
    ];

    for (int i = 0; i < mapsToClean.length; i++) {
      bool mapModified = false;

      for (final key in keysToRemove) {
        if (mapsToClean[i].containsKey(key)) {
          mapsToClean[i].remove(key);
          mapModified = true;
        }
      }

      if (mapModified) {
        await prefs.setString(prefKeys[i], json.encode(mapsToClean[i]));
      }
    }
  });
}

Future<void> removeFriend(BuildContext context, int index) async {
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
    Provider.of<FriendProvider>(context, listen: false)
        .load(showLoading: false);
  });
}

Future<void> removeAllFriends(BuildContext context) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  await _lock.synchronized(() async {
    await prefs.remove('subscribed_keys');
    await prefs.remove('friends');
    await prefs.remove('latestEventTimestamps');
    await prefs.remove('messagesHistory');
  });
  Provider.of<FriendProvider>(context, listen: false).load(showLoading: false);
}

Future<List<int>> checkForUnreadMessages(friendsList) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;

  List<int> friendsWithUnreadMessages = [];
  for (int i = 0; i < friendsList.length; i++) {
    Map<String, dynamic> decodedFriend = friendsList[i];
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
        }
      }
      // Update SharedPreferences
    }
  }
  return friendsWithUnreadMessages;
}
