import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:synchronized/synchronized.dart';

import './chat_page.dart';
import './profile_page.dart';
import '../utils/friends.dart';
import '../utils/location.dart';

final _lock = Lock();

class FriendsListPage extends StatefulWidget {
  const FriendsListPage({Key? key}) : super(key: key);

  @override
  _FriendsListPageState createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  List<Map<String, dynamic>> _friends = [];
  Set<int> unreadMessageIndexes = {};

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    List<String> friendsList = await loadFriends();
    LatLng savedLocation = await getSavedLocation();

    //unreadMessageIndexes = (await checkForUnreadMessages(friendsList)).toSet();

    setState(() {
      _friends = friendsList.map((friend) {
        Map<String, dynamic> decodedFriend =
            jsonDecode(friend) as Map<String, dynamic>;
        String locationString = decodedFriend['currentLocation'];
        List<String> latLngStrings =
            locationString.substring(7, locationString.length - 1).split(', ');
        double latitude = double.parse(latLngStrings[0]);
        double longitude = double.parse(latLngStrings[1]);
        LatLng friendLatLng = LatLng(latitude, longitude);

        double distance = getDistance(savedLocation, friendLatLng);
        String distanceString = distance.toString() + 'm';
        decodedFriend['distance'] = distanceString;
        return decodedFriend;
      }).toList();
    });
  }

  Future<void> _removeFriend(int index) async {
    removeFriend(index);
    setState(() {
      _friends.removeAt(index);
    });

    Navigator.pop(context, true);
  }

  Future<void> _showEditNameDialog(int index) async {
    TextEditingController nameController =
        TextEditingController(text: _friends[index]['name']);

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Friend\'s Name'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Friend\'s Name',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                _selectNewName(index, nameController.text);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteConfirmationDialog(int index) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Friend'),
          content: const Text('Are you sure you want to remove this friend?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Remove'),
              onPressed: () {
                _removeFriend(index);

                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Friend removed')));
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _selectNewPhoto(int index) async {
    final ImagePicker _picker = ImagePicker();
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (pickedFile != null) {
      final Directory directory = await getApplicationDocumentsDirectory();
      final String newPath = '${directory.path}/${_friends[index]['name']}.png';

      await File(pickedFile.path).copy(newPath);
      _friends[index]['photoPath'] = newPath;

      await _lock.synchronized(() async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        List<String> friendsList = _friends
            .map((friend) => jsonEncode(friend))
            .toList()
            .cast<String>();
        await prefs.setStringList('friends', friendsList);
      });

      setState(() {});
    }
  }

  Future<void> _selectNewName(int index, String name) async {
    _friends[index]['name'] = name;

    await _lock.synchronized(() async {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> friendsList =
          _friends.map((friend) => jsonEncode(friend)).toList().cast<String>();
      await prefs.setStringList('friends', friendsList);
    });

    setState(() {});
  }

  Future<void> _showConfirmNewPhotoDialog(int index) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm'),
          content: const Text('Do you want to take a new photo?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Take Photo'),
              onPressed: () {
                Navigator.of(context).pop();
                _selectNewPhoto(index);
              },
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
            Padding(
              padding: const EdgeInsets.only(top: 50),
              child: ListView.builder(
                itemCount: _friends.length,
                itemBuilder: (BuildContext context, int index) {
                  Map<String, dynamic> friend = _friends[index];
                  bool hasUnreadMessages = unreadMessageIndexes.contains(index);
                  return Dismissible(
                    key: Key(friend['name']),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (direction) async {
                      await _showDeleteConfirmationDialog(index);
                      return false;
                    },
                    background: Container(
                      color: Colors.red,
                      child: const Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(right: 20.0),
                          child: Icon(Icons.delete, color: Colors.white),
                        ),
                      ),
                    ),
                    child: Stack(
                      children: [
                        ListTile(
                          leading: InkWell(
                            onTap: () async {
                              await _showConfirmNewPhotoDialog(index);
                            },
                            child: CircleAvatar(
                              backgroundImage: friend['photoPath'] == null
                                  ? null
                                  : FileImage(File(friend['photoPath'])),
                            ),
                          ),
                          title: Text(friend['name']),
                          subtitle: Text(friend['distance']),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatPage(
                                    friendName: friend['name'],
                                    sharedKey: friend['privateKey'],
                                    friendIndex: index),
                              ),
                            );
                          },
                          onLongPress: () async {
                            await _showEditNameDialog(index);
                          },
                        ),
                        if (hasUnreadMessages)
                          Positioned(
                            bottom: 25,
                            right: 20,
                            child: Align(
                              alignment: Alignment.center,
                              child: Transform.scale(
                                scale: 0.5,
                                child:
                                    const Icon(Icons.circle, color: Colors.red),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.person, color: Colors.black),
                onPressed: () async {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfilePage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
