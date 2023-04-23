class DebugHelper {
  static final DebugHelper _instance = DebugHelper._internal();
  List<String> debugMessages = [];
  final void Function()? onNewMessage;

  factory DebugHelper() {
    return _instance;
  }

  DebugHelper._internal({this.onNewMessage});

  void addDebugMessage(String message) {
    debugMessages.insert(0, message);
    if (onNewMessage != null) {
      onNewMessage!();
    }
  }
}
