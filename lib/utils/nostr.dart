import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:nostr/nostr.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';
import './location.dart';

final _lock = Lock();

String relay = 'wss://nostr.fairshare.social';

WebSocket? webSocket;
Timer? timer;

Map<String, dynamic> addingFriend = {};

Future<void> connectWebSocket() async {
  if (webSocket == null || webSocket!.readyState == WebSocket.closed) {
    webSocket = await WebSocket.connect(relay);
    print('Websocket connection made ' + relay);
    SharedPreferences prefs = await SharedPreferences.getInstance();

    webSocket!.listen((event) async {
      if (event.contains('EVENT')) {
        Map<String, dynamic> content = json.decode(getContent(event));
        String pubKey = getPubkey(event);

        if (pubKey == prefs.getString('cycling_pub_key')) {
          //for adding a new friend when user's qr code is scanned
          print('received event to add new friend');
          addingFriend = content;
        } else if (content['globalKey'] != prefs.getString('global_key') &&
            content['type'] != 'handshake' &&
            content['type'] != null) {
          print('received event from existing friend');
          if (content['type'] == 'locationUpdate') {
            await updateFriendsLocation(content, pubKey);
            print('updated friends location');
          }
        }
        //await updateFriendsLocation(content, pubKey);
        print(pubKey + ': ');
        print(content);
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

// //used specifically for getting messages
// Future<List<String>> getPreviousEvents(
//     {required List<String> publicKeys,
//     required int friendIndex,
//     required bool markAsRead}) async {
//   print('listening with getPreviousEvents function');
//   Completer<List<String>> eventsCompleter = Completer();
//   SharedPreferences prefs = await SharedPreferences.getInstance();
//   List<String> friendsList = [];

//   await _lock.synchronized(() async {
//     friendsList = prefs.getStringList('friends') ?? [];
//   });

//   List<String> eventsList = [];

//   // Create a subscription message request with filters
//   Request requestWithFilter = Request(generate64RandomHexChars(), [
//     Filter(
//       authors: publicKeys, // Listen to an array of public keys
//       kinds: [1],
//       since: 0,
//       limit: 450,
//     )
//   ]);

//   // Send a request message to the WebSocket server
//   webSocket!.add(requestWithFilter.serialize());

//   // Timer timer = Timer(loopTime, () async {
//   //   await webSocket.close();
//   // });

//   // Listen for events from the WebSocket server
//   StreamSubscription? subscription;
//   subscription = _streamController.stream.listen((event) {
//     if (event.contains('global_key')) {
//       String content = getContent(event);
//       if (content.contains('timestamp')) {
//         eventsList.add(content);
//         // Update latestMessage if necessary
//         int currentTimestamp = getTimestamp(content);
//         Map<String, dynamic> friendData = json.decode(friendsList[friendIndex]);
//         if ((currentTimestamp > (friendData['latestMessage'] ?? 0)) &&
//             markAsRead) {
//           friendData['latestMessage'] = currentTimestamp;
//           friendsList[friendIndex] = json.encode(friendData);
//           _lock.synchronized(() async {
//             prefs.setStringList('friends', friendsList);
//           });
//         }
//       }
//     }

//     // Check if the event contains the string "EOSE"
//     if (event.contains('EOSE')) {
//       eventsCompleter.complete(eventsList);
//       subscription?.cancel();
//     }
//   });

//   return eventsCompleter.future;
// }

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

// Future<String?> getFriendsLastLocation({
//   required List<String> publicKeys,
// }) async {
//   print('listening with getFriendsLastLocation function');
//   Completer<String?> eventCompleter = Completer();
//   final prefs = await SharedPreferences.getInstance();
//   String globalKey = prefs.getString('global_key') ?? '';
//   //globalKey = '123';
//   // Create a subscription message request with filters
//   Request requestWithFilter = Request(generate64RandomHexChars(), [
//     Filter(
//       authors: publicKeys, // Listen to an array of public keys
//       kinds: [1],
//       since: 0,
//       limit: 450,
//     )
//   ]);

//   String? mostRecentEventWithLocation;
//   if (webSocket == null) {
//     print('reconnected websocket');
//     await connectWebSocket();
//   }
//   webSocket!.add(requestWithFilter.serialize());

//   StreamSubscription? subscription;
//   subscription = _streamController.stream.listen((event) {
//     // Check if the event contains the string "currentLocation"
//     if (event.contains('currentLocation')) {
//       String jsonString = getContent(event);
//       //print(jsonString);
//       Map<String, dynamic> jsonContent = jsonDecode(jsonString);

//       // Check if the global_key in the event matches globalKey
//       if (jsonContent['global_key'] != globalKey &&
//           jsonContent['global_key'] != null) {
//         // Get the content and createdAt from the event
//         int createdAt = getCreatedAt(event);

//         // Check if this is the most recent "currentLocation" event
//         if (mostRecentEventWithLocation == null ||
//             createdAt > getCreatedAt(mostRecentEventWithLocation!)) {
//           mostRecentEventWithLocation = event;
//         }
//       }
//     }

//     // Check if the event contains the string "EOSE"
//     if (event.contains('EOSE')) {
//       // Close the WebSocket and complete the eventCompleter with the content of the most recent "currentLocation" event

//       if (mostRecentEventWithLocation != null) {
//         String jsonString = getContent(mostRecentEventWithLocation!);
//         eventCompleter.complete(jsonString);
//       } else {
//         eventCompleter.complete(null);
//       }
//       subscription?.cancel();
//     }
//   });

//   return eventCompleter.future;
// }

// Future<String> listenForConfirm({required String publicKey}) async {
//   print(getPublicKey(
//       'd7ac40dcf1cc1a72a03935ff65b4291123fce82753140fdadac76bc69db26557')); //be52dc4dcb2307c0e552be4239b9a800a6c1d96e69e8505362859d0cd6bc9666
//   print('listening in listenForConfirm function at: ' + publicKey);
//   // Create a completer for returning the event
//   Completer<String> completer = Completer<String>();

//   // Create a subscription message request with filters
//   Request requestWithFilter = Request(generate64RandomHexChars(), [
//     Filter(
//       authors: [publicKey], // Listen to an array of public keys
//       kinds: [1],
//       since: 0,
//       limit: 10,
//     )
//   ]);

//   if (webSocket == null) {
//     print('reconnected websocket');
//     await connectWebSocket();
//   }
//   // Send a request message to the WebSocket server
//   webSocket!.add(requestWithFilter.serialize());

//   bool isCompleted = false;

//   if (streamSubscription != null) {
//     streamSubscription!.onData((event) {
//       print('listening');
//       if (!isCompleted && event.contains("EVENT")) {
//         print('got message in confirm function without eose: ');
//         print(event);

//         completer.complete(event);
//         isCompleted = true;
//       }
//     });
//   }

//   // Return the future from the completer
//   return completer.future;
// }

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
