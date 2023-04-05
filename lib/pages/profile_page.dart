import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _name;
  File? _image;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? name = prefs.getString('user_name');
    String? imagePath = prefs.getString('user_image');

    setState(() {
      _name = name;
      _image = imagePath != null ? File(imagePath) : null;
    });
  }

  Future<void> _updateImage(ImageSource source) async {
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
    final ImagePicker _picker = ImagePicker();
    final XFile? pickedFile = await _picker.pickImage(source: source);

    if (pickedFile != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('user_image', pickedFile.path);

      setState(() {
        _image = File(pickedFile.path);
      });
    } else {
      setState(() {
        _image = null;
      });
    }
  }

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

  Future<void> _resetAndCloseApp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete All Data?'),
          content: const Text(
              'Are you sure you want to delete all data? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await prefs.clear(); // Clear all stored data
// Close the app
                if (Platform.isAndroid) {
                  SystemChannels.platform
                      .invokeMethod<void>('SystemNavigator.pop');
                } else if (Platform.isIOS) {
                  exit(0);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showNameInputDialog(BuildContext context) {
    String newName = _name ?? '';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Name'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter your name'),
            onChanged: (value) {
              newName = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.setString('user_name', newName);
                setState(() {
                  _name = newName;
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
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
            Center(
              child: GestureDetector(
                onTap: () => _showNameInputDialog(context),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _showImageSourceOptions(context),
                      behavior: HitTestBehavior.translucent,
                      child: CircleAvatar(
                        backgroundImage: (_image != null
                                ? FileImage(_image!)
                                : const AssetImage(
                                    'assets/images/avatar-1.png'))
                            as ImageProvider<Object>?,
                        radius: 50,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _name ?? 'Anonymous',
                      style: Theme.of(context).textTheme.headlineSmall!,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(50.0),
        child: ElevatedButton(
          onPressed: _resetAndCloseApp,
          child: const Text('Delete All Data'),
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.all<Color>(Colors.red),
          ),
        ),
      ),
    );
  }
}
