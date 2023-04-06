import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/nostr.dart';

class ChatPage extends StatefulWidget {
  final String friendName;
  final String sharedKey;

  const ChatPage({
    Key? key,
    required this.friendName,
    required this.sharedKey,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class Message {
  final String text;
  final String globalKey;

  Message(this.text, this.globalKey);
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];

  @override
  void initState() {
    super.initState();
    _startListeningToEvents(publicKeys: [getPublicKey(widget.sharedKey)]);
  }

  Future<String> _getGlobalKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('global_key') ?? '';
  }

  void _startListeningToEvents({required List<String> publicKeys}) {
    startListeningToEvents(publicKeys: publicKeys);
    // Add the code to listen to Nostr events and update the _messages list
    // when new messages arrive.
  }

  void _sendMessage(String text) async {
    String globalKey = await _getGlobalKey();
    if (text.trim().isNotEmpty) {
      setState(() {
        _messages.add(Message(text.trim(), globalKey));
      });
      _textController.clear();

      int timestamp = DateTime.now().millisecondsSinceEpoch;
      String content = jsonEncode({
        'global_key': globalKey,
        'message': text.trim(),
        'timestamp': timestamp,
      });

      postToNostr(widget.sharedKey, content);
    }
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
              child: FutureBuilder<String>(
                future: _getGlobalKey(),
                builder:
                    (BuildContext context, AsyncSnapshot<String> snapshot) {
                  if (snapshot.hasData) {
                    String myGlobalKey = snapshot.data!;
                    return ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (BuildContext context, int index) {
                        return ChatBubble(
                          text: _messages[index].text,
                          globalKey: _messages[index].globalKey,
                          myGlobalKey: myGlobalKey,
                        );
                      },
                    );
                  } else {
                    return const Center(child: CircularProgressIndicator());
                  }
                },
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
