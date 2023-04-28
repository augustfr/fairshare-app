import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fairshare/utils/friends.dart';
import 'package:fairshare/utils/location.dart';
import 'package:fairshare/utils/nostr.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class FriendProvider extends ChangeNotifier {
  bool isLoading = false;
  List<Map<String, dynamic>> friends = [];
  Set<Marker> mapMarkers = {};
  Set<int> unreadMessageIndexes = {};

  Future<void> load({bool showLoading = true}) async {
    if (showLoading) {
      isLoading = true;
      notifyListeners();
    }
    List<Map<String, dynamic>> friendsList =
        await Future.wait(await _updateFriendsList());

    friends.clear();
    friends.addAll(friendsList);

    await addFriendsToMap(friendsList);
    unreadMessageIndexes = (await checkForUnreadMessages(friendsList)).toSet();

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

  Future<void> addFriendsToMap(friendsList) async {
    BitmapDescriptor customMarkerIcon =
        await _createCircleMarkerIcon(Colors.red, 20);
    Set<Marker> updatedMarkers = {};

    for (var friendData in friendsList) {
      String? friendName = friendData['name'];
      final friendLocation = friendData['currentLocation'];

      if (friendLocation != null) {
        List<double> currentLocation =
            parseLatLngFromString(friendData['currentLocation']);
        double latitude = currentLocation[0];
        double longitude = currentLocation[1];
        updatedMarkers.add(
          Marker(
            markerId: MarkerId(friendName ?? 'Anonymous'),
            position: LatLng(latitude, longitude),
            infoWindow: InfoWindow(title: friendName ?? 'Anonymous'),
            icon: customMarkerIcon,
          ),
        );
      }
    }

    mapMarkers.clear();
    mapMarkers.addAll(updatedMarkers);
  }

  Future<BitmapDescriptor> _createCircleMarkerIcon(
      Color color, double circleRadius) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = color;
    final double radius = circleRadius;

    canvas.drawCircle(Offset(radius, radius), radius, paint);

    final ui.Image image = await pictureRecorder
        .endRecording()
        .toImage((radius * 2).toInt(), (radius * 2).toInt());
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  void clear() {
    friends.clear();
    notifyListeners();
  }
}
