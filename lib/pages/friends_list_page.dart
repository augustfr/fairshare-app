import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fairshare/providers/friend.dart';
import 'package:fairshare/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import './chat_page.dart';
import './profile_page.dart';
import '../main.dart';
import '../utils/friends.dart';

final _lock = Lock();

bool isFriendListPage = false;

class FriendsListPage extends StatefulWidget {
  const FriendsListPage({Key? key}) : super(key: key);

  @override
  _FriendsListPageState createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage>
    with AfterLayoutMixin {
  FriendProvider? friendProvider;

  @override
  void initState() {
    super.initState();
    isFriendListPage = true;
  }

  @override
  void afterFirstLayout(BuildContext context) {
    friendProvider = Provider.of<FriendProvider>(context, listen: false);
    friendProvider!.load();
  }

  @override
  void dispose() {
    isFriendListPage = false;
    super.dispose();
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

  Future<void> _removeFriend(int index) async {
    await removeFriend(context, index);
    friendProvider?.load();
  }

  Future<void> _showEditNameDialog(int index) async {
    TextEditingController nameController =
        TextEditingController(text: friendProvider?.friends[index]['name']);

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
      source: ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (pickedFile != null) {
      final List<Map<String, dynamic>> friendsList = friendProvider!.friends;
      final Directory directory = await getApplicationDocumentsDirectory();
      final String? existingPath = friendsList[index]['photoPath'] ?? '';
      final String newFileName = path.basename(pickedFile.path);
      final String newPath = '${directory.path}/$newFileName';

      final File newFile = File(newPath);
      final bool newFileExists = await newFile.exists();
      if (newFileExists) {
        // If the file already exists, delete it
        await newFile.delete();
      }

      // Save the new photo
      final pickedFileBytes = await pickedFile.readAsBytes();
      await newFile.writeAsBytes(pickedFileBytes);

      // Update the friends list
      friendsList[index]['photoPath'] = newPath;

      // Save the updated friends list to SharedPreferences
      await _lock.synchronized(() async {
        final SharedPreferences prefs = SharedPreferencesHelper().prefs;
        await prefs.setStringList(
          'friends',
          friendsList.map((friend) => jsonEncode(friend)).toList(),
        );
      });

      // Delete the old photo if it exists and is not the same as the new photo
      if (existingPath != newPath && existingPath != null) {
        final File existingFile = File(existingPath);
        final bool existingFileExists = await existingFile.exists();
        if (existingFileExists) {
          await existingFile.delete();
        }
      }

      friendProvider?.load(showLoading: false);
    }
  }

  Future<void> _selectNewName(int index, String name) async {
    List<Map<String, dynamic>> friendsList = friendProvider!.friends;
    friendsList[index]['name'] = name;

    await _lock.synchronized(() async {
      SharedPreferences prefs = SharedPreferencesHelper().prefs;
      await prefs.setStringList(
          'friends', friendsList.map((friend) => jsonEncode(friend)).toList());
    });

    friendProvider?.load(showLoading: false);
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
              child: Consumer<FriendProvider>(
                builder: (context, friendProvider, child) {
                  if (friendProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  List<Map<String, dynamic>> friends = friendProvider.friends;
                  return RefreshIndicator(
                      onRefresh: () => friendProvider.load(),
                      child: ListView.builder(
                        itemCount: friends.length,
                        itemBuilder: (BuildContext context, int index) {
                          if (friends.isEmpty) {
                            return const Center(
                                child: Text('No friends found.'));
                          }
                          Map<String, dynamic> friend = friends[index];
                          bool hasUnreadMessages = friendProvider
                              .unreadMessageIndexes
                              .contains(index);
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
                                  child:
                                      Icon(Icons.delete, color: Colors.white),
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
                                      backgroundImage:
                                          friend['photoPath'] == null
                                              ? null
                                              : FileImage(
                                                  File(friend['photoPath'])),
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
                      ));
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
