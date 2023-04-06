import 'dart:io';
import 'dart:async';
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
    'wss://relay.nostr.info', // or any nostr relay
  );
  // if the current socket fails, try another one
  // wss://nostr.sandwich.farm
  // wss://relay.damus.io

  // Send a request message to the WebSocket server
  webSocket.add(requestWithFilter.serialize());

  // Listen for events from the WebSocket server
  await Future.delayed(const Duration(seconds: 1));
  webSocket.listen((event) {
    print('Received event: $event');
  });

  // Close the WebSocket connection
  await webSocket.close();
}

String generateRandomPrivateKey() {
  var randomKeys = Keychain.generate();
  return randomKeys.private;
}

String getPublicKey(privateKey) {
  return Keychain(privateKey).public;
}

Future<void> postToNostr(String privateKey, String content) async {
  // Create a partial event from nothing and fill it with data until it is valid
  var eventToSend = Event.partial();
  assert(eventToSend.isValid() == false);
  eventToSend.createdAt = currentUnixTimestampSeconds();
  eventToSend.pubkey = getPublicKey(privateKey);
  eventToSend.id = eventToSend.getEventId();
  eventToSend.sig = eventToSend.getSignature(privateKey);
  assert(eventToSend.isValid() == true);

  // Instantiate an event with a partial data and let the library sign the event with your private key
  Event anotherEvent =
      Event.from(kind: 1, tags: [], content: content, privkey: privateKey);
  // Connecting to a nostr relay using websocket
  WebSocket webSocket = await WebSocket.connect(
    'wss://relay.damus.io', // or any nostr relay
  );

  // Send an event to the WebSocket server
  webSocket.add(anotherEvent.serialize());

  // Listen for events from the WebSocket server
  await Future.delayed(const Duration(seconds: 1));
  webSocket.listen((event) {
    print('Received event: $event');
  });

  // Close the WebSocket connection
  await webSocket.close();
}
