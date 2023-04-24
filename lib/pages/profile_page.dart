import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import '../utils/nostr.dart';
import '../utils/friends.dart';
import '../pages/home_page.dart';
import '../main.dart';
import '../utils/debug_helper.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _name;
  String? _globalKey;

  List<String> _relays = [];

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;
    String? name = prefs.getString('user_name');
    String? globalKey = prefs.getString('global_key');
    List<String>? relays = prefs.getStringList('relays') ?? [];
    setState(() {
      _name = name;
      _globalKey = getPublicKey(globalKey);
      _relays = relays;
    });
  }

  Future<void> _resetAndCloseApp() async {
    SharedPreferences prefs = SharedPreferencesHelper().prefs;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete All Data?'),
          content: const Text(
              'Are you sure you want to delete all data? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await prefs.clear();
                if (Platform.isAndroid) {
                  SystemChannels.platform
                      .invokeMethod<void>('SystemNavigator.pop');
                } else if (Platform.isIOS) {
                  exit(0);
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeAllFriends() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove All Friends?'),
          content: const Text(
              'Are you sure you want to remove all of your friends? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                removeAllFriends();
                Navigator.pop(context); // Close the dialog
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomePage()),
                );
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  void _updateRelay(int index) async {
    await closeWebSocket(index);
    final TextEditingController _textController =
        TextEditingController(text: "wss://");
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Update Relay'),
          content: TextField(
            controller: _textController,
            decoration: const InputDecoration(hintText: 'Enter new name'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Update'),
              onPressed: () async {
                final String newRelayName = _textController.text;
                final SharedPreferences prefs = SharedPreferencesHelper().prefs;
                final List<String> relays =
                    prefs.getStringList('relays') ?? <String>[];
                relays[index] = newRelayName;
                await prefs.setStringList('relays', relays);
                await connectWebSocket();
                setState(() {
                  _relays = relays;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _refresh() async {
    await connectWebSocket();
    final SharedPreferences prefs = SharedPreferencesHelper().prefs;
    final List<String> relays = prefs.getStringList('relays') ?? <String>[];
    setState(() {
      _relays = relays;
    });
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(
        text: _globalKey ?? 'None')); // copy the user ID to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('User ID copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _importData(BuildContext context) async {
    TextEditingController _controller = TextEditingController();

    // Prompt user to paste JSON data
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Paste Exported Data"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: "JSON Data",
                  hintText: "Paste your exported data here",
                ),
                maxLines: 5,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: const Text("Import"),
              onPressed: () async {
                String jsonData = _controller.text;
                Navigator.pop(context);
                await _processImport(context, jsonData);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _processImport(BuildContext context, String jsonData) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    print(prefs.getString('user_name'));
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 16.0),
                Text("Importing data..."),
              ],
            ),
          ),
        );
      },
    );

    Map<String, dynamic> data = jsonDecode(jsonData);
    for (var key in data.keys) {
      final value = data[key];
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(key, value);
      } else if (value is List<dynamic>) {
        List<String> stringList = value.map((e) => e.toString()).toList();
        await prefs.setStringList(key, stringList);
      }
    }

    // Dismiss loading dialog
    Navigator.pop(context);

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Data imported successfully."),
      ),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(),
                SizedBox(width: 16.0),
                Text("Exporting data..."),
              ],
            ),
          ),
        );
      },
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    Set<String> keys = prefs.getKeys();

    Map<String, dynamic> data = {};
    for (var key in keys) {
      if (key != 'cycling_priv_key' &&
          key != 'cycling_subscription_id' &&
          key != 'cycling_pub_key' &&
          key != 'cycling_subscription_ids') {
        data[key] = prefs.get(key);
      }
    }

    String jsonData = jsonEncode(data);

    Directory appDocDir = await getApplicationDocumentsDirectory();
    File jsonFile = File('${appDocDir.path}/fairshare_data.json');
    await jsonFile.writeAsString(jsonData);

    // Dismiss loading dialog
    Navigator.pop(context);

    // Show data to user
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Exported data"),
          content: SingleChildScrollView(
            child: Text(jsonData),
          ),
          actions: [
            TextButton(
              child: const Text("Copy"),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonData));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Data copied to clipboard."),
                  ),
                );
              },
            ),
            TextButton(
              child: const Text("Email"),
              onPressed: () async {
                String subject = "My FairShare data";
                String body = "Here is my FairShare data.";
                String filePath = jsonFile.path;
                List<String> recipients = []; // Add recipients here

                final Email email = Email(
                  body: body,
                  subject: subject,
                  recipients: recipients,
                  attachmentPaths: [filePath],
                  isHTML: false,
                );

                try {
                  await FlutterEmailSender.send(email);
                } catch (error) {
                  print(error);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Could not send email: $error"),
                    ),
                  );
                }
              },
            ),
            TextButton(
              child: const Text("Close"),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showNameInputDialog(BuildContext context) {
    String newName = _name ?? '';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Name'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Enter your name'),
            onChanged: (value) {
              newName = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                SharedPreferences prefs = SharedPreferencesHelper().prefs;
                prefs.setString('user_name', newName);
                setState(() {
                  _name = newName;
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDebugWindow() {
    return Container(
      margin: const EdgeInsets.all(20),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey[200],
        boxShadow: const [
          BoxShadow(
            color: Colors.grey,
            blurRadius: 5.0,
          ),
        ],
      ),
      child: StreamBuilder<String>(
        stream: DebugHelper().debugMessagesStream,
        builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Error loading debug messages'),
            );
          }
          return ListView(
            reverse: true,
            children: DebugHelper()
                .debugMessages
                .map((message) => ListTile(title: Text(message)))
                .toList(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 10,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Center(
                    child: GestureDetector(
                      onTap: () => _showNameInputDialog(context),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          Text(
                            _name ?? 'Anonymous',
                            style: Theme.of(context).textTheme.headlineSmall!,
                          ),
                          GestureDetector(
                            onTap: () => _copyToClipboard(),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.grey[200],
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.grey,
                                    blurRadius: 5.0,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'User ID',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SelectableText(
                                    _globalKey ?? 'Anonymous',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall!
                                        .copyWith(
                                          fontSize: 14.0,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Relays:',
                                style:
                                    Theme.of(context).textTheme.headlineSmall!,
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => _refresh(),
                                child: const Icon(
                                  Icons.refresh,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Column(
                            children: List.generate(_relays.length, (index) {
                              return GestureDetector(
                                onTap: () {
                                  _updateRelay(index);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Colors.grey[200],
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.grey,
                                        blurRadius: 5.0,
                                      ),
                                    ],
                                    border: Border.all(
                                      color: isConnected.isNotEmpty &&
                                              isConnected[index]
                                          ? Colors.green
                                          : Colors.red,
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    _relays[index],
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDebugWindow(),
                ],
              ),
              const SizedBox(height: 50),
              Padding(
                padding: const EdgeInsets.all(50.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: _removeAllFriends,
                      child: const Text('Remove All Friends'),
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all<Color>(Colors.red),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _resetAndCloseApp,
                      child: const Text('Delete All Data'),
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all<Color>(Colors.red),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _exportData(context);
                      },
                      child: const Text('Export Data'),
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all<Color>(Colors.red),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _importData(context);
                      },
                      child: const Text('Import Data'),
                      style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all<Color>(Colors.red),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
