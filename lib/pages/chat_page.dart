import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/nostr.dart';
import '../utils/messages.dart';
import 'package:synchronized/synchronized.dart';
import './home_page.dart';
import './friends_list_page.dart';

bool needsMessageUpdate = false;

final _lock = Lock();

class ChatPage extends StatefulWidget {
  final String friendName;
  final String sharedKey;
  final int friendIndex;

  const ChatPage({
    Key? key,
    required this.friendName,
    required this.sharedKey,
    required this.friendIndex,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class Message {
  final String text;
  final String globalKey;
  final int timestamp;

  Message(this.text, this.globalKey, this.timestamp);
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  late Timer _timer;
  String _myGlobalKey = ''; // added state variable
  final ScrollController _scrollController = ScrollController();

  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _displayMessages(widget.sharedKey, widget.friendIndex);
    _getGlobalKey().then((value) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (needsMessageUpdate) {
          _displayMessages(widget.sharedKey, widget.friendIndex);
        }
      });
      setState(() {
        _myGlobalKey = value;
      });
    });
  }

  Future<void> _displayMessages(String sharedKey, int index) async {
    List<Message> fetchedMessages = [];
    String publicKey = getPublicKey(sharedKey);

    // Fetch messages from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    String messagesHistoryString = prefs.getString('messagesHistory') ?? '{}';
    Map<String, dynamic> messagesHistoryMap = jsonDecode(messagesHistoryString);

    if (messagesHistoryMap.containsKey(publicKey)) {
      List<dynamic> messagesHistory =
          messagesHistoryMap[publicKey] as List<dynamic>;
      for (var message in messagesHistory) {
        fetchedMessages.add(Message(
            message['message'], message['globalKey'], message['timestamp']));
      }
      needsMessageUpdate = false;
    }

    // Sort messages by timestamp
    fetchedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    // Clear existing messages and update UI with the fetched messages
    setState(() {
      _messages.clear();
      _messages.addAll(fetchedMessages);
    });

    if (!_keyboardVisible) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // Update the latestSeenMessage in friendsList
    if (fetchedMessages.isNotEmpty) {
      await _lock.synchronized(() async {
        int latestSeenMessageTimestamp = fetchedMessages.last.timestamp;
        List<String> friendsList = prefs.getStringList('friends') ?? [];
        Map<String, dynamic> friendData =
            jsonDecode(friendsList[widget.friendIndex]) as Map<String, dynamic>;
        friendData['latestSeenMessage'] = latestSeenMessageTimestamp;
        friendsList[widget.friendIndex] = json.encode(friendData);
        await prefs.setStringList('friends', friendsList);
        needsUpdate = true;
        needsChatListUpdate = true;
      });
    }
  }

  Future<String> _getGlobalKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('global_key') ?? '';
  }

  void _sendMessage(String text) async {
    String globalKey = await _getGlobalKey();
    if (text.trim().isNotEmpty) {
      int timestamp = DateTime.now().millisecondsSinceEpoch;
      int secondsTimestamp = (timestamp / 1000).round();

      _textController.clear();

      String content = jsonEncode({
        'type': 'message',
        'globalKey': globalKey,
        'message': text.trim(),
      });
      String pubKey = getPublicKey(widget.sharedKey);
      await addSentMessage(pubKey, globalKey, text, secondsTimestamp);
      await postToNostr(widget.sharedKey, content);
      await _displayMessages(widget.sharedKey, widget.friendIndex);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.friendName),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Detect keyboard visibility based on scroll position
                  final pixels = notification.metrics.pixels;
                  final maxScrollExtent = notification.metrics.maxScrollExtent;
                  final minScrollExtent = notification.metrics.minScrollExtent;
                  final inScrollArea =
                      pixels < maxScrollExtent && pixels > minScrollExtent;
                  final isScrolling =
                      notification is ScrollUpdateNotification ||
                          notification is OverscrollNotification;
                  final visible = isScrolling || inScrollArea;
                  if (_keyboardVisible != visible) {
                    setState(() {
                      _keyboardVisible = visible;
                    });
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length,
                  addAutomaticKeepAlives: true,
                  itemBuilder: (BuildContext context, int index) {
                    return ChatBubble(
                      text: _messages[index].text,
                      globalKey: _messages[index].globalKey,
                      myGlobalKey: _myGlobalKey,
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20.0),
                        ),
                      ),
                      onSubmitted: (text) {
                        _sendMessage(text);
                      },
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  FloatingActionButton(
                    onPressed: () {
                      _sendMessage(_textController.text);
                    },
                    child: const Icon(Icons.send),
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

class ChatBubble extends StatelessWidget {
  final String text;
  final String globalKey;
  final String myGlobalKey;

  const ChatBubble(
      {Key? key,
      required this.text,
      required this.globalKey,
      required this.myGlobalKey})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isSent = globalKey == myGlobalKey;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
      child: Row(
        mainAxisAlignment:
            isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isSent ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isSent
                    ? const Radius.circular(12)
                    : const Radius.circular(0),
                bottomRight: isSent
                    ? const Radius.circular(0)
                    : const Radius.circular(12),
              ),
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isSent ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
