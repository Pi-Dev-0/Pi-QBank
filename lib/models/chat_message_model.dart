import 'dart:convert';

class ChatMessageModel {
  final String text;
  final bool isUser;
  final String? imagePath; // Path to the image file if user sent an image
  final String? base64Image; // Base64 encoded image if AI generated an image
  final String? userImageBase64; // Base64 encoded image if user sent an image

  ChatMessageModel({
    required this.text,
    required this.isUser,
    this.imagePath,
    this.base64Image,
    this.userImageBase64,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'isUser': isUser,
      'imagePath': imagePath,
      'base64Image': base64Image,
      'userImageBase64': userImageBase64,
    };
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      text: json['text'],
      isUser: json['isUser'],
      imagePath: json['imagePath'],
      base64Image: json['base64Image'],
      userImageBase64: json['userImageBase64'],
    );
  }
}
