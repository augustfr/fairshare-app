import 'dart:async';

class DebugHelper {
  static final DebugHelper _instance = DebugHelper._internal();
  List<String> debugMessages = [];

  final StreamController<String> _debugMessageController =
      StreamController<String>.broadcast();

  Stream<String> get debugMessagesStream => _debugMessageController.stream;

  factory DebugHelper() {
    return _instance;
  }

  DebugHelper._internal() {
    debugMessages = [];
    debugMessagesStream.listen((message) {
      debugMessages.insert(0, message); // insert new messages at the beginning
    });
  }

  void addDebugMessage(String message) {
    _debugMessageController.add(message);
  }
}
