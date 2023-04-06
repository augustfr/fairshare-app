import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
