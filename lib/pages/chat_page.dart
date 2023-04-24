import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import '../utils/nostr.dart';
import '../utils/messages.dart';
import 'package:synchronized/synchronized.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
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
  final String type;
  final String? text;
  final String? image;
  final String? media;
  final String globalKey;
  final int timestamp;
  final bool showDate;

  Message(
      {required this.type,
      this.text,
      this.image,
      this.media,
      required this.showDate,
      required this.globalKey,
      required this.timestamp});
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  late Timer _timer;
  String _myGlobalKey = '';
  final ScrollController _scrollController = ScrollController();
  File? _image;
  final _listKey = GlobalKey<AnimatedListState>();

  @override
  void didChangeMetrics() {
    final mediaQuery = MediaQuery.of(context);
    if (mediaQuery.viewInsets.bottom > 0) {
      _scrollToBottom();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _displayMessages(widget.sharedKey, widget.friendIndex);
    _getGlobalKey().then((value) {
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (needsMessageUpdate) {
          _displayMessages(widget.sharedKey, widget.friendIndex);
        }
      });
      setState(() {
        _myGlobalKey = value;
      });
    });
  }

  Future<void> _getImage(ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
      });
      await _sendImage();
    }
  }

  Future<void> _sendImage() async {
    if (_image != null) {
      String globalKey = await _getGlobalKey();
      Uint8List imageData;
      if (await _image!.exists()) {
        String fileType = path.extension(_image!.path).toLowerCase();
        if (fileType == '.png') {
          imageData = await _image!.readAsBytes();
        } else if (fileType == '.heic') {
          File convertedFile = await FlutterNativeImage.compressImage(
            _image!.path,
            quality: 100, // set the desired quality level here
            targetWidth: 600, // set the desired width here
            targetHeight: 600, // set the desired height here
          );
          imageData = await compressFile(convertedFile.path);
        } else {
          imageData = await compressFile(_image!.path);
        }

        String content = jsonEncode({
          'type': 'message',
          'globalKey': getPublicKey(globalKey),
          'image': base64Encode(imageData),
        });
        String pubKey = getPublicKey(widget.sharedKey);
        int timestamp = DateTime.now().millisecondsSinceEpoch;
        int secondsTimestamp = (timestamp / 1000).round();
        await postToNostr(widget.sharedKey, content);
        await addSentImage(
            pubKey, globalKey, base64Encode(imageData), secondsTimestamp);
        await _displayMessages(widget.sharedKey, widget.friendIndex);
        _image = null;
      }
    }
  }

  Future<Uint8List> compressFile(String filePath) async {
    final file = File(filePath);
    Uint8List imageData = await file.readAsBytes();

    // Set custom dimensions
    int maxWidth = 800;
    int maxHeight = 600;

    // Decode image
    img.Image? originalImage = img.decodeImage(imageData);

    // Check if originalImage is not null
    if (originalImage != null) {
      // Calculate aspect ratio
      double aspectRatio = originalImage.width / originalImage.height;
      int targetWidth, targetHeight;

      // Determine new dimensions based on aspect ratio
      if (originalImage.width >= originalImage.height) {
        targetWidth = maxWidth;
        targetHeight = (maxWidth / aspectRatio).round();
      } else {
        targetHeight = maxHeight;
        targetWidth = (maxHeight * aspectRatio).round();
      }

      // Resize image
      img.Image resizedImage = img.copyResize(
        originalImage,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.nearest,
      );

      // Define an initial quality value
      int quality = 80;
      Uint8List compressedImage;

      // Compress image iteratively to reach the target size
      do {
        // Encode resized image to Uint8List
        Uint8List resizedImageData =
            img.encodeJpg(resizedImage, quality: quality);

        // Compress image
        compressedImage = await FlutterImageCompress.compressWithList(
          resizedImageData,
          quality: quality,
        );

        // Reduce quality by 5 for the next iteration if needed
        quality -= 5;
      } while (compressedImage.lengthInBytes > 100 * 1024 && quality > 0);

      return compressedImage;
    } else {
      return Uint8List(0);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
      DateTime? previousDate;

      for (var message in messagesHistory) {
        DateTime currentMessageDate =
            DateTime.fromMillisecondsSinceEpoch(message['timestamp'] * 1000);
        bool showDate = false;

        if (previousDate == null ||
            currentMessageDate.day != previousDate.day ||
            currentMessageDate.month != previousDate.month ||
            currentMessageDate.year != previousDate.year) {
          showDate = true;
        }

        fetchedMessages.add(Message(
            type: message['type'], // 'sent' or 'received'
            media: message['media'] == 'image'
                ? 'image'
                : null, // 'image' for images, null for text messages
            text: message['media'] == 'text'
                ? message['message']
                : message['media'] == null
                    ? message['message']
                    : null, // set to 'message' if media is null (text message)
            image: message['media'] == 'image' ? message['image'] : null,
            globalKey: message['globalKey'],
            timestamp: message['timestamp'],
            showDate: showDate)); // Set showDate property based on comparison

        previousDate = currentMessageDate;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

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
        'globalKey': getPublicKey(globalKey),
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
    WidgetsBinding.instance.removeObserver(this);
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
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length,
                  addAutomaticKeepAlives: true,
                  itemBuilder: (BuildContext context, int index) {
                    return ChatBubble(
                      listKey: _listKey,
                      text: _messages[index].text,
                      image: _messages[index].image,
                      globalKey: _messages[index].globalKey,
                      myGlobalKey: _myGlobalKey,
                      timestamp: _messages[index].timestamp,
                      showDate: _messages[index].showDate,
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
                  IconButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (BuildContext context) {
                          return SafeArea(
                            child: Wrap(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.camera_alt),
                                  title: const Text('Take a picture'),
                                  onTap: () {
                                    _getImage(ImageSource.camera);
                                    Navigator.of(context).pop();
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.image),
                                  title: const Text('Select from gallery'),
                                  onTap: () {
                                    _getImage(ImageSource.gallery);
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.image),
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
  final String? text;
  final String? image;
  final String globalKey;
  final String myGlobalKey;
  final GlobalKey<AnimatedListState>? listKey;
  final int timestamp;
  final bool showDate;

  const ChatBubble({
    Key? key,
    this.text,
    this.image,
    required this.globalKey,
    required this.myGlobalKey,
    required this.listKey,
    required this.timestamp,
    required this.showDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool isSent = globalKey == myGlobalKey;

    Widget content = image != null
        ? GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return Scaffold(
                      appBar: AppBar(),
                      body: Center(
                        child: Image.memory(
                          base64Decode(image!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            child: AspectRatio(
              aspectRatio: 1.0,
              child: Image.memory(
                base64Decode(image!),
                fit: BoxFit.cover,
              ),
            ),
          )
        : Text(
            text ?? '',
            style: TextStyle(
              color: isSent ? Colors.white : Colors.black,
            ),
          );

    String formattedDate = DateFormat('EEEE, MMMM d').format(
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double maxWidth = constraints.maxWidth * 0.6;
        if (listKey?.currentState != null) {
          listKey!.currentState!.insertItem(0);
        }

        return SizedBox(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDate)
                  Text(
                    formattedDate,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  DateFormat('hh:mm a').format(
                      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
                Row(
                  mainAxisAlignment:
                      isSent ? MainAxisAlignment.end : MainAxisAlignment.start,
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
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
                      child: content,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ImagePage extends StatelessWidget {
  final String? image;

  const ImagePage({Key? key, required this.image}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: image == null
            ? const Text('No image')
            : AspectRatio(
                aspectRatio: 1,
                child: Image.memory(
                  base64Decode(image!),
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }
}
