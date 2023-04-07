import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

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
