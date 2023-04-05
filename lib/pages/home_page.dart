import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/map_style.dart';
import './friends_list_page.dart';
import './qr_scanner.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  GoogleMapController? _controller;

  late Future<CameraPosition> _initialCameraPosition;

  @override
  void initState() {
    super.initState();
    _initialCameraPosition = _getCurrentLocation();
    _checkFirstTimeUser();
  }

  // Method to get current location
  Future<CameraPosition> _getCurrentLocation() async {
    final location = Location();
    final currentLocation = await location.getLocation();
    final latLng =
        LatLng(currentLocation.latitude!, currentLocation.longitude!);

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
                    onMapCreated: (GoogleMapController controller) {
                      _controller = controller;
                      _controller!.setMapStyle(MapStyle().dark);
                    },
                  ),
                  Positioned(
                    top: 40,
                    right: 10,
                    child: RawMaterialButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const FriendsListPage()),
                        );
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
                      String? qrResult = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => QRScannerPage(
                                  onQRScanSuccess: () {
                                    print('QR scan successful.');
                                  },
                                )),
                      );
                      if (qrResult != null) {}
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
  File? _userImage;

  Future<void> _pickImage() async {
    Future<void> _showImageSourceOptions(BuildContext context) {
      return showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.camera),
                  title: const Text('Take a selfie'),
                  onTap: () {
                    Navigator.pop(context);
                    _updateImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Pick from library'),
                  onTap: () {
                    Navigator.pop(context);
                    _updateImage(ImageSource.gallery);
                  },
                ),
              ],
            ),
          );
        },
      );
    }

    // Check if app has permission to access gallery and camera
    final galleryPermissionStatus = await Permission.storage.status;
    final cameraPermissionStatus = await Permission.camera.status;
    if (galleryPermissionStatus.isDenied ||
        galleryPermissionStatus.isRestricted ||
        cameraPermissionStatus.isDenied ||
        cameraPermissionStatus.isRestricted) {
      // Request permission if necessary
      await Permission.storage.request();
      await Permission.camera.request();
    }

    // Display options for choosing an image source
    await _showImageSourceOptions(context);
  }

  void _updateImage(ImageSource source) async {
    final ImagePicker _picker = ImagePicker();

    // Open camera or gallery and select image
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _userImage = File(image.path);
      });
    } else {
      // Handle case where image is null (user cancelled selection process)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No image selected.'),
      ));
    }
  }

  Future<void> _saveUserDetails() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user_name', _userName);
      prefs.setString('user_image', _userImage!.path);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set Your Name and Profile Picture'),
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
              const SizedBox(height: 16),
              _userImage != null
                  ? Image.file(_userImage!)
                  : const Text('No image selected'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _pickImage,
                child: const Text('Choose Image'),
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