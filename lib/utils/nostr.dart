import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nostr/nostr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './location.dart';
import './friends.dart';
import './messages.dart';
import '../pages/chat_page.dart';
import '../pages/home_page.dart';
import '../pages/friends_list_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:encrypt/encrypt.dart';
import 'package:encrypt/encrypt_io.dart';
import '../pages/qr_scanner.dart';

String relay = 'wss://nostr.fairshare.social';

WebSocket? webSocket;
Timer? timer;

Map<String, dynamic> addingFriend = {};

Map<String, dynamic> latestEventTimestamps = {};

Map<String, dynamic> latestLocationTimestamps = {};

bool receivedFriendRequest = false;
String newFriendPrivKey = '';

String eventId = '';

Future<void> connectWebSocket() async {
  if (webSocket == null || webSocket!.readyState == WebSocket.closed) {
    webSocket = await WebSocket.connect(relay);
    print('Websocket connection made ' + relay);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    webSocket!.listen((event) async {
      if (event.contains('EVENT')) {
        String currentEventId = getEventId(event);
        if (currentEventId != eventId) {
          eventId = currentEventId;
          String pubKey = getPubkey(event);
          String encryptedContent = getContent(event);
          List<dynamic> friendsList = await loadFriends();
          String? privateKey;
          Map<String, dynamic>? content;

          for (var friend in friendsList) {
            dynamic decodedFriend = jsonDecode(friend);
            if (getPublicKey(decodedFriend['privateKey']) == pubKey) {
              privateKey = decodedFriend['privateKey'];
              break;
            }
          }
          if (privateKey != null) {
            try {
              String decryptedContent = decrypt(privateKey, encryptedContent);
              content = json.decode(decryptedContent);
            } catch (e) {
              content = json.decode(encryptedContent);
            }
          }
          if (content != null) {
            int? lastReceived = await getLatestReceivedEvent(pubKey);
            String globalKey = prefs.getString('global_key') ?? '';
            int timestamp = getCreatedAt(event);
            if (((pubKey == prefs.getString('cycling_pub_key')) ||
                    pubKey == scannedPubKey) &&
                content['globalKey'] != globalKey &&
                (lastReceived == null || timestamp > lastReceived)) {
              await setLatestReceivedEvent(timestamp, pubKey);
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
                newFriendPrivKey = privateKey;
              } else {
                newFriendPrivKey = scannedPrivKey;
              }
              if (privateKey != null) {
                addingFriend = content;
              }
            } else if (content['globalKey'] != globalKey &&
                content['type'] != 'handshake' &&
                content['type'] != null &&
                content['globalKey'] != null) {
              if (lastReceived == null || timestamp > lastReceived) {
                print('received new event from existing friend');
                if (content['type'] == 'locationUpdate') {
                  int? latestLocationUpdate =
                      await getLatestLocationUpdate(pubKey);
                  latestLocationUpdate ??= 0;
                  if (latestLocationUpdate < timestamp) {
                    await updateFriendsLocation(content, pubKey);
                    await setLatestLocationUpdate(timestamp, pubKey);
                  }
                  needsUpdate = true;
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
        }
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
  print('added subscription (id: ' + subscriptionId + '):');

  return subscriptionId;
}

Future<void> closeSubscription({required String subscriptionId}) async {
  var close = Close(subscriptionId);

  if (webSocket == null) {
    print('reconnecting websocket');
    await connectWebSocket();
  }

  webSocket!.add(close.serialize());
  print('closed subscription (id: ' + subscriptionId + ')');
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

String getEventId(String input) {
  // Parse the input string into a list
  List<dynamic> list = jsonDecode(input);

  // Get the content field from the third element of the list
  String content = list[2]['id'];

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
  String encryptedContent = encrypt(privateKey, content);
  Event eventToSend = Event.from(
      kind: 1, tags: [], content: encryptedContent, privkey: privateKey);

  if (webSocket == null) {
    print('reconnected websocket');
    await connectWebSocket();
  }
  webSocket!.add(eventToSend.serialize());
}

String encrypt(String privateKey, String content) {
  final key = Key.fromUtf8(privateKey.substring(0, 32));
  final iv = IV.fromLength(16); // Generate a 16-byte IV
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  final encrypted = encrypter.encrypt(content, iv: iv);
  return base64.encode(iv.bytes + encrypted.bytes);
}

String decrypt(String privateKey, String encryptedContent) {
  final key = Key.fromUtf8(privateKey.substring(0, 32));
  final encryptedData = base64.decode(encryptedContent);
  final iv = IV(encryptedData.sublist(0, 16));
  final encryptedBytes = Uint8List.fromList(encryptedData.sublist(16));
  final encrypted = Encrypted(encryptedBytes);
  final decrypter = Encrypter(AES(key, mode: AESMode.cbc));
  return decrypter.decrypt(encrypted, iv: iv);
}
