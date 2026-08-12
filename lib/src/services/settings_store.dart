import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/telegram_models.dart';

class AccountProfile {
  AccountProfile({
    required this.id,
    required this.label,
    required this.botToken,
    this.apiBaseUrl = 'https://api.telegram.org',
    this.preferredChatId,
    this.lockHash,
    Map<int, String>? customChatNames,
    int? createdAt,
  })  : customChatNames = customChatNames ?? <int, String>{},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String label;
  String botToken;
  String apiBaseUrl;
  int? preferredChatId;
  String? lockHash;
  Map<int, String> customChatNames;
  final int createdAt;

  bool get hasPassword => lockHash != null && lockHash!.isNotEmpty;

  String get displayLabel {
    if (label.trim().isNotEmpty) return label.trim();
    if (botToken.length > 12) {
      return 'بوت ${botToken.substring(0, 10)}...';
    }
    return 'حساب $id';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'bot_token': botToken,
      'api_base_url': apiBaseUrl,
      'preferred_chat_id': preferredChatId,
      'lock_hash': lockHash,
      'custom_chat_names':
          customChatNames.map((k, v) => MapEntry(k.toString(), v)),
      'created_at': createdAt,
    };
  }

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    final rawNames = json['custom_chat_names'];
    final names = <int, String>{};
    if (rawNames is Map) {
      for (final e in rawNames.entries) {
        final key = int.tryParse(e.key.toString());
        final val = e.value?.toString().trim();
        if (key != null && val != null && val.isNotEmpty) {
          names[key] = val;
        }
      }
    }
    return AccountProfile(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      label: json['label']?.toString() ?? 'حساب',
      botToken: json['bot_token']?.toString() ?? '',
      apiBaseUrl: (json['api_base_url']?.toString() ?? 'https://api.telegram.org').trim().isEmpty
          ? 'https://api.telegram.org'
          : json['api_base_url'].toString(),
      preferredChatId: json['preferred_chat_id'] is int
          ? json['preferred_chat_id'] as int
          : int.tryParse(json['preferred_chat_id']?.toString() ?? ''),
      lockHash: json['lock_hash']?.toString(),
      customChatNames: names,
      createdAt: json['created_at'] is int
          ? json['created_at'] as int
          : int.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  AccountProfile copyWith({
    String? label,
    String? botToken,
    String? apiBaseUrl,
    int? preferredChatId,
    String? lockHash,
    bool clearLock = false,
    bool clearPreferred = false,
    Map<int, String>? customChatNames,
  }) {
    return AccountProfile(
      id: id,
      label: label ?? this.label,
      botToken: botToken ?? this.botToken,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      preferredChatId: clearPreferred ? null : (preferredChatId ?? this.preferredChatId),
      lockHash: clearLock ? null : (lockHash ?? this.lockHash),
      customChatNames: customChatNames ?? Map<int, String>.from(this.customChatNames),
      createdAt: createdAt,
    );
  }
}

class SettingsStore extends ChangeNotifier {
  // Legacy keys
  static const _tokenKey = 'telegram_bot_token';
  static const _apiBaseUrlKey = 'telegram_api_base_url';
  static const _preferredChatKey = 'preferred_chat_id';
  static const _darkModeKey = 'dark_mode';
  static const _soundsKey = 'sounds_enabled';
  static const _notificationsKey = 'notifications_enabled';
  static const _lockHashKey = 'app_lock_hash';
  static const _chatNamesKey = 'custom_chat_names';
  static const _messageArchiveKey = 'message_archive_v1';

  // New keys
  static const _accountsKey = 'accounts_v2';
  static const _activeAccountIdKey = 'active_account_id_v2';

  SharedPreferences? _prefs;

  List<AccountProfile> _accounts = [];
  String? _activeAccountId;

  // Global settings
  bool _darkMode = true;
  bool _soundsEnabled = true;
  bool _notificationsEnabled = true;

  // Legacy single values for migration
  String _legacyBotToken = '';
  String _legacyApiBaseUrl = 'https://api.telegram.org';
  int? _legacyPreferredChatId;
  String? _legacyLockHash;
  final Map<int, String> _legacyCustomNames = {};

  // Getters
  List<AccountProfile> get accounts => List<AccountProfile>.unmodifiable(_accounts);
  AccountProfile? get activeAccount {
    if (_activeAccountId == null) return null;
    try {
      return _accounts.firstWhere((a) => a.id == _activeAccountId);
    } catch (_) {
      return _accounts.isNotEmpty ? _accounts.first : null;
    }
  }

  String? get activeAccountId => _activeAccountId;

  String get botToken => activeAccount?.botToken ?? _legacyBotToken;
  String get apiBaseUrl => activeAccount?.apiBaseUrl ?? _legacyApiBaseUrl;
  int? get preferredChatId => activeAccount?.preferredChatId ?? _legacyPreferredChatId;
  bool get hasBotToken => botToken.trim().isNotEmpty;

  bool get darkMode => _darkMode;
  bool get soundsEnabled => _soundsEnabled;
  bool get notificationsEnabled => _notificationsEnabled;

  bool get hasPassword {
    if (activeAccount != null) return activeAccount!.hasPassword;
    return _legacyLockHash != null && _legacyLockHash!.isNotEmpty;
  }

  Map<int, String> get customChatNames {
    if (activeAccount != null) {
      return Map<int, String>.unmodifiable(activeAccount!.customChatNames);
    }
    return Map<int, String>.unmodifiable(_legacyCustomNames);
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    // Global
    _darkMode = _prefs?.getBool(_darkModeKey) ?? true;
    _soundsEnabled = _prefs?.getBool(_soundsKey) ?? true;
    _notificationsEnabled = _prefs?.getBool(_notificationsKey) ?? true;

    // Legacy
    _legacyBotToken = _prefs?.getString(_tokenKey) ?? '';
    _legacyApiBaseUrl = _prefs?.getString(_apiBaseUrlKey) ?? 'https://api.telegram.org';
    _legacyPreferredChatId = int.tryParse(_prefs?.getString(_preferredChatKey) ?? '');
    _legacyLockHash = _prefs?.getString(_lockHashKey);
    _loadLegacyCustomNames();

    // New accounts
    final rawAccounts = _prefs?.getString(_accountsKey);
    if (rawAccounts != null && rawAccounts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAccounts);
        if (decoded is List) {
          _accounts = decoded
              .map((e) => e is Map ? e.map((k, v) => MapEntry(k.toString(), v)) : null)
              .whereType<Map<String, dynamic>>()
              .map(AccountProfile.fromJson)
              .where((a) => a.botToken.trim().isNotEmpty)
              .toList();
        }
      } catch (_) {
        _accounts = [];
      }
    }

    _activeAccountId = _prefs?.getString(_activeAccountIdKey);

    // Migration: if no accounts but legacy token exists -> create first account
    if (_accounts.isEmpty && _legacyBotToken.trim().isNotEmpty) {
      final migrated = AccountProfile(
        id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
        label: 'الحساب الرئيسي',
        botToken: _legacyBotToken,
        apiBaseUrl: _legacyApiBaseUrl,
        preferredChatId: _legacyPreferredChatId,
        lockHash: _legacyLockHash,
        customChatNames: Map<int, String>.from(_legacyCustomNames),
      );
      _accounts = [migrated];
      _activeAccountId = migrated.id;
      await _persistAccounts();
      await _prefs?.setString(_activeAccountIdKey, migrated.id);
      // Migrate archive if exists
      final oldArchive = _prefs?.getString(_messageArchiveKey);
      if (oldArchive != null && oldArchive.isNotEmpty) {
        await _prefs?.setString('${_messageArchiveKey}_${migrated.id}', oldArchive);
      }
    }

    if (_accounts.isNotEmpty && _activeAccountId == null) {
      _activeAccountId = _accounts.first.id;
      await _prefs?.setString(_activeAccountIdKey, _activeAccountId!);
    }

    // Ensure active id valid
    if (_activeAccountId != null && !_accounts.any((a) => a.id == _activeAccountId)) {
      _activeAccountId = _accounts.isNotEmpty ? _accounts.first.id : null;
      if (_activeAccountId != null) {
        await _prefs?.setString(_activeAccountIdKey, _activeAccountId!);
      } else {
        await _prefs?.remove(_activeAccountIdKey);
      }
    }
  }

  // Account management
  Future<AccountProfile> addAccount({
    required String label,
    required String token,
    String? apiBaseUrl,
    int? preferredChatId,
    String? password,
  }) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) throw ArgumentError('Token empty');

    final id = 'acc_${DateTime.now().millisecondsSinceEpoch}_${_accounts.length}';
    String? lockHash;
    if (password != null && password.trim().isNotEmpty) {
      final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      lockHash = '$salt:${_hashPassword(password.trim(), salt)}';
    }

    final account = AccountProfile(
      id: id,
      label: label.trim().isEmpty ? 'حساب ${_accounts.length + 1}' : label.trim(),
      botToken: normalizedToken,
      apiBaseUrl: _normalizeApiBaseUrl(apiBaseUrl),
      preferredChatId: preferredChatId,
      lockHash: lockHash,
    );
    _accounts = [..._accounts, account];
    _activeAccountId = account.id;
    await _persistAccounts();
    await _prefs?.setString(_activeAccountIdKey, account.id);
    notifyListeners();
    return account;
  }

  Future<void> setActiveAccount(String id) async {
    if (!_accounts.any((a) => a.id == id)) return;
    _activeAccountId = id;
    await _prefs?.setString(_activeAccountIdKey, id);
    notifyListeners();
  }

  Future<void> updateAccountLabel(String id, String newLabel) async {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _accounts[idx] = _accounts[idx].copyWith(label: newLabel.trim().isEmpty ? _accounts[idx].label : newLabel.trim());
    await _persistAccounts();
    notifyListeners();
  }

  Future<void> removeAccount(String id) async {
    final wasActive = _activeAccountId == id;
    _accounts = _accounts.where((a) => a.id != id).toList();
    // Remove its archive
    await _prefs?.remove('${_messageArchiveKey}_$id');
    if (wasActive) {
      _activeAccountId = _accounts.isNotEmpty ? _accounts.first.id : null;
      if (_activeAccountId != null) {
        await _prefs?.setString(_activeAccountIdKey, _activeAccountId!);
      } else {
        await _prefs?.remove(_activeAccountIdKey);
      }
    }
    await _persistAccounts();
    notifyListeners();
  }

  Future<void> updateAccountFull({
    required String id,
    String? label,
    String? token,
    String? apiBaseUrl,
    int? preferredChatId,
    bool clearPreferred = false,
    String? newPassword,
    bool clearPassword = false,
  }) async {
    final idx = _accounts.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    var acc = _accounts[idx];
    if (label != null) {
      acc = acc.copyWith(label: label.trim().isEmpty ? acc.label : label.trim());
    }
    if (token != null && token.trim().isNotEmpty) {
      acc = acc.copyWith(botToken: token.trim());
    }
    if (apiBaseUrl != null) {
      acc = acc.copyWith(apiBaseUrl: _normalizeApiBaseUrl(apiBaseUrl));
    }
    if (clearPreferred) {
      acc = acc.copyWith(clearPreferred: true);
    } else if (preferredChatId != null) {
      acc = acc.copyWith(preferredChatId: preferredChatId);
    }

    if (clearPassword) {
      acc = acc.copyWith(clearLock: true);
    } else if (newPassword != null && newPassword.trim().isNotEmpty) {
      final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final hash = '$salt:${_hashPassword(newPassword.trim(), salt)}';
      acc = acc.copyWith(lockHash: hash);
    }

    _accounts[idx] = acc;
    await _persistAccounts();
    notifyListeners();
  }

  // Legacy setBotConfig now updates active account or creates one
  Future<void> setBotConfig({
    required String token,
    String? apiBaseUrl,
    int? preferredChatId,
  }) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;
    final resolvedBase = _normalizeApiBaseUrl(apiBaseUrl);

    if (activeAccount != null) {
      final idx = _accounts.indexWhere((a) => a.id == activeAccount!.id);
      if (idx >= 0) {
        _accounts[idx] = _accounts[idx].copyWith(
          botToken: normalized,
          apiBaseUrl: resolvedBase,
          preferredChatId: preferredChatId,
          clearPreferred: preferredChatId == null,
        );
        await _persistAccounts();
      }
    } else {
      // No accounts, create one
      await addAccount(label: 'الحساب الرئيسي', token: normalized, apiBaseUrl: resolvedBase, preferredChatId: preferredChatId);
      // addAccount already persists and notifies
      return;
    }

    // Keep legacy keys updated for backward compat
    await _prefs?.setString(_tokenKey, normalized);
    await _prefs?.setString(_apiBaseUrlKey, resolvedBase);
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
    final map = activeAccount?.customChatNames ?? _legacyCustomNames;
    final value = map[chatId];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  Future<void> setCustomChatName(int chatId, String? name) async {
    final normalized = name?.trim() ?? '';
    if (activeAccount != null) {
      final idx = _accounts.indexWhere((a) => a.id == activeAccount!.id);
      if (idx < 0) return;
      final names = Map<int, String>.from(_accounts[idx].customChatNames);
      if (normalized.isEmpty) {
        names.remove(chatId);
      } else {
        names[chatId] = normalized;
      }
      _accounts[idx] = _accounts[idx].copyWith(customChatNames: names);
      await _persistAccounts();
    } else {
      if (normalized.isEmpty) {
        _legacyCustomNames.remove(chatId);
      } else {
        _legacyCustomNames[chatId] = normalized;
      }
      await _prefs?.setString(
        _chatNamesKey,
        jsonEncode(_legacyCustomNames.map((k, v) => MapEntry(k.toString(), v))),
      );
    }
    notifyListeners();
  }

  Map<int, List<TelegramMessage>> loadMessageArchive({String? accountId}) {
    final targetId = accountId ?? _activeAccountId;
    String? raw;
    if (targetId != null) {
      raw = _prefs?.getString('${_messageArchiveKey}_$targetId');
      // fallback to legacy if first account
      if ((raw == null || raw.isEmpty) && _accounts.length == 1) {
        raw = _prefs?.getString(_messageArchiveKey);
      }
    } else {
      raw = _prefs?.getString(_messageArchiveKey);
    }
    if (raw == null || raw.isEmpty) return <int, List<TelegramMessage>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <int, List<TelegramMessage>>{};
      final result = <int, List<TelegramMessage>>{};
      for (final entry in decoded.entries) {
        final chatId = int.tryParse(entry.key.toString());
        final rawMessages = entry.value;
        if (chatId == null || rawMessages is! List) continue;
        result[chatId] = rawMessages
            .map((item) => item is Map ? item.map((k, v) => MapEntry(k.toString(), v)) : null)
            .whereType<Map<String, dynamic>>()
            .map(TelegramMessage.fromCacheJson)
            .where((m) => m.id.isNotEmpty)
            .toList(growable: true)
          ..sort((a, b) => a.date.compareTo(b.date));
      }
      return result;
    } catch (_) {
      return <int, List<TelegramMessage>>{};
    }
  }

  Future<void> saveMessageArchive(
    Map<int, List<TelegramMessage>> messagesByChat, {
    String? accountId,
  }) async {
    final targetId = accountId ?? _activeAccountId;
    if (targetId == null) {
      // No account, save legacy
      await _saveArchiveToKey(_messageArchiveKey, messagesByChat);
      return;
    }
    await _saveArchiveToKey('${_messageArchiveKey}_$targetId', messagesByChat);
  }

  Future<void> _saveArchiveToKey(
    String key,
    Map<int, List<TelegramMessage>> messagesByChat,
  ) async {
    const maxMessagesPerChat = 500;
    final encoded = <String, dynamic>{};
    for (final entry in messagesByChat.entries) {
      final messages = List<TelegramMessage>.from(entry.value)..sort((a, b) => a.date.compareTo(b.date));
      final trimmed = messages.length > maxMessagesPerChat ? messages.sublist(messages.length - maxMessagesPerChat) : messages;
      encoded[entry.key.toString()] = trimmed.map((m) => m.toCacheJson()).toList();
    }
    await _prefs?.setString(key, jsonEncode(encoded));
  }

  // Password per account
  Future<void> setAccountPassword(String accountId, String password) async {
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return;
    final normalized = password.trim();
    if (normalized.isEmpty) {
      await clearAccountPassword(accountId);
      return;
    }
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final hash = '$salt:${_hashPassword(normalized, salt)}';
    _accounts[idx] = _accounts[idx].copyWith(lockHash: hash);
    await _persistAccounts();
    if (accountId == _legacyBotToken) {
      await _prefs?.setString(_lockHashKey, hash);
    }
    notifyListeners();
  }

  Future<void> clearAccountPassword(String accountId) async {
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return;
    _accounts[idx] = _accounts[idx].copyWith(clearLock: true);
    await _persistAccounts();
    notifyListeners();
  }

  bool verifyAccountPassword(String accountId, String password) {
    final acc = _accounts.firstWhere((a) => a.id == accountId, orElse: () => AccountProfile(id: '', label: '', botToken: ''));
    if (acc.id.isEmpty) return false;
    final stored = acc.lockHash;
    if (stored == null || stored.isEmpty) return true;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    return _hashPassword(password.trim(), parts.first) == parts.last;
  }

  // Legacy global password proxies to active account
  Future<void> setPassword(String password) async {
    if (activeAccount != null) {
      await setAccountPassword(activeAccount!.id, password);
    } else {
      final normalized = password.trim();
      if (normalized.isEmpty) {
        await clearPassword();
        return;
      }
      final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      _legacyLockHash = '$salt:${_hashPassword(normalized, salt)}';
      await _prefs?.setString(_lockHashKey, _legacyLockHash!);
      notifyListeners();
    }
  }

  Future<void> clearPassword() async {
    if (activeAccount != null) {
      await clearAccountPassword(activeAccount!.id);
    } else {
      _legacyLockHash = null;
      await _prefs?.remove(_lockHashKey);
      notifyListeners();
    }
  }

  bool verifyPassword(String password) {
    if (activeAccount != null) {
      return verifyAccountPassword(activeAccount!.id, password);
    }
    final stored = _legacyLockHash;
    if (stored == null || stored.isEmpty) return true;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    return _hashPassword(password.trim(), parts.first) == parts.last;
  }

  Future<void> _persistAccounts() async {
    final list = _accounts.map((a) => a.toJson()).toList();
    await _prefs?.setString(_accountsKey, jsonEncode(list));
  }

  String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  String _normalizeApiBaseUrl(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'https://api.telegram.org';
    }
    return normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
  }

  void _loadLegacyCustomNames() {
    _legacyCustomNames.clear();
    final raw = _prefs?.getString(_chatNamesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final value = entry.value?.toString().trim();
        if (id != null && value != null && value.isNotEmpty) {
          _legacyCustomNames[id] = value;
        }
      }
    } catch (_) {}
  }
}
