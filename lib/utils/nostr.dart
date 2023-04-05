import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nostr/nostr.dart';

void startListeningToEvents(VoidCallback onQRScanSuccess) async {
  String targetPublicKey = '1fbdef9c96a182ad318bcefba2b3c1c120be51179b8e97a47c09d9409e03c793';

  // Create a subscription message request with filters
  Request requestWithFilter = Request(generate64RandomHexChars(), [
    Filter(
      //authors: [targetPublicKey], // Add the target public key here
      kinds: [1],
      since: 0,
      limit: 450,
    )
  ]);

  onQRScanSuccess(); // Call the callback after a successful QR scan

  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    'wss://relay.nostr.info', // or any nostr relay
  );
  // if the current socket fail try another one
  // wss://nostr.sandwich.farm
  // wss://relay.damus.io

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  // Listen for events from the WebSocket server
  await Future.delayed(Duration(seconds: 1));
  webSocket.listen((event) {
    print('Received event: $event');
  });

  // Close the WebSocket connection
  await webSocket.close();
}
