import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encryptor;
import 'package:fairshare/providers/chat.dart';
import 'package:fairshare/providers/friend.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nostr/nostr.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';

import './friends.dart';
import './location.dart';
import './messages.dart';
import '../main.dart';
import '../pages/friends_list_page.dart';
import '../pages/qr_scanner.dart';
import '../utils/debug_helper.dart';
import '../utils/notification_helper.dart';

List<String> defaultRelays = [
  'wss://nostr.fairshare.social',
  'wss://relay.damus.io',
  'wss://relay.snort.social',
];

List<WebSocket?> webSockets = List.filled(defaultRelays.length, null);

Map<String, dynamic> addingFriend = {};

Map<String, dynamic> latestEventTimestamps = {};

Map<String, dynamic> latestEventSigs = {};

Map<String, dynamic> latestLocationTimestamps = {};

bool receivedFriendRequest = false;
String newFriendPrivKey = '';

String eventSig = '';

bool successfulPost = false;

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

List<bool> isConnected = List<bool>.empty(growable: true);

Future<void> connectWebSocket(BuildContext context) async {
  final chatProvider = Provider.of<ChatProvider>(context, listen: false);
  final friendProvider = Provider.of<FriendProvider>(context, listen: false);
  await closeAllWebSockets();
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String>? relays = prefs.getStringList('relays');
  if (relays != null) {
    if (isConnected.length != relays.length) {
      isConnected = List<bool>.filled(relays.length, false);
    }
    for (int i = 0; i < relays.length; i++) {
      if (webSockets[i] == null ||
          webSockets[i]!.readyState == WebSocket.closed) {
        try {
          webSockets[i] = await WebSocket.connect(relays[i]).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException('Connection timeout');
            },
          );
          print('Websocket connection made ' + relays[i]);
          isConnected[i] = true;
          webSockets[i]!.listen((event) async {
            if (event.contains('EVENT')) {
              String currentEventSig = getEventSig(event);
              if (currentEventSig != eventSig) {
                eventSig = currentEventSig;
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
                if (privateKey == null) {
                  if (pubKey == prefs.getString('cycling_pub_key')) {
                    privateKey = prefs.getString('cycling_priv_key');
                  } else if (pubKey == scannedPubKey) {
                    privateKey = scannedPrivKey;
                  }
                }
                if (privateKey != null) {
                  try {
                    String decryptedContent =
                        decrypt(privateKey, encryptedContent);
                    content = json.decode(decryptedContent);
                  } catch (e) {
                    content = json.decode(encryptedContent);
                  }
                }
                if (content != null) {
                  Tuple2<int?, String?> latestEventInfo =
                      await getLatestReceivedEvent(pubKey);
                  int? lastReceived = latestEventInfo.item1;
                  String? lastEventSig = latestEventInfo.item2;
                  String globalKeyPriv = prefs.getString('global_key') ?? '';
                  String globalKey = getPublicKey(globalKeyPriv);
                  int timestamp = getCreatedAt(event);
                  int myLatestPost =
                      prefs.getInt('my_latest_post_timestamp') ?? 0;
                  if (globalKey == content['globalKey'] &&
                      timestamp > myLatestPost) {
                    prefs.setInt('my_latest_post_timestamp', timestamp);
                    successfulPost = true;
                    print('Successfully posted to Nostr (' + relays[i] + '):');
                    print(content);
                  } else {
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
                        addingFriend = content;
                      } else {
                        newFriendPrivKey = scannedPrivKey;
                      }
                      if (successfulPost) {
                        addingFriend = content;
                      }
                    } else if (content['globalKey'] != globalKey &&
                        content['globalKey'] != globalKeyPriv &&
                        content['type'] != 'handshake' &&
                        content['type'] != null &&
                        content['globalKey'] != null) {
                      if ((lastReceived == null || timestamp > lastReceived) &&
                          (lastEventSig != eventSig)) {
                        String debugString =
                            relays[i] + ': ' + jsonEncode(content);
                        if (content['image'] != null) {
                          debugString = relays[i] + ': image received';
                        }
                        DebugHelper().addDebugMessage(debugString);
                        print('received new event from existing friend (' +
                            relays[i] +
                            '): ');
                        print(content);
                        if (content['type'] == 'locationUpdate') {
                          int? latestLocationUpdate =
                              await getLatestLocationUpdate(pubKey);
                          latestLocationUpdate ??= 0;
                          if (latestLocationUpdate < timestamp) {
                            await updateFriendsLocation(content, pubKey);
                            await setLatestLocationUpdate(timestamp, pubKey);
                          }
                        } else if (content['type'] == 'message') {
                          final List<String> friendInfo =
                              await getFriendInfo(pubKey);
                          final String friendName = friendInfo[0];
                          final int friendIndex =
                              int.tryParse(friendInfo[1]) ?? -1;
                          if (content['image'] != null) {
                            await addReceivedImage(
                                pubKey, globalKey, content['image'], timestamp);
                          } else {
                            String text = content['message'];
                            await addReceivedMessage(
                                pubKey, content['globalKey'], text, timestamp);
                          }

                          needsChatListUpdate = true;
                          if (friendIndex == chatProvider.friendIndex) {
                            chatProvider.load(context);
                          } else {
                            displayNotification(
                                friendName, 'Message', friendIndex);
                          }
                        }

                        friendProvider.load(showLoading: false);
                        await setLatestReceivedEvent(timestamp, pubKey);
                        await setLatestReceivedEventSig(eventSig, pubKey);
                      }
                    }
                  }
                }
              }
            }
          });
        } catch (e) {
          if (e is TimeoutException) {
            print('Failed to connect due to timeout: ' + relays[i].toString());
          } else {
            print('Failed to connect to: ' + relays[i].toString());
          }
          if (webSockets[i] != null) {
            await webSockets[i]!.close();
            webSockets[i] = null;
          }
          isConnected[i] = false;
        }
      }
    }
  }
}

Future<void> closeAllWebSockets() async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String>? relays = prefs.getStringList('relays');
  if (relays != null) {
    for (WebSocket? ws in webSockets) {
      if (ws != null) {
        await ws.close();
      }
    }
    webSockets = List.filled(relays.length, null);
  }
}

Future<void> closeWebSocket(int index) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String>? relays = prefs.getStringList('relays');
  if (relays != null && index >= 0 && index < webSockets.length) {
    await webSockets[index]?.close();
    webSockets[index] = null;
  }
}

Future<List<String>> addSubscription({required List<String> publicKeys}) async {
  SharedPreferences prefs = SharedPreferencesHelper().prefs;
  List<String>? relays = prefs.getStringList('relays');
  if (relays != null) {
    List<String> subscriptionIds = [];
    for (int i = 0; i < relays.length; i++) {
      String subscriptionId = generate64RandomHexChars();
      Request requestWithFilter = Request(subscriptionId, [
        Filter(
          authors: publicKeys,
          kinds: [1],
          since: 0,
          limit: 450,
        )
      ]);

      // if (webSockets[i] == null) {
      //   print('reconnecting websocket');
      //   await connectWebSocket();
      // }
      if (webSockets[i] != null) {
        webSockets[i]!.add(requestWithFilter.serialize());
        print('added subscription (id: ' + subscriptionId + ')');
        subscriptionIds.add(subscriptionId);
      }
    }
    return subscriptionIds;
  }
  return [];
}

Future<void> closeSubscription({required List<String> subscriptionIds}) async {
  if (subscriptionIds.isNotEmpty) {
    for (int i = 0; i < subscriptionIds.length; i++) {
      var close = Close(subscriptionIds[i]);

      if (webSockets[i] != null) {
        webSockets[i]!.add(close.serialize());
        print('closed subscription (id: ' + subscriptionIds[i] + ')');
      }
    }
  }
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

String getEventSig(String input) {
  // Parse the input string into a list
  List<dynamic> list = jsonDecode(input);

  // Get the content field from the third element of the list
  String content = list[2]['sig'];

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
  successfulPost = false;
  SharedPreferences prefs = SharedPreferencesHelper().prefs;

  List<String>? relays = prefs.getStringList('relays');

  String encryptedContent = encrypt(privateKey, content);
  Event eventToSend = Event.from(
      kind: 1, tags: [], content: encryptedContent, privkey: privateKey);

  // Iterate through the webSockets list and send the event to each connected WebSocket
  for (int i = 0; i < webSockets.length; i++) {
    try {
      if (webSockets[i] != null) {
        print('attempting to post to: ' + (relays?[i] ?? 'unknown'));

        webSockets[i]!.add(eventToSend.serialize());
      }
    } catch (e) {}
  }
}

String encrypt(String privateKey, String content) {
  final key = encryptor.Key.fromUtf8(privateKey.substring(0, 32));
  final iv = encryptor.IV.fromLength(16); // Generate a 16-byte IV
  final encrypter =
      encryptor.Encrypter(encryptor.AES(key, mode: encryptor.AESMode.cbc));
  final encrypted = encrypter.encrypt(content, iv: iv);
  return base64.encode(iv.bytes + encrypted.bytes);
}

String decrypt(String privateKey, String encryptedContent) {
  final key = encryptor.Key.fromUtf8(privateKey.substring(0, 32));
  final encryptedData = base64.decode(encryptedContent);
  final iv = encryptor.IV(encryptedData.sublist(0, 16));
  final encryptedBytes = Uint8List.fromList(encryptedData.sublist(16));
  final encrypted = encryptor.Encrypted(encryptedBytes);
  final decrypter =
      encryptor.Encrypter(encryptor.AES(key, mode: encryptor.AESMode.cbc));
  return decrypter.decrypt(encrypted, iv: iv);
}
