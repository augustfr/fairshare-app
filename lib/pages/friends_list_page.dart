import 'dart:convert';
import 'dart:io';
import 'dart:async';

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
import '../utils/nostr.dart';
import './home_page.dart';

final _lock = Lock();

bool needsChatListUpdate = false;

class FriendsListPage extends StatefulWidget {
  const FriendsListPage({Key? key}) : super(key: key);

  @override
  _FriendsListPageState createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  final StreamController<List<Map<String, dynamic>>> _friendsStreamController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (needsChatListUpdate) {
        _loadFriends();
        needsChatListUpdate = false;
      }
    });
  }

  @override
  void dispose() {
    _friendsStreamController.close();
    _timer?.cancel();
    super.dispose();
  }

  Future<List<Future<Map<String, dynamic>>>> _updateFriendsList() async {
    List<String> friendsList = await loadFriends();
    LatLng savedLocation = await getSavedLocation();
    List<Future<Map<String, dynamic>>> updatedFriendsFutures =
        friendsList.map((friend) async {
      Map<String, dynamic> decodedFriend =
          jsonDecode(friend) as Map<String, dynamic>;
      List<double> currentLocation =
          parseLatLngFromString(decodedFriend['currentLocation']);
      double latitude = currentLocation[0];
      double longitude = currentLocation[1];
      LatLng friendLatLng = LatLng(latitude, longitude);
      double distance = getDistance(savedLocation, friendLatLng);
      String distanceString = distance.toString() + 'm';
      decodedFriend['distance'] = distanceString;
      String pubKey = getPublicKey(decodedFriend['privateKey']);
      int? latestLocationUpdate = await getLatestLocationUpdate(pubKey);
      int currentTime = DateTime.now().millisecondsSinceEpoch;
      int secondsTimestamp = (currentTime / 1000).round();
      if (latestLocationUpdate != null) {
        int timeElapsed = secondsTimestamp - latestLocationUpdate;
        decodedFriend['timeElapsed'] = timeElapsed;
      }

      return decodedFriend;
    }).toList();

    return updatedFriendsFutures;
  }

  String formatDuration(int? timeElapsed) {
    if (timeElapsed == null) {
      return '';
    } else {
      if (timeElapsed < 60) {
        return '($timeElapsed sec${timeElapsed == 1 ? '' : 's'} ago)';
      } else if (timeElapsed < 3600) {
        int minutes = (timeElapsed / 60).round();
        return '($minutes min${minutes == 1 ? '' : 's'} ago)';
      } else if (timeElapsed < 86400) {
        int hours = (timeElapsed / 3600).round();
        return '($hours hour${hours == 1 ? '' : 's'} ago)';
      } else {
        int days = (timeElapsed / 86400).round();
        return '($days day${days == 1 ? '' : 's'} ago)';
      }
    }
  }

  Future<void> _loadFriends() async {
    List<Map<String, dynamic>> updatedFriends =
        await Future.wait(await _updateFriendsList());

    _friendsStreamController.add(updatedFriends);
  }

  Future<void> _removeFriend(int index) async {
    await removeFriend(index);
    List<Map<String, dynamic>> friendsList =
        await Future.wait(await _updateFriendsList());
    _friendsStreamController.add(friendsList);
  }

  Future<void> _showEditNameDialog(int index) async {
    List<Map<String, dynamic>> friendsList =
        await Future.wait(await _updateFriendsList());
    TextEditingController nameController =
        TextEditingController(text: friendsList[index]['name']);

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
      List<Map<String, dynamic>> friendsList =
          await Future.wait(await _updateFriendsList());
      final Directory directory = await getApplicationDocumentsDirectory();
      final String newPath =
          '${directory.path}/${friendsList[index]['photoPath']}.png';

      friendsList[index]['photoPath'] = newPath;

      await File(pickedFile.path).copy(newPath);
      _friendsStreamController.add(friendsList);
      await _lock.synchronized(() async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('friends',
            friendsList.map((friend) => jsonEncode(friend)).toList());
      });
    }
  }

  Future<void> _selectNewName(int index, String name) async {
    List<Map<String, dynamic>> friendsList =
        await Future.wait(await _updateFriendsList());
    friendsList[index]['name'] = name;
    _friendsStreamController.add(friendsList);

    await _lock.synchronized(() async {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'friends', friendsList.map((friend) => jsonEncode(friend)).toList());
    });
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
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _friendsStreamController.stream,
                builder: (BuildContext context,
                    AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting ||
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else {
                    List<Map<String, dynamic>> friends = snapshot.data!;
                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (BuildContext context, int index) {
                        if (friends.isEmpty) {
                          return const Center(child: Text('No friends found.'));
                        }
                        Map<String, dynamic> friend = friends[index];
                        bool hasUnreadMessages =
                            unreadMessageIndexes.contains(index);
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
                                subtitle: Text(friend['distance'] +
                                    ' ' +
                                    formatDuration(friend['timeElapsed'])),
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
                                      child: const Icon(Icons.circle,
                                          color: Colors.red),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  }
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
