import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/nostr.dart';
import '../utils/friends.dart';
import '../utils/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path/path.dart' as path;
import '../main.dart';

Duration loopTime = const Duration(seconds: 10);

Map<String, dynamic> friendData = {};

String scannedPubKey = '';
String scannedPrivKey = '';

bool isCameraStarted = false;

class QRScannerPage extends StatefulWidget {
  final Function onQRScanSuccess;

  const QRScannerPage({
    Key? key,
    required this.onQRScanSuccess,
  }) : super(key: key);

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  late MobileScannerController cameraController;
  String? _previousBarcodeValue;
  String _userName = '';
  String _privateKey = '';
  String _currentLocationString = ''; // declare as state variable
  String currentLocationString = '';
  bool _isLocationAvailable = false;
  String _previousId = '';
  bool addingFriendInProgress = false;
  bool _isLoading = false;

  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _startCamera();
    _timer = Timer.periodic(loopTime, (timer) async {
      if (!addingFriendInProgress) {
        _updateKey();
      }
    });
    _loadUserData();
  }

  @override
  void dispose() {
    if (_previousId != '') {
      closeSubscription(subscriptionId: _previousId);
    }
    _timer.cancel();
    _stopCamera();
    super.dispose();
  }

  void _startCamera() {
    if (!isCameraStarted) {
      cameraController = MobileScannerController();
      cameraController.start().then((_) {
        isCameraStarted = true;
      });
    }
  }

  void _stopCamera() {
    if (isCameraStarted) {
      cameraController.stop().then((_) {
        isCameraStarted = false;
      });
    }
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    LatLng savedLocation = await getSavedLocation();
    currentLocationString = savedLocation.toString();
    setState(() {
      _isLocationAvailable = true;
      _userName = prefs.getString('user_name') ?? '';
    });
    await _updateKey();
  }

  Future<void> _updateKey() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    String privateKey = generateRandomPrivateKey();
    String pubKey = getPublicKey(privateKey);
    String? previousId = prefs.getString('cycling_subscription_id');
    if (previousId != null) {
      await closeSubscription(subscriptionId: previousId);
    }
    String id = await addSubscription(publicKeys: [pubKey]);
    await prefs.setString('cycling_subscription_id', id);
    await prefs.setString('cycling_pub_key', pubKey);
    await prefs.setString('cycling_priv_key', privateKey);

    setState(() {
      _previousId = id;
      _privateKey = privateKey;
      _currentLocationString = currentLocationString;
    });
  }

  Future<bool> _checkReceivedConfirm() async {
    const timeoutDuration = Duration(seconds: 5);
    const checkInterval = Duration(milliseconds: 100);

    Stopwatch stopwatch = Stopwatch()..start();

    while (addingFriend.isEmpty) {
      if (stopwatch.elapsed >= timeoutDuration) {
        return false;
      }
      await Future.delayed(checkInterval);
    }

    if (addingFriend.isNotEmpty) {
      addingFriendInProgress = true;
      Map<String, dynamic> content = addingFriend;
      addingFriend = {};
      if (content['name'] != null) {
        String friendName = content['name'];
        String friendLocation = content['currentLocation'];
        String globalKey = content['globalKey'];
        String? photoPath =
            await _promptForPhoto(friendName, _privateKey, CameraDevice.rear);
        Map<String, String> jsonMap = {
          "name": friendName,
          "privateKey": newFriendPrivKey,
          "currentLocation": friendLocation,
          "globalKey": globalKey
        };
        String jsonString = json.encode(jsonMap);
        bool added = await addFriend(jsonString, photoPath);

        if (added) {
          widget.onQRScanSuccess();
          addingFriendInProgress = false;
        }
        return true;
      }
    }
    return false;
  }

  bool _isValidQRData(String? rawData) {
    if (rawData == null) {
      return false;
    }

    try {
      final Map<String, dynamic> decodedData = jsonDecode(rawData);
      return decodedData.containsKey('name') &&
          decodedData.containsKey('privateKey');
    } catch (e) {
      return false;
    }
  }

  void _showPopup(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(15, 15, 15, 0),
      ),
    );
  }

  Future<String?> _promptForPhoto(
      String friendName, String friendKey, CameraDevice cameraDevice) async {
    final picker = ImagePicker();
    bool confirmTakePhoto = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Contact Photo'),
          content: Text('Do you want to add a photo of $friendName?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Yes'),
              onPressed: () {
                confirmTakePhoto = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );

    if (!confirmTakePhoto) {
      _showPopup(context, '$friendName added successfully');
      print('pop');
      Navigator.of(context).pop();
      return null;
    }

    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: cameraDevice,
    );
    print('test');
    if (pickedFile == null) {
      print('failed to add');
      _showPopup(context, 'Failed to add friend');
      Navigator.of(context).pop();
      return null;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${friendName}_$friendKey.jpg';
    final file = File(path.join(appDir.path, fileName));

    final pickedFileBytes = await pickedFile.readAsBytes();
    await file.writeAsBytes(pickedFileBytes);

    _showPopup(context, '$friendName added successfully');
    Navigator.of(context).pop();

    return file.path;
  }

  Future<bool> _isFriendAlreadyAdded(String rawData) async {
    final Map<String, dynamic> friendData = jsonDecode(rawData);
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    List<String> friendsList = prefs.getStringList('friends') ?? [];

    // Check if the friend is already in the list
    for (String friend in friendsList) {
      final Map<String, dynamic> existingFriend = jsonDecode(friend);
      if (existingFriend['privateKey'] == friendData['privateKey']) {
        return true; // Friend is already in the list
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 50, 10, 10),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: SizedBox(
                            width: 200.0,
                            height: 200.0,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: MobileScanner(
                                controller: cameraController,
                                onDetect: (capture) async {
                                  setState(() {
                                    _isLoading = true;
                                    _stopCamera();
                                  });
                                  final List<Barcode> barcodes =
                                      capture.barcodes;
                                  for (final barcode in barcodes) {
                                    if (barcode.rawValue !=
                                            _previousBarcodeValue &&
                                        _isValidQRData(barcode.rawValue)) {
                                      friendData =
                                          jsonDecode(barcode.rawValue!);
                                      scannedPubKey = getPublicKey(
                                          friendData['privateKey']);
                                      scannedPrivKey = friendData['privateKey'];
                                      await addSubscription(
                                          publicKeys: [scannedPubKey]);
                                      bool isAlreadyAdded =
                                          await _isFriendAlreadyAdded(
                                              barcode.rawValue!);
                                      SharedPreferences prefs =
                                          await SharedPreferences.getInstance();
                                      String? name =
                                          prefs.getString('user_name');
                                      String? globalKey =
                                          prefs.getString('global_key');
                                      if (!isAlreadyAdded &&
                                          globalKey != null) {
                                        String jsonBody =
                                            '{"type": "handshake", "name": "' +
                                                (name ?? 'Anonymous') +
                                                '", "currentLocation": "' +
                                                _currentLocationString +
                                                '", "globalKey": "' +
                                                (globalKey) +
                                                '"}';
                                        await postToNostr(
                                            scannedPrivKey, jsonBody);
                                        bool received =
                                            await _checkReceivedConfirm();
                                        if (!received) {
                                          _showPopup(
                                              context, 'Failed to add friend');
                                          Navigator.of(context).pop();
                                        } else {
                                          widget.onQRScanSuccess();
                                        }
                                      }
                                      _previousBarcodeValue = barcode.rawValue;
                                    }
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: QrImage(
                            data: jsonEncode({
                              "name": _userName,
                              "privateKey": _privateKey,
                              "currentLocation": _isLocationAvailable
                                  ? _currentLocationString
                                  : 'LatLng(0.0,0.0)'
                            }),
                            version: QrVersions.auto,
                            size: 200.0,
                            gapless: false,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
