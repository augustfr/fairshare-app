import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './chat_page.dart';
import './profile_page.dart';
import '../utils/friends.dart';

class FriendsListPage extends StatefulWidget {
  const FriendsListPage({Key? key}) : super(key: key);

  @override
  _FriendsListPageState createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    List<String> friendsList = await loadFriends();

    setState(() {
      _friends = friendsList
          .map((friend) => jsonDecode(friend) as Map<String, dynamic>)
          .toList();
    });
  }

  Future<void> _removeFriend(int index) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> friendsList = prefs.getStringList('friends') ?? [];

    friendsList.removeAt(index);
    await prefs.setStringList('friends', friendsList);

    setState(() {
      _friends.removeAt(index);
    });
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

      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> friendsList =
          _friends.map((friend) => jsonEncode(friend)).toList().cast<String>();
      await prefs.setStringList('friends', friendsList);

      setState(() {});
    }
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
                    child: ListTile(
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
                      subtitle: Text('0.${index + 1}m'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              friendName: friend['name'],
                              friendAvatar: friend['photoPath'],
                            ),
                          ),
                        );
                      },
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
