import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:nostr/nostr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './location.dart';
import './friends.dart';
import './messages.dart';
import '../pages/chat_page.dart';
import '../pages/home_page.dart';
import '../pages/friends_list_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../pages/qr_scanner.dart';

String relay = 'wss://nostr.fairshare.social';

WebSocket? webSocket;
Timer? timer;

Map<String, dynamic> addingFriend = {};

Map<String, dynamic> latestEventTimestamps = {};

Map<String, dynamic> latestLocationTimestamps = {};

bool receivedFriendRequest = false;
String newFriendPrivKey = '';

Future<void> connectWebSocket() async {
  if (webSocket == null || webSocket!.readyState == WebSocket.closed) {
    webSocket = await WebSocket.connect(relay);
    print('Websocket connection made ' + relay);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    webSocket!.listen((event) async {
      if (event.contains('EVENT')) {
        Map<String, dynamic> content = json.decode(getContent(event));
        String pubKey = getPubkey(event);
        String globalKey = prefs.getString('global_key') ?? '';
        int timestamp = getCreatedAt(event);
        if (((pubKey == prefs.getString('cycling_pub_key')) ||
                pubKey == scannedPubKey) &&
            content['globalKey'] != globalKey) {
          String? privateKey = prefs.getString('cycling_priv_key');
          String? name = prefs.getString('user_name');
          LatLng savedLocation = await getSavedLocation();
          String currentLocationString = savedLocation.toString();
          String jsonBody = '{"type": "handshake", "name": "' +
              (name ?? 'Anonymous') +
              '", "currentLocation": "' +
              currentLocationString +
              '", "globalKey": "' +
              (globalKey) +
              '"}';
          if (privateKey != null && pubKey != scannedPubKey) {
            await postToNostr(privateKey, jsonBody);
          }
          if (privateKey != null) {
            newFriendPrivKey = privateKey;
            addingFriend = content;
          }
        } else if (content['globalKey'] != globalKey &&
            content['type'] != 'handshake' &&
            content['type'] != null) {
          int? lastReceived = await getLatestReceivedEvent(pubKey);
          if (lastReceived == null || timestamp > lastReceived) {
            print('received new event from existing friend');
            if (content['type'] == 'locationUpdate') {
              await updateFriendsLocation(content, pubKey);
              await setLatestLocationUpdate(timestamp, pubKey);
              print('updated friends location');
            } else if (content['type'] == 'message') {
              String text = content['message'];
              await addReceivedMessage(
                  pubKey, content['globalKey'], text, timestamp);
              needsMessageUpdate = true;
              needsUpdate = true;
              needsChatListUpdate = true;
            }
            await setLatestReceivedEvent(timestamp, pubKey);
          }
        }
        // print(pubKey + ': ');
        // print(content);
      }
    });
  }
}

Future<void> closeWebSocket() async {
  await webSocket!.close();
  webSocket = null;
}

Future<String> addSubscription({required List<String> publicKeys}) async {
  String subscriptionId = generate64RandomHexChars();
  print('subscribed pub key:');
  print(publicKeys);
  Request requestWithFilter = Request(subscriptionId, [
    Filter(
      authors: publicKeys,
      kinds: [1],
      since: 0,
      limit: 450,
    )
  ]);

  if (webSocket == null) {
    print('reconnecting websocket');
    await connectWebSocket();
  }

  webSocket!.add(requestWithFilter.serialize());
  print('added subscription: ' + subscriptionId);

  return subscriptionId;
}

Future<void> closeSubscription({required String subscriptionId}) async {
  var close = Close(subscriptionId);

  if (webSocket == null) {
    print('reconnecting websocket');
    await connectWebSocket();
  }

  webSocket!.add(close.serialize());
  print('closed subscription: ' + subscriptionId);
}

String getPubkey(String input) {
  // Parse the input string into a list
  List<dynamic> list = jsonDecode(input);

  // Get the content field from the third element of the list
  String content = list[2]['pubkey'];

  // Return the content
  return content;
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

  if (webSocket == null) {
    print('reconnected websocket');
    await connectWebSocket();
  }
  // Send an event to the WebSocket server
  webSocket!.add(eventToSend.serialize());

  // Listen for events from the WebSocket server
  // await Future.delayed(const Duration(seconds: 1));
  // webSocket!.listen((event) {
  //   print('Received event: $event');
  // });
}
