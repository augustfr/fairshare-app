import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import '../models/map_style.dart';
import './friends_list_page.dart';
import './qr_scanner.dart';
import '../utils/nostr.dart';
import '../utils/friends.dart';
import '../utils/location.dart';
import '../main.dart';

final _lock = Lock();

bool needsUpdate = false;

Set<int> unreadMessageIndexes = {};

bool switchValue = true; // true when user wants to be sending location

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  GoogleMapController? _controller;
  Timer? _timer;

  final Set<Marker> _markers = {};

  LatLng myCurrentLocation = const LatLng(0.0, 0.0);

  List<String> friendsList = [];

  late Future<CameraPosition> _initialCameraPosition;

  StreamSubscription<LocationData>? _locationSubscription;

  void _showGhostModePopup(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(15, 15, 15, 0),
      ),
    );
  }

  void _loadSwitchValue() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    setState(() {
      switchValue = prefs.getBool('switchValue') ?? true;
    });
  }

  void _saveSwitchValue(bool value) async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    await prefs.setBool('switchValue', value);
    if (value) {
      await sendLocationUpdate();
    }
  }

  void _subscribeToLocationUpdates() async {
    final location = Location();
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    double latitude;
    double longitude;
    LatLng oldLocation = const LatLng(0, 0);

    await _lock.synchronized(() async {
      latitude = prefs.getDouble('current_latitude') ?? 0.0;
      longitude = prefs.getDouble('current_longitude') ?? 0.0;
      oldLocation = LatLng(latitude, longitude);
    });

    _locationSubscription =
        location.onLocationChanged.listen((LocationData currentLocation) async {
      // Update latitude and longitude in SharedPreferences
      latitude = currentLocation.latitude ?? 0.0;
      longitude = currentLocation.longitude ?? 0.0;

      setState(() {
        myCurrentLocation = LatLng(latitude, longitude);
      });

      double distance = getDistance(oldLocation, myCurrentLocation);
      if (distance >= 0.1 && switchValue) {
        await sendLocationUpdate();
      }

      await _lock.synchronized(() async {
        await prefs.setDouble('current_latitude', latitude);
        await prefs.setDouble('current_longitude', longitude);
        oldLocation = myCurrentLocation;
      });
    });
  }

  Future<void> sendLocationUpdate() async {
    friendsList = await loadFriends();
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    String globalKey = prefs.getString('global_key') ?? '';
    List<double> currentLocationString =
        parseLatLngFromString(myCurrentLocation.toString());
    if (currentLocationString[0] != 0.0 && currentLocationString[1] != 0.0) {
      for (final friend in friendsList) {
        Map<String, dynamic> decodedFriend =
            jsonDecode(friend) as Map<String, dynamic>;
        String sharedKey = decodedFriend['privateKey'];
        final content = jsonEncode({
          'type': 'locationUpdate',
          'currentLocation': myCurrentLocation.toString(),
          'globalKey': getPublicKey(globalKey)
        });
        await postToNostr(sharedKey, content);
      }
    }
  }

  Future<void> _fetchAndUpdateData() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    List<String> subscribedKeys = prefs.getStringList('subscribed_keys') ?? [];
    List<dynamic>? friendsSubscriptionIds =
        prefs.getStringList('friends_subscription_id');
    List<String> currentFriendsSubscriptions =
        friendsSubscriptionIds?.map((id) => id as String).toList() ?? [];
    if (currentFriendsSubscriptions.isNotEmpty) {
      await closeSubscription(subscriptionIds: currentFriendsSubscriptions);
    }

    if (subscribedKeys.isNotEmpty) {
      List<String> ids = await addSubscription(publicKeys: subscribedKeys);
      await prefs.setStringList('friends_subscription_id', ids);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSwitchValue();
    WidgetsBinding.instance.addObserver(this);
    _initialCameraPosition = _getCurrentLocation();
    _checkFirstTimeUser();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _subscribeToLocationUpdates());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (needsUpdate) {
        _updateFriendsOnMapAndNotifications();
      }
    });
    _initializeAsyncDependencies();
  }

  Future<void> _initializeAsyncDependencies() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    List<String> relays = prefs.getStringList('relays') ?? [];
    if (relays.isEmpty) {
      prefs.setStringList('relays', defaultRelays);
    }
    await connectWebSocket();
    await cleanLocalStorage();
    await _fetchAndUpdateData();
    await _updateFriendsOnMapAndNotifications();
    if (switchValue) {
      await sendLocationUpdate();
    }
  }

  Future<void> _updateFriendsOnMapAndNotifications() async {
    friendsList = await loadFriends();
    await addFriendsToMap(friendsList);
    unreadMessageIndexes = (await checkForUnreadMessages(friendsList)).toSet();
    needsUpdate = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Method to get current location
  Future<CameraPosition> _getCurrentLocation() async {
    final latLng = await getCurrentLocation();

    // Save current location in SharedPreferences
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

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

  Future<void> addFriendsToMap(friendsList) async {
    BitmapDescriptor customMarkerIcon =
        await _createCircleMarkerIcon(Colors.red, 20);
    Set<Marker> updatedMarkers = {};

    for (var friendJson in friendsList) {
      Map<String, dynamic> friendData = jsonDecode(friendJson);
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

    // Update the _markers set with the updated markers
    setState(() {
      _markers.clear();
      _markers.addAll(updatedMarkers);
    });
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
                          _fetchAndUpdateData();
                        }
                      },
                      shape: const CircleBorder(),
                      fillColor: Colors.white,
                      padding: const EdgeInsets.all(0),
                      constraints: const BoxConstraints.tightFor(
                        width: 56,
                        height: 56,
                      ),
                      child: Stack(
                        children: [
                          const Icon(Icons.menu, color: Colors.black),
                          if (unreadMessageIndexes.isNotEmpty)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    left: 10,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.0),
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(2),
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                switchValue = !switchValue;
                              });
                              _showGhostModePopup(
                                context,
                                switchValue
                                    ? 'Ghost mode disabled'
                                    : 'Ghost mode enabled',
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              width: 90,
                              height: 56,
                              child: Center(
                                child: Stack(
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Icon(
                                        MdiIcons.ghost,
                                        color: switchValue
                                            ? Colors.grey
                                            : Colors.red,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Icon(
                                        Icons.location_on,
                                        color: switchValue
                                            ? Colors.blue
                                            : Colors.grey,
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Switch(
                                        value: switchValue,
                                        onChanged: (bool value) {
                                          setState(() {
                                            switchValue = value;
                                          });
                                          _showGhostModePopup(
                                            context,
                                            switchValue
                                                ? 'Ghost mode disabled'
                                                : 'Ghost mode enabled',
                                          );
                                          _saveSwitchValue(value);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
                              _fetchAndUpdateData();
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
      SharedPreferences prefs = SharedPreferencesHelper().prefs;
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
