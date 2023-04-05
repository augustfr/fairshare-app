import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './chat_page.dart';
import './profile_page.dart';

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
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> friendsList = prefs.getStringList('friends') ?? [];

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
                setState(() {
                  _removeFriend(index);
                  _friends.removeAt(index);
                });

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
                      leading: CircleAvatar(
                        backgroundImage:
                            AssetImage('assets/images/avatar-${index + 1}.png'),
                      ),
                      title: Text(friend['name']),
                      subtitle: Text('0.${index + 1}m'),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              friendName: friend['name'],
                              friendAvatar:
                                  'assets/images/avatar-${index + 1}.png',
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
