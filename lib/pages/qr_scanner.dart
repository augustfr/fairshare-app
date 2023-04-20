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

Duration loopTime = const Duration(seconds: 10);

Map<String, dynamic> friendData = {};

String scannedPubKey = '';
String scannedPrivKey = '';

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
  late MobileScannerController cameraController;
  String qrResult = '';
  String? _previousBarcodeValue;
  String _userName = '';
  String _privateKey = '';
  bool _isScanning = false;
  String _currentLocationString = ''; // declare as state variable
  String currentLocationString = '';
  bool _isLocationAvailable = false;
  String _previousId = '';
  bool addingFriendInProgress = false;

  late Timer _timer;
  late Timer _timer2;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
    _timer = Timer.periodic(loopTime, (timer) async {
      if (!addingFriendInProgress) {
        _updateKey();
      }
    });
    _timer2 = Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      _checkReceivedConfirm();
    });
    _loadUserData();
  }

  @override
  void dispose() {
    if (_previousId != '') {
      closeSubscription(subscriptionId: _previousId);
    }
    _timer.cancel();
    _timer2.cancel();
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    LatLng savedLocation = await getSavedLocation();
    currentLocationString = savedLocation.toString();
    setState(() {
      _isLocationAvailable = true;
      _userName = prefs.getString('user_name') ?? '';
    });
    await _updateKey();
  }

  Future<void> _updateKey() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
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

  Future<void> _checkReceivedConfirm() async {
    if (addingFriend.isNotEmpty) {
      addingFriendInProgress = true;
      Map<String, dynamic> content = addingFriend;
      addingFriend = {};
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
    }
  }

  void _toggleScan() {
    setState(() {
      _isScanning = !_isScanning;
    });

    if (_isScanning) {
      _previousBarcodeValue =
          null; // Reset the previous barcode value when starting the scanner
      cameraController.dispose();
      cameraController =
          MobileScannerController(); // Re-initialize the controller
      cameraController.start();
    } else {
      cameraController.stop();
    }
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
        });

    if (!confirmTakePhoto) {
      setState(() {
        qrResult = '$friendName has been added as a friend!';
      });
      return null;
    }

    final pickedFile = await picker.pickImage(
        source: ImageSource.camera, preferredCameraDevice: cameraDevice);

    setState(() {
      qrResult = '$friendName has been added as a friend!';
    });

    if (pickedFile == null) {
      return null;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${friendName}_$friendKey.jpg';
    final file = File('${appDir.path}/$fileName');
    await pickedFile.saveTo(file.path);

    return file.path;
  }

  Future<bool> _isFriendAlreadyAdded(String rawData) async {
    final Map<String, dynamic> friendData = jsonDecode(rawData);
    SharedPreferences prefs = await SharedPreferences.getInstance();

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
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _toggleScan,
                    child: Text(_isScanning ? 'Stop Scanning' : 'Scan'),
                  ),
                  // ElevatedButton(
                  //   onPressed: () async {
                  //     await postToNostr(_privateKey,
                  //         '{"type": "handshake", "name": "Gene", "currentLocation": "LatLng(37.792520, -122.440140)", "globalKey": "123"}');
                  //   },
                  //   child: const Text('Debug scanned'),
                  // ),
                  Visibility(
                    visible: _isScanning,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.width * 0.8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: MobileScanner(
                          controller: cameraController,
                          onDetect: (capture) async {
                            if (!_isScanning) {
                              return;
                            }
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              if (barcode.rawValue != _previousBarcodeValue &&
                                  _isValidQRData(barcode.rawValue)) {
                                Future.delayed(
                                    const Duration(milliseconds: 500), () {
                                  _toggleScan();
                                });
                                friendData = jsonDecode(barcode.rawValue!);
                                final String friendName = friendData['name'];
                                scannedPubKey =
                                    getPublicKey(friendData['privateKey']);
                                scannedPrivKey = friendData['privateKey'];
                                await addSubscription(
                                    publicKeys: [scannedPubKey]);
                                bool isAlreadyAdded =
                                    await _isFriendAlreadyAdded(
                                        barcode.rawValue!);
                                SharedPreferences prefs =
                                    await SharedPreferences.getInstance();
                                String? name = prefs.getString('user_name');
                                String? globalKey =
                                    prefs.getString('global_key');
                                if (!isAlreadyAdded && globalKey != null) {
                                  String jsonBody =
                                      '{"type": "handshake", "name": "' +
                                          (name ?? 'Anonymous') +
                                          '", "currentLocation": "' +
                                          _currentLocationString +
                                          '", "globalKey": "' +
                                          (globalKey) +
                                          '"}';
                                  await postToNostr(scannedPrivKey, jsonBody);
                                } else {
                                  setState(() {
                                    qrResult =
                                        '$friendName is already your friend!';
                                  });
                                }
                                _previousBarcodeValue = barcode.rawValue;
                                widget.onQRScanSuccess();
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Visibility(
                    visible: !_isScanning && _isLocationAvailable,
                    child: Center(
                      child: QrImage(
                        data: jsonEncode({
                          "name": _userName,
                          "privateKey": _privateKey,
                          "currentLocation": _currentLocationString
                        }),
                        version: QrVersions.auto,
                        size: 300.0,
                        gapless: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    qrResult,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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
