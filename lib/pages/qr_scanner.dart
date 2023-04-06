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

const loopTime = 10; //in seconds

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

  late Timer _timer;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
    _timer = Timer.periodic(const Duration(seconds: loopTime), (timer) async {
      _updateKey();
    });
    _loadUserData();
  }

  @override
  void dispose() {
    _timer.cancel();
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

  Future<String?> _updateKey() async {
    String privateKey = generateRandomPrivateKey();
    String pubKey = getPublicKey(privateKey);
    setState(() {
      _privateKey = privateKey;
      _currentLocationString = currentLocationString;
    });
    String event = await listenForConfirm(publicKey: pubKey);
    String friendName = getContent(event);
    String? photoPath =
        await _promptForPhoto(friendName, privateKey, CameraDevice.rear);
    Map<String, String> jsonMap = {
      "name": friendName,
      "privateKey": privateKey
    };
    String jsonString = json.encode(jsonMap);
    bool isAdded = await addFriend(jsonString, photoPath);
    if (isAdded) {
      return jsonString; // Return the rawData if the friend is added
    }
    return null;
  }

  void _toggleScan() {
    setState(() {
      _isScanning = !_isScanning;
    });
    if (_isScanning) {
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
                  ElevatedButton(
                    onPressed: () async {
                      await postToNostr(_privateKey,
                          '{"name": "Gene", "currentLocation": "LatLng(37.792520, -122.440140)"}');
                    },
                    child: const Text('Debug scanned'),
                  ),
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
                                _toggleScan(); // Close the scanner immediately
                                final Map<String, dynamic> friendData =
                                    jsonDecode(barcode.rawValue!);

                                final String friendName = friendData['name'];

                                bool isAlreadyAdded =
                                    await _isFriendAlreadyAdded(
                                        barcode.rawValue!);
                                String? photoPath;
                                SharedPreferences prefs =
                                    await SharedPreferences.getInstance();
                                String? name = prefs.getString('user_name');
                                if (!isAlreadyAdded) {
                                  String jsonBody = '{"name": "' +
                                      (name ?? 'Anonymous') +
                                      '", "currentLocation": "' +
                                      _currentLocationString +
                                      '"}';
                                  postToNostr(
                                      friendData['privateKey'], jsonBody);
                                  photoPath = await _promptForPhoto(
                                      friendName,
                                      friendData['privateKey'],
                                      CameraDevice.rear);
                                  bool isAdded = await addFriend(
                                      barcode.rawValue!, photoPath);
                                  setState(() {
                                    if (isAdded) {
                                      qrResult =
                                          '$friendName has been added as a friend!';
                                    }
                                  });
                                } else {
                                  _toggleScan();
                                  setState(() {
                                    qrResult =
                                        '$friendName is already your friend!';
                                  });
                                }

                                debugPrint(
                                    'QR code found! ${barcode.rawValue}');
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
