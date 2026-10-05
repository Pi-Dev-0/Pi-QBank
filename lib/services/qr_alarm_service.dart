import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrAlarm {
  const QrAlarm({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.qrCodeName,
    required this.qrValue,
    required this.enabled,
  });

  final String id;
  final String label;
  final int hour;
  final int minute;
  final List<int> weekdays;
  final String qrCodeName;
  final String qrValue;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'qrCodeName': qrCodeName,
        'qrValue': qrValue,
        'enabled': enabled,
      };

  factory QrAlarm.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final legacyToken = json['qrToken'] as String?;
    return QrAlarm(
      id: id,
      label: json['label'] as String? ?? 'Alarm',
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      weekdays: (json['weekdays'] as List<dynamic>? ?? const []).cast<int>(),
      qrCodeName: json['qrCodeName'] as String? ?? 'Saved QR code',
      qrValue: json['qrValue'] as String? ??
          (legacyToken == null ? '' : 'piqbank://qr-alarm/$id/$legacyToken'),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class SavedQrCode {
  const SavedQrCode({
    required this.id,
    required this.name,
    required this.value,
  });

  final String id;
  final String name;
  final String value;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'value': value};

  factory SavedQrCode.fromJson(Map<String, dynamic> json) => SavedQrCode(
        id: json['id'] as String,
        name: json['name'] as String,
        value: json['value'] as String,
      );
}

class QrAlarmService {
  static const _prefsKey = 'qr_alarms_v1';
  static const _savedCodesKey = 'qr_alarm_saved_codes_v1';
  static const _channel = MethodChannel('com.pi.mathematics/qr_alarm');

  static Future<List<QrAlarm>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    String? raw;
    try {
      raw = await _channel.invokeMethod<String>('loadAlarms');
    } on MissingPluginException {
      raw = prefs.getString(_prefsKey);
    } on PlatformException {
      raw = prefs.getString(_prefsKey);
    }
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => QrAlarm.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAlarms(List<QrAlarm> alarms) async {
    final encoded = jsonEncode(alarms.map((alarm) => alarm.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, encoded);
    try {
      await _channel.invokeMethod<void>('syncAlarms', encoded);
      if (alarms.any((alarm) => alarm.enabled)) {
        await _channel.invokeMethod<void>('requestNotificationPermission');
        await _channel.invokeMethod<void>('requestExactAlarmPermission');
      }
    } on MissingPluginException {
      // Alarm scheduling and notifications are provided by Android.
    }
  }

  static Future<List<SavedQrCode>> loadSavedQrCodes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedCodesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => SavedQrCode.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveQrCode(SavedQrCode code) async {
    final codes = await loadSavedQrCodes();
    final existingIndex = codes.indexWhere((item) => item.value == code.value);
    if (existingIndex >= 0) {
      codes[existingIndex] = SavedQrCode(
        id: codes[existingIndex].id,
        name: code.name,
        value: code.value,
      );
    } else {
      codes.add(code);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _savedCodesKey,
      jsonEncode(codes.map((item) => item.toJson()).toList()),
    );
  }

  static Future<bool> dismissByQr(String qrValue) async {
    try {
      return await _channel.invokeMethod<bool>('dismissByQr', qrValue) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> dismissEmergency() async {
    try {
      return await _channel.invokeMethod<bool>('dismissEmergency') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
