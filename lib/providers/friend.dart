import 'dart:convert';

import 'package:fairshare/utils/friends.dart';
import 'package:fairshare/utils/location.dart';
import 'package:fairshare/utils/nostr.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FriendProvider extends ChangeNotifier {
  bool isLoading = false;
  List<Map<String, dynamic>> friends = [];

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      isLoading = true;
      notifyListeners();
    }
    List<Map<String, dynamic>> friendsList =
        await Future.wait(await _updateFriendsList());

    friends.clear();
    friends.addAll(friendsList);
    if (showLoading) {
      isLoading = false;
    }
    notifyListeners();
  }

  Future<List<Future<Map<String, dynamic>>>> _updateFriendsList() async {
    List<String> friendsList = await loadFriends();
    LatLng savedLocation = await getSavedLocation();
    List<Future<Map<String, dynamic>>> updatedFriendsFutures =
        friendsList.map((friend) async {
      Map<String, dynamic> decodedFriend =
          jsonDecode(friend) as Map<String, dynamic>;
      List<double> currentLocation =
          parseLatLngFromString(decodedFriend['currentLocation']);
      double latitude = currentLocation[0];
      double longitude = currentLocation[1];
      LatLng friendLatLng = LatLng(latitude, longitude);
      double distance = getDistance(savedLocation, friendLatLng);
      String distanceString = distance.toString() + 'm';
      decodedFriend['distance'] = distanceString;
      String pubKey = getPublicKey(decodedFriend['privateKey']);
      int? latestLocationUpdate = await getLatestLocationUpdate(pubKey);
      int currentTime = DateTime.now().millisecondsSinceEpoch;
      int secondsTimestamp = (currentTime / 1000).round();
      if (latestLocationUpdate != null) {
        int timeElapsed = secondsTimestamp - latestLocationUpdate;
        decodedFriend['timeElapsed'] = timeElapsed;
      }

      return decodedFriend;
    }).toList();

    return updatedFriendsFutures;
  }

  void clear() {
    friends.clear();
    notifyListeners();
  }
}
