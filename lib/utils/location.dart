import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import './nostr.dart';
import 'package:synchronized/synchronized.dart';

final _lock = Lock();

Future<LatLng> getSavedLocation() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  double latitude = prefs.getDouble('current_latitude') ?? 0.0;
  double longitude = prefs.getDouble('current_longitude') ?? 0.0;
  return LatLng(latitude, longitude);
}

Future<LatLng> getCurrentLocation() async {
  final location = Location();
  final currentLocation = await location.getLocation();
  final latLng = LatLng(currentLocation.latitude!, currentLocation.longitude!);

  return latLng;
}

Future<void> updateFriendsLocation(
    Map<String, dynamic> content, String pubKey) async {
  String? globalKey = content['globalKey'];
  if (globalKey != null) {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await _lock.synchronized(() async {
      List<String> friendsList = prefs.getStringList('friends') ?? [];
      bool isUpdated = false;

      for (int i = 0; i < friendsList.length; i++) {
        dynamic decodedFriend = jsonDecode(friendsList[i]);
        if (decodedFriend['globalKey'] == globalKey) {
          if (getPublicKey(decodedFriend['privateKey']) == pubKey) {
            String newLocationString = content['currentLocation'];
            decodedFriend['currentLocation'] = newLocationString;

            // Update the friend in friendsList
            friendsList[i] = jsonEncode(decodedFriend);
            isUpdated = true;
            break;
          }
        }
      }

      // Save the updated friendsList in SharedPreferences if there was an update
      if (isUpdated) {
        await prefs.setStringList('friends', friendsList);
      }
    });
  }
}

List<double> parseLatLngFromString(String latLngString) {
  RegExp regex = RegExp(r'LatLng\(([^,]+),\s*([^)]+)\)');
  Match? match = regex.firstMatch(latLngString);
  if (match != null) {
    double latitude = double.parse(match.group(1) ?? '0');
    double longitude = double.parse(match.group(2) ?? '0');
    return [latitude, longitude];
  }
  return [0, 0];
}

double getDistance(LatLng location1, LatLng location2) {
  const double earthRadius = 3958.8; // Earth radius in miles

  double toRadians(double degree) {
    return degree * pi / 180.0;
  }

  double lat1 = toRadians(location1.latitude);
  double lon1 = toRadians(location1.longitude);
  double lat2 = toRadians(location2.latitude);
  double lon2 = toRadians(location2.longitude);

  double deltaLat = lat2 - lat1;
  double deltaLon = lon2 - lon1;

  double a = pow(sin(deltaLat / 2), 2) +
      cos(lat1) * cos(lat2) * pow(sin(deltaLon / 2), 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  double distance = earthRadius * c;

  if (distance > 100) {
    return (distance.round()).toDouble();
  } else {
    return double.parse((distance).toStringAsFixed(1));
  }
}
