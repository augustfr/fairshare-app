import 'package:shared_preferences/shared_preferences.dart';

Future<List<String>> loadFriends() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  List<String> friendsList = prefs.getStringList('friends') ?? [];
  return friendsList;
}
