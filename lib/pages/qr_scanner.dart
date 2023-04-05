import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/nostr.dart';

class QRScannerPage extends StatefulWidget {
  final VoidCallback onQRScanSuccess;

  const QRScannerPage({Key? key, required this.onQRScanSuccess})
      : super(key: key);

  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  late MobileScannerController cameraController;
  String qrResult = '';
  String? _previousBarcodeValue;
  String _userName = '';
  String _privateKey = '';
  bool _isScanning = false;

  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    cameraController = MobileScannerController();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      setState(() {
        _privateKey = generateRandomPrivateKey();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? '';
      _privateKey = generateRandomPrivateKey();
    });
  }

  Future<bool> _addFriend(String rawData) async {
    final Map<String, dynamic> friendData = jsonDecode(rawData);
    SharedPreferences prefs = await SharedPreferences.getInstance();

    List<String> friendsList = prefs.getStringList('friends') ?? [];

    // Check if the friend is already in the list
    for (String friend in friendsList) {
      final Map<String, dynamic> existingFriend = jsonDecode(friend);
      if (existingFriend['privateKey'] == friendData['privateKey']) {
        return false; // Friend is already in the list
      }
    }

    friendsList.add(jsonEncode(friendData));
    await prefs.setStringList('friends', friendsList);
    return true; // Friend added successfully
  }

  void _toggleScan() {
    setState(() {
      _isScanning = !_isScanning;
    });
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
                                final Map<String, dynamic> friendData =
                                    jsonDecode(barcode.rawValue!);
                                final String friendName = friendData['name'];

                                bool isAdded =
                                    await _addFriend(barcode.rawValue!);
                                _toggleScan();
                                setState(() {
                                  if (isAdded) {
                                    qrResult =
                                        '$friendName has been added as a friend!';
                                  } else {
                                    qrResult =
                                        '$friendName is already your friend!';
                                  }
                                });

                                debugPrint(
                                    'QR code found! ${barcode.rawValue}');
                                Vibrate.feedback(FeedbackType.success);
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
                    visible:
                        !_isScanning, // Only show the QR code when not scanning
                    child: Center(
                      child: QrImage(
                        data: jsonEncode({
                          "name": _userName,
                          "privateKey": _privateKey,
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
