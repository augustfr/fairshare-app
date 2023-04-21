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
    cameraController.start(); // Start the camera when the page is initialized
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
      },
    );

    if (!confirmTakePhoto) {
      setState(() {
        qrResult = '$friendName has been added as a friend!';
      });
      return null;
    }

    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: cameraDevice,
    );

    setState(() {
      qrResult = '$friendName has been added as a friend!';
    });

    if (pickedFile == null) {
      return null;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${friendName}_$friendKey.jpg';
    final file = File(path.join(appDir.path, fileName));

    final pickedFileBytes = await pickedFile.readAsBytes();
    await file.writeAsBytes(pickedFileBytes);

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
              padding: const EdgeInsets.fromLTRB(10, 50, 10, 10),
              child: Column(
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
                            final List<Barcode> barcodes = capture.barcodes;
                            for (final barcode in barcodes) {
                              if (barcode.rawValue != _previousBarcodeValue &&
                                  _isValidQRData(barcode.rawValue)) {
                                Future.delayed(
                                    const Duration(milliseconds: 250));
                                friendData = jsonDecode(barcode.rawValue!);
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
                  Center(
                    child: QrImage(
                      data: jsonEncode({
                        "name": _userName,
                        "privateKey": _privateKey,
                        "currentLocation": _currentLocationString
                      }),
                      version: QrVersions.auto,
                      size: 200.0,
                      gapless: false,
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
