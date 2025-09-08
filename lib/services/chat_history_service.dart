import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart';
import '../models/chat_message_model.dart';

class ChatHistoryService {
  static const String _historyKey = 'chat_history';
  static const int _maxHistoryLength = 5;

  // Encryption setup
  // IMPORTANT: In a real application, the key and IV should be securely generated and stored,
  // not hardcoded like this. This is for demonstration purposes only.
  static final Key _key = Key.fromLength(32); // 256-bit key
  static final IV _iv = IV.fromLength(16); // 128-bit IV
  static final Encrypter _encrypter = Encrypter(AES(_key));

  Future<List<List<ChatMessageModel>>> loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedHistory = prefs.getStringList(_historyKey) ?? [];
    
    List<List<ChatMessageModel>> history = [];
    List<String> validEncryptedHistory = []; // To store only successfully decrypted chats

    for (String encryptedChat in encryptedHistory) {
      try {
        final decrypted = _encrypter.decrypt64(encryptedChat, iv: _iv);
        final List<dynamic> chatJson = json.decode(decrypted);
        final chatMessages = chatJson.map((msgJson) => ChatMessageModel.fromJson(msgJson)).toList();
        history.add(chatMessages);
        validEncryptedHistory.add(encryptedChat); // Add to valid list
      } catch (e) {
        print("Error decrypting or decoding chat history: $e. Removing corrupted entry.");
        // If decryption fails, this entry is skipped and not added to validEncryptedHistory
      }
    }
    // Save only the valid history back to SharedPreferences
    await prefs.setStringList(_historyKey, validEncryptedHistory);
    return history;
  }

  Future<void> saveChat(List<ChatMessageModel> chat) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert current chat to JSON
    final chatJson = chat.map((msg) => msg.toJson()).toList();
    final chatString = json.encode(chatJson);

    // Encrypt the chat string
    final encrypted = _encrypter.encrypt(chatString, iv: _iv);
    final encryptedChatString = encrypted.base64;

    // Load existing history, add new chat, and enforce max length
    List<String> encryptedHistory = prefs.getStringList(_historyKey) ?? [];
    encryptedHistory.insert(0, encryptedChatString); // Add to the beginning
    if (encryptedHistory.length > _maxHistoryLength) {
      encryptedHistory = encryptedHistory.sublist(0, _maxHistoryLength);
    }

    await prefs.setStringList(_historyKey, encryptedHistory);
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
