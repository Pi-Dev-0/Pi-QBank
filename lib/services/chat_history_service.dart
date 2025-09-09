import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message_model.dart';

class ChatHistoryService {
  static const String _historyKey = 'chat_history';
  static const int _maxHistoryLength = 5;

  Future<List<List<ChatMessageModel>>> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJsonStrings = prefs.getStringList(_historyKey) ?? [];
    
    List<List<ChatMessageModel>> history = [];
    List<String> validHistoryJsonStrings = []; // To store only successfully parsed chats

    for (String chatJsonString in historyJsonStrings) {
      try {
        final List<dynamic> chatJson = json.decode(chatJsonString);
        final chatMessages = chatJson.map((msgJson) => ChatMessageModel.fromJson(msgJson)).toList();
        history.add(chatMessages);
        validHistoryJsonStrings.add(chatJsonString); // Add to valid list
      } catch (e) {
        // If parsing fails, skip this entry
        continue;}
    }
    // Save only the valid history back to SharedPreferences
    await prefs.setStringList(_historyKey, validHistoryJsonStrings);
    return history;
  }

  Future<int> saveChat(List<ChatMessageModel> chat) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert current chat to JSON
    final chatJson = chat.map((msg) => msg.toJson()).toList();
    final chatString = json.encode(chatJson);

    // Load existing history, add new chat, and enforce max length
    List<String> historyJsonStrings = prefs.getStringList(_historyKey) ?? [];
    historyJsonStrings.insert(0, chatString); // Add to the beginning
    if (historyJsonStrings.length > _maxHistoryLength) {
      historyJsonStrings = historyJsonStrings.sublist(0, _maxHistoryLength);
    }

    await prefs.setStringList(_historyKey, historyJsonStrings);
    return 0; // Return the index of the newly added chat (which is always 0)
  }

  Future<void> updateChat(int index, List<ChatMessageModel> chat) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> historyJsonStrings = prefs.getStringList(_historyKey) ?? [];

    if (index >= 0 && index < historyJsonStrings.length) {
      // Convert updated chat to JSON
      final chatJson = chat.map((msg) => msg.toJson()).toList();
      final chatString = json.encode(chatJson);

      historyJsonStrings[index] = chatString; // Update the chat at the specified index
      await prefs.setStringList(_historyKey, historyJsonStrings);
    }
  }

  Future<void> deleteChatAtIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> encryptedHistory = prefs.getStringList(_historyKey) ?? [];
    if (index >= 0 && index < encryptedHistory.length) {
      encryptedHistory.removeAt(index);
      await prefs.setStringList(_historyKey, encryptedHistory);
    }
  }

  Future<void> clearChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
}
