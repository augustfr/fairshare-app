import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_vibrate/flutter_vibrate.dart';

Future<List<String>> loadFriends() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String> friendsList = prefs.getStringList('friends') ?? [];
  return friendsList;
}

Future<bool> addFriend(String rawData, String? photoPath) async {
  final Map<String, dynamic> friendData = jsonDecode(rawData);
  SharedPreferences prefs = await SharedPreferences.getInstance();

  List<String> friendsList = prefs.getStringList('friends') ?? [];
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

  // Add the current location to the friend data
  List<double> currentLocation = [37.792520, -122.440140];
  friendData['currentLocation'] = currentLocation;

  friendsList.add(jsonEncode(friendData));

  await prefs.setStringList('friends', friendsList);
  Vibrate.feedback(FeedbackType.success);
  return true; // Friend added successfully
}

Future<void> removeAllFriends() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.remove('friends');
}
