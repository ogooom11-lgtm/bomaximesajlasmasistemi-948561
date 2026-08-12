import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/telegram_models.dart';

class SettingsStore extends ChangeNotifier {
  static const _tokenKey = 'telegram_bot_token';
  static const _apiBaseUrlKey = 'telegram_api_base_url';
  static const _preferredChatKey = 'preferred_chat_id';
  static const _darkModeKey = 'dark_mode';
  static const _soundsKey = 'sounds_enabled';
  static const _notificationsKey = 'notifications_enabled';
  static const _lockHashKey = 'app_lock_hash';
  static const _chatNamesKey = 'custom_chat_names';
  static const _messageArchiveKey = 'message_archive_v1';

  SharedPreferences? _prefs;

  String _botToken = '';
  String _apiBaseUrl = 'https://api.telegram.org';
  int? _preferredChatId;
  bool _darkMode = true;
  bool _soundsEnabled = true;
  bool _notificationsEnabled = true;
  String? _lockHash;
  final Map<int, String> _customChatNames = <int, String>{};

  String get botToken => _botToken;
  String get apiBaseUrl => _apiBaseUrl;
  int? get preferredChatId => _preferredChatId;
  bool get hasBotToken => _botToken.trim().isNotEmpty;
  bool get darkMode => _darkMode;
  bool get soundsEnabled => _soundsEnabled;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get hasPassword => _lockHash != null && _lockHash!.isNotEmpty;
  Map<int, String> get customChatNames =>
      Map<int, String>.unmodifiable(_customChatNames);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _botToken = _prefs?.getString(_tokenKey) ?? '';
    _apiBaseUrl =
        _prefs?.getString(_apiBaseUrlKey) ?? 'https://api.telegram.org';
    _preferredChatId = int.tryParse(_prefs?.getString(_preferredChatKey) ?? '');
    _darkMode = _prefs?.getBool(_darkModeKey) ?? true;
    _soundsEnabled = _prefs?.getBool(_soundsKey) ?? true;
    _notificationsEnabled = _prefs?.getBool(_notificationsKey) ?? true;
    _lockHash = _prefs?.getString(_lockHashKey);
    _loadCustomChatNames();
  }

  Future<void> setBotConfig({
    required String token,
    String? apiBaseUrl,
    int? preferredChatId,
  }) async {
    _botToken = token.trim();
    _apiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl);
    _preferredChatId = preferredChatId;
    await _prefs?.setString(_tokenKey, _botToken);
    await _prefs?.setString(_apiBaseUrlKey, _apiBaseUrl);
    if (preferredChatId == null) {
      await _prefs?.remove(_preferredChatKey);
    } else {
      await _prefs?.setString(_preferredChatKey, preferredChatId.toString());
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _prefs?.setBool(_darkModeKey, value);
    notifyListeners();
  }

  Future<void> setSoundsEnabled(bool value) async {
    _soundsEnabled = value;
    await _prefs?.setBool(_soundsKey, value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    await _prefs?.setBool(_notificationsKey, value);
    notifyListeners();
  }

  String? customChatName(int chatId) {
    final value = _customChatNames[chatId];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  Future<void> setCustomChatName(int chatId, String? name) async {
    final normalized = name?.trim() ?? '';
    if (normalized.isEmpty) {
      _customChatNames.remove(chatId);
    } else {
      _customChatNames[chatId] = normalized;
    }
    await _prefs?.setString(
      _chatNamesKey,
      jsonEncode(
        _customChatNames.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
    notifyListeners();
  }

  Map<int, List<TelegramMessage>> loadMessageArchive() {
    final raw = _prefs?.getString(_messageArchiveKey);
    if (raw == null || raw.isEmpty) {
      return <int, List<TelegramMessage>>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <int, List<TelegramMessage>>{};
    }
    final result = <int, List<TelegramMessage>>{};
    for (final entry in decoded.entries) {
      final chatId = int.tryParse(entry.key.toString());
      final rawMessages = entry.value;
      if (chatId == null || rawMessages is! List) {
        continue;
      }
      result[chatId] =
          rawMessages
              .map(
                (item) => item is Map
                    ? item.map((key, value) => MapEntry(key.toString(), value))
                    : null,
              )
              .whereType<Map<String, dynamic>>()
              .map(TelegramMessage.fromCacheJson)
              .where((message) => message.id.isNotEmpty)
              .toList(growable: true)
            ..sort((a, b) => a.date.compareTo(b.date));
    }
    return result;
  }

  Future<void> saveMessageArchive(
    Map<int, List<TelegramMessage>> messagesByChat,
  ) async {
    const maxMessagesPerChat = 500;
    final encoded = <String, dynamic>{};
    for (final entry in messagesByChat.entries) {
      final messages = List<TelegramMessage>.from(entry.value)
        ..sort((a, b) => a.date.compareTo(b.date));
      final trimmed = messages.length > maxMessagesPerChat
          ? messages.sublist(messages.length - maxMessagesPerChat)
          : messages;
      encoded[entry.key.toString()] = trimmed
          .map((message) => message.toCacheJson())
          .toList();
    }
    await _prefs?.setString(_messageArchiveKey, jsonEncode(encoded));
  }

  Future<void> setPassword(String password) async {
    final normalized = password.trim();
    if (normalized.isEmpty) {
      await clearPassword();
      return;
    }
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _lockHash = '$salt:${_hashPassword(normalized, salt)}';
    await _prefs?.setString(_lockHashKey, _lockHash!);
    notifyListeners();
  }

  Future<void> clearPassword() async {
    _lockHash = null;
    await _prefs?.remove(_lockHashKey);
    notifyListeners();
  }

  bool verifyPassword(String password) {
    final stored = _lockHash;
    if (stored == null || stored.isEmpty) {
      return true;
    }
    final parts = stored.split(':');
    if (parts.length != 2) {
      return false;
    }
    return _hashPassword(password.trim(), parts.first) == parts.last;
  }

  String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  String _normalizeApiBaseUrl(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'https://api.telegram.org';
    }
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  void _loadCustomChatNames() {
    _customChatNames.clear();
    final raw = _prefs?.getString(_chatNamesKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return;
    }
    for (final entry in decoded.entries) {
      final id = int.tryParse(entry.key.toString());
      final value = entry.value?.toString().trim();
      if (id != null && value != null && value.isNotEmpty) {
        _customChatNames[id] = value;
      }
    }
  }
}
