import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:google_maps_example/pages/qr_scanner.dart';
import 'package:nostr/nostr.dart';

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
    'wss://relay.damus.io', // or any nostr relay
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

Future<List<String>> getPreviousEvents(
    {required List<String> publicKeys}) async {
  Completer<List<String>> eventsCompleter = Completer();
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
    'wss://relay.damus.io', // or any nostr relay
  );

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  Timer timer = Timer(const Duration(seconds: loopTime), () async {
    await webSocket.close();
  });

  // Listen for events from the WebSocket server
  webSocket.listen((event) {
    //print('Received event: $event');
    if (event.contains('global_key')) {
      // Extract the JSON string from the event
      int start = event.indexOf('global_key') - 3;
      int end = event.indexOf('}') + 1;
      String jsonString = event.substring(start, end);
      jsonString = jsonString.replaceAll('\\', '');
      // Add the JSON string to the eventsList
      eventsList.add(jsonString);
    }

    // Check if the event contains the string "EOSE"
    if (event.contains('EOSE')) {
      // Close the WebSocket and complete the eventsCompleter
      webSocket.close().then((_) {
        timer.cancel(); // Cancel the timer when the connection is closed
        eventsCompleter.complete(eventsList);
      });
    }
  }, onDone: () {
    if (!eventsCompleter.isCompleted) {
      timer.cancel(); // Cancel the timer when the connection is closed
      eventsCompleter.complete(eventsList);
    }
  });

  return eventsCompleter.future;
}

Future<String> listenForConfirm({required String publicKey}) async {
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
    'wss://relay.damus.io', // or any nostr relay
  );

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  Timer timer = Timer(const Duration(seconds: loopTime), () async {
    await webSocket.close();
  });

  // Listen for events from the WebSocket server
  webSocket.listen((event) {
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
  // Instantiate an event with a partial data and let the library sign the event with your private key
  Event eventToSend =
      Event.from(kind: 1, tags: [], content: content, privkey: privateKey);
  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    'wss://relay.damus.io', // or any nostr relay
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
