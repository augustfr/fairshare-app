import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:google_maps_example/pages/qr_scanner.dart';
import 'package:nostr/nostr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

final _lock = Lock();

String relay = 'wss://relay.snort.social';

void startListeningToEvents({required List<String> publicKeys}) async {
  // Create a subscription message request with filters
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      authors: publicKeys, // Listen to an array of public keys
      kinds: [1],
      since: 0,
      limit: 450,
    )
  ]);

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    relay, // or any nostr relay
  );

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  Timer timer = Timer(const Duration(seconds: loopTime), () async {
    await webSocket.close();
  });

  // Listen for events from the WebSocket server
  webSocket.listen((event) {
    print('Received event: $event');
  }, onDone: () {
    timer.cancel(); // Cancel the timer when the connection is closed
  });
}

//used specifically for getting messages
Future<List<String>> getPreviousEvents(
    {required List<String> publicKeys,
    required int friendIndex,
    required bool markAsRead}) async {
  Completer<List<String>> eventsCompleter = Completer();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String> friendsList = [];

  await _lock.synchronized(() async {
    friendsList = prefs.getStringList('friends') ?? [];
  });

  List<String> eventsList = [];

  // Create a subscription message request with filters
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      authors: publicKeys, // Listen to an array of public keys
      kinds: [1],
      since: 0,
      limit: 450,
    )
  ]);

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    relay, // or any nostr relay
  );

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  Timer timer = Timer(const Duration(seconds: loopTime), () async {
    await webSocket.close();
  });

  // Listen for events from the WebSocket server
  webSocket.listen((event) {
    if (event.contains('global_key')) {
      String content = getContent(event);
      if (content.contains('timestamp')) {
        eventsList.add(content);
        // Update latestMessage if necessary
        int currentTimestamp = getTimestamp(content);
        Map<String, dynamic> friendData = json.decode(friendsList[friendIndex]);
        if ((currentTimestamp > (friendData['latestMessage'] ?? 0)) &&
            markAsRead) {
          friendData['latestMessage'] = currentTimestamp;
          friendsList[friendIndex] = json.encode(friendData);
          _lock.synchronized(() async {
            prefs.setStringList('friends', friendsList);
          });
        }
      }
    }

    // Check if the event contains the string "EOSE"
    if (event.contains('EOSE')) {
      webSocket.close().then((_) {
        timer.cancel();
        eventsCompleter.complete(eventsList);
      });
    }
  }, onDone: () {
    if (!eventsCompleter.isCompleted) {
      timer.cancel();
      eventsCompleter.complete(eventsList);
    }
  });

  return eventsCompleter.future;
}

int getTimestamp(String content) {
  Map<String, dynamic> contentMap = jsonDecode(content);
  int timestamp = contentMap['timestamp'] ??
      0; // Provide a default value of 0 if timestamp is null
  return timestamp;
}

String getGlobalKey(String content) {
  Map<String, dynamic> contentMap = jsonDecode(content);
  String globalKey = contentMap['global_key'];
  return globalKey;
}

Future<String?> getFriendsLastLocation({
  required List<String> publicKeys,
}) async {
  Completer<String?> eventCompleter = Completer();
  final prefs = await SharedPreferences.getInstance();
  String globalKey = prefs.getString('global_key') ?? '';
  //globalKey = '123';
  // Create a subscription message request with filters
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      authors: publicKeys, // Listen to an array of public keys
      kinds: [1],
      since: 0,
      limit: 450,
    )
  ]);

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(relay);

  String? mostRecentEventWithLocation;

  webSocket.add(requestWithFilter.serialize());

  webSocket.listen((event) {
    // Check if the event contains the string "currentLocation"
    if (event.contains('currentLocation')) {
      String jsonString = getContent(event);
      //print(jsonString);
      Map<String, dynamic> jsonContent = jsonDecode(jsonString);

      // Check if the global_key in the event matches globalKey
      if (jsonContent['global_key'] != globalKey &&
          jsonContent['global_key'] != null) {
        // Get the content and createdAt from the event
        int createdAt = getCreatedAt(event);

        // Check if this is the most recent "currentLocation" event
        if (mostRecentEventWithLocation == null ||
            createdAt > getCreatedAt(mostRecentEventWithLocation!)) {
          mostRecentEventWithLocation = event;
        }
      }
    }

    // Check if the event contains the string "EOSE"
    if (event.contains('EOSE')) {
      // Close the WebSocket and complete the eventCompleter with the content of the most recent "currentLocation" event
      webSocket.close().then((_) {
        if (mostRecentEventWithLocation != null) {
          String jsonString = getContent(mostRecentEventWithLocation!);
          eventCompleter.complete(jsonString);
        } else {
          eventCompleter.complete(null);
        }
      });
    }
  });

  return eventCompleter.future;
}

Future<String> listenForConfirm({required String publicKey}) async {
  print(publicKey);
  // Create a completer for returning the event
  Completer<String> completer = Completer<String>();

  // Create a subscription message request with filters
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      authors: [publicKey], // Listen to an array of public keys
      kinds: [1],
      since: 0,
      limit: 10,
    )
  ]);

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    relay, // or any nostr relay
  );

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  Timer timer = Timer(const Duration(seconds: loopTime), () async {
    await webSocket.close();
  });

  // Listen for events from the WebSocket server
  webSocket.listen((event) {
    print('listening for confirm');
    print(event);
    //print('Received event: $event');
    // Complete the completer with the received event
    if (!event.contains("EOSE")) {
      // Complete the completer with the received event if it doesn't contain "EOSE"
      completer.complete(event);
    }
  }, onDone: () {
    timer.cancel(); // Cancel the timer when the connection is closed
  });

  // Return the future from the completer
  return completer.future;
}

String generateRandomPrivateKey() {
  var randomKeys = Keychain.generate();
  return randomKeys.private;
}

String getPublicKey(privateKey) {
  return Keychain(privateKey).public;
}

Future<void> postToNostr(String privateKey, String content) async {
  print('Posting to Nostr: ' +
      content +
      'at this pub key: ' +
      getPublicKey(privateKey));
  // Instantiate an event with a partial data and let the library sign the event with your private key
  Event eventToSend =
      Event.from(kind: 1, tags: [], content: content, privkey: privateKey);
  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    'wss://relay.snort.social', // or any nostr relay
  );
  // Send an event to the WebSocket server
  webSocket.add(eventToSend.serialize());

  // Listen for events from the WebSocket server
  await Future.delayed(const Duration(seconds: 1));
  webSocket.listen((event) {
    print('Received event: $event');
  });

  // Close the WebSocket connection
  await webSocket.close();
}

String getContent(String input) {
  // Parse the input string into a list
  List<dynamic> list = jsonDecode(input);

  // Get the content field from the third element of the list
  String content = list[2]['content'];

  // Return the content
  return content;
}

int getCreatedAt(String input) {
  // Parse the input string into a list
  List<dynamic> list = jsonDecode(input);

  // Get the content field from the third element of the list
  int content = list[2]['created_at'];

  // Return the content
  return content;
}
