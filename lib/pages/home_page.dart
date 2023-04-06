import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_style.dart';
import './friends_list_page.dart';
import './qr_scanner.dart';
import '../utils/nostr.dart';
import '../utils/friends.dart';
import '../utils/location.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _controller;
  final Set<Marker> _markers = {}; // Add this line to store markers

  List<double> myCurrentLocation = [0.0, 0.0]; // Default value

  late Future<CameraPosition> _initialCameraPosition;

  StreamSubscription<LocationData>? _locationSubscription;

  void _subscribeToLocationUpdates() {
    final location = Location();

    _locationSubscription =
        location.onLocationChanged.listen((LocationData currentLocation) {
      setState(() {
        myCurrentLocation = [
          currentLocation.latitude ?? 0.0,
          currentLocation.longitude ?? 0.0,
        ];
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _initialCameraPosition = _getCurrentLocation();
    _checkFirstTimeUser();
    _subscribeToLocationUpdates();
    _fetchFriendsLocations(); // Add this line to fetch friends locations
  }

  // Method to get current location
  Future<CameraPosition> _getCurrentLocation() async {
    final latLng = await getCurrentLocation();

    // Save current location in SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('current_latitude', latLng.latitude);
    await prefs.setDouble('current_longitude', latLng.longitude);

    return CameraPosition(target: latLng, zoom: 14.4746);
  }

  Future<void> _checkFirstTimeUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isFirstTime = prefs.getBool('first_time') ?? true;

    if (isFirstTime) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => const UserDetailsDialog(),
      );
      prefs.setBool('first_time', false);
    }
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

  Future<void> _fetchFriendsLocations() async {
    try {
      List<String> friendsList = await loadFriends();
      // Create a custom marker icon with a specified color and radius
      BitmapDescriptor customMarkerIcon =
          await _createCircleMarkerIcon(Colors.red, 20);

      // Create a set of markers for existing friends
      Set<Marker> updatedMarkers = {};
      for (var friendJson in friendsList) {
        Map<String, dynamic> friendData = jsonDecode(friendJson);
        List<dynamic>? currentLocation = friendData['currentLocation'];
        String? friendName = friendData['name'];
        if (currentLocation != null &&
            currentLocation.length == 2 &&
            friendName != null) {
          LatLng friendLatLng = LatLng(currentLocation[0], currentLocation[1]);
          updatedMarkers.add(
            Marker(
              markerId: MarkerId(friendName),
              position: friendLatLng,
              infoWindow: InfoWindow(title: friendName),
              icon: customMarkerIcon, // Use the custom marker icon
            ),
          );
        }
      }

      // Update the _markers set with the updated markers
      setState(() {
        _markers.clear();
        _markers.addAll(updatedMarkers);
      });
    } catch (e) {
      print('Error fetching friends locations: $e');
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FutureBuilder<CameraPosition>(
            future: _initialCameraPosition,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              return Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: snapshot.data!,
                    myLocationEnabled: true,
                    markers: _markers, // Add this line to include markers
                    onMapCreated: (GoogleMapController controller) {
                      _controller = controller;
                      _controller!.setMapStyle(MapStyle().dark);
                    },
                  ),
                  Positioned(
                    top: 40,
                    right: 10,
                    child: RawMaterialButton(
                      onPressed: () async {
                        bool? friendsListUpdated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FriendsListPage(),
                          ),
                        );
                        if (friendsListUpdated == true) {
                          _fetchFriendsLocations();
                        }
                      },
                      shape: const CircleBorder(),
                      fillColor: Colors.white,
                      padding: const EdgeInsets.all(0),
                      constraints: const BoxConstraints.tightFor(
                        width: 56,
                        height: 56,
                      ),
                      child: const Icon(Icons.menu, color: Colors.black),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            bottom: 20,
            child: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => QRScannerPage(
                            onQRScanSuccess: () {
                              _fetchFriendsLocations();
                            },
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserDetailsDialog extends StatefulWidget {
  const UserDetailsDialog({Key? key}) : super(key: key);

  @override
  _UserDetailsDialogState createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<UserDetailsDialog> {
  final _formKey = GlobalKey<FormState>();
  String _userName = '';

  Future<void> _saveUserDetails() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user_name', _userName);
      prefs.setString('global_key', generateRandomPrivateKey());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set Your Name'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
                onSaved: (value) => _userName = value!,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saveUserDetails,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
