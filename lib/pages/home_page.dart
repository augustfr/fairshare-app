import 'dart:async';
import 'dart:convert';

import 'package:fairshare/providers/friend.dart';
import 'package:fairshare/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:permission_handler/permission_handler.dart' as Permissor;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import './friends_list_page.dart';
import './qr_scanner.dart';
import '../main.dart';
import '../models/map_style.dart';
import '../utils/friends.dart';
import '../utils/location.dart';
import '../utils/nostr.dart';
import '../utils/notification_helper.dart';

final _lock = Lock();

bool switchValue = true; // true when user wants to be sending location

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, AfterLayoutMixin {
  GoogleMapController? _controller;

  LatLng myCurrentLocation = const LatLng(0.0, 0.0);

  CameraPosition initialCameraPosition =
      CameraPosition(target: LatLng(0, 0), zoom: 14.4746);

  late Future<CameraPosition> _initialCameraPosition;

  StreamSubscription<LocationData>? _locationSubscription;

  FriendProvider? friendProvider;

  @override
  void initState() {
    super.initState();
    _loadSwitchValue();
    _initializeNotification();
    WidgetsBinding.instance.addObserver(this);

    _initialCameraPosition = _getCurrentLocation();
    _checkFirstTimeUser();
    // _subscribeToLocationUpdates();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _subscribeToLocationUpdates());
    _initializeAsyncDependencies();
  }

  @override
  void afterFirstLayout(BuildContext context) {
    friendProvider = Provider.of<FriendProvider>(context, listen: false);
    friendProvider!.load();
  }

  Future<void> _initializeNotification() async {
    await initializeNotifications(context);
  }

  Future<void> _initializeAsyncDependencies() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    List<String> relays = prefs.getStringList('relays') ?? [];
    if (relays.isEmpty) {
      prefs.setStringList('relays', defaultRelays);
    }
    await connectWebSocket(context);
    await cleanLocalStorage();
    await _fetchAndUpdateData();
    if (switchValue) {
      await sendLocationUpdate();
    }
  }

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

    await GeolocatorPlatform.instance.isLocationServiceEnabled();

    final myLocation = await Geolocator.getCurrentPosition();
    setState(() {
      myCurrentLocation = LatLng(myLocation.latitude, myLocation.longitude);
      initialCameraPosition =
          CameraPosition(target: myCurrentLocation, zoom: 14.4746);
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
    List<Map<String, dynamic>> friendsList = friendProvider!.friends;
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    String globalKey = prefs.getString('global_key') ?? '';
    List<double> currentLocationString =
        parseLatLngFromString(myCurrentLocation.toString());
    if (currentLocationString[0] != 0.0 && currentLocationString[1] != 0.0) {
      for (final friend in friendsList) {
        String sharedKey = friend['privateKey'];
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
  void dispose() {
    _locationSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Method to get current location
  Future<CameraPosition> _getCurrentLocation() async {
    Permissor.PermissionStatus status = Permissor.PermissionStatus.denied;
    while (status.isGranted) {
      await Permissor.Permission.location.request();
      status = await Permissor.Permission.location.status;
    }
    Position position = await Geolocator.getCurrentPosition();

    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    await prefs.setDouble('current_latitude', position.latitude);
    await prefs.setDouble('current_longitude', position.longitude);

    _controller!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        15.0,
      ),
    );

    return CameraPosition(
        target: LatLng(position.latitude, position.longitude), zoom: 14.4746);
  }

  Future<void> _checkFirstTimeUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isFirstTime = prefs.getBool('first_time') ?? true;

    if (isFirstTime) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => UserDetailsDialog(
          onClose: () {
            _initialCameraPosition = _getCurrentLocation();
          },
        ),
      );
      prefs.setBool('first_time', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<CameraPosition>(
        future: _initialCameraPosition,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              Consumer<FriendProvider>(
                builder: (context, friend, child) {
                  if (friend.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: initialCameraPosition,
                        myLocationEnabled: true,
                        markers: friend
                            .mapMarkers, // Add this line to include markers
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
                              if (friend.unreadMessageIndexes.isNotEmpty)
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
          );
        },
      ),
    );
  }
}

class UserDetailsDialog extends StatefulWidget {
  final Function onClose;
  const UserDetailsDialog({
    required this.onClose,
    Key? key,
  }) : super(key: key);

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
      widget.onClose();
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
