import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/telegram_models.dart';
import 'notification_service.dart';
import 'settings_store.dart';
import 'telegram_bot_api.dart';

enum MessageFileMode {
  auto,
  document,
  photo,
  video,
  audio,
  voice,
  sticker,
  animation,
}

class ChatSummary {
  const ChatSummary({
    required this.chat,
    required this.lastMessage,
    required this.unreadCount,
  });

  final TelegramChat chat;
  final TelegramMessage? lastMessage;
  final int unreadCount;
}

class ChatController extends ChangeNotifier {
  ChatController({
    required SettingsStore settings,
    required NotificationService notifications,
  }) : _settings = settings,
       _notifications = notifications;

  final SettingsStore _settings;
  final NotificationService _notifications;

  TelegramBotApi? _api;
  BotIdentity? _bot;
  AudioRecorder? _recorder;
  int? _updateOffset;
  int _pollSession = 0;
  int _temporaryMessageId = -1;

  final Map<int, TelegramChat> _chats = <int, TelegramChat>{};
  final Map<int, List<TelegramMessage>> _messagesByChat =
      <int, List<TelegramMessage>>{};
  final Map<int, int> _unreadByChat = <int, int>{};
  final Map<int, bool> _chatSendBlocked = <int, bool>{};

  int? _selectedChatId;
  bool _isConnecting = false;
  bool _isPolling = false;
  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  String? _lastError;
  Timer? _reconnectTimer;

  BotIdentity? get bot => _bot;
  int? get selectedChatId => _selectedChatId;
  bool get isConnecting => _isConnecting;
  bool get isPolling => _isPolling;
  bool get isRecording => _isRecording;
  DateTime? get recordingStartedAt => _recordingStartedAt;
  bool get isConnected => _api != null && _bot != null && _lastError == null;
  String? get lastError => _lastError;

  bool isChatSendBlocked(int chatId) => _chatSendBlocked[chatId] == true;

  bool get isSelectedChatSendBlocked {
    final id = _selectedChatId;
    return id != null && _chatSendBlocked[id] == true;
  }

  TelegramChat? get selectedChat {
    final id = _selectedChatId;
    if (id == null) {
      return null;
    }
    return _chats[id] ?? TelegramChat(id: id, type: 'private');
  }

  List<TelegramMessage> get selectedMessages {
    final id = _selectedChatId;
    if (id == null) {
      return const <TelegramMessage>[];
    }
    return List<TelegramMessage>.unmodifiable(
      (_messagesByChat[id] ?? const <TelegramMessage>[])
          .where((message) => message.delivery != MessageDelivery.deleted)
          .toList(growable: false),
    );
  }

  List<ChatSummary> get chatSummaries {
    final summaries = <ChatSummary>[];
    final includedIds = <int>{};
    for (final entry in _chats.entries) {
      includedIds.add(entry.key);
      final messages = (_messagesByChat[entry.key] ?? const <TelegramMessage>[])
          .where((message) => message.delivery != MessageDelivery.deleted)
          .toList(growable: false);
      summaries.add(
        ChatSummary(
          chat: entry.value,
          lastMessage: messages.isEmpty ? null : messages.last,
          unreadCount: _unreadByChat[entry.key] ?? 0,
        ),
      );
    }
    final preferred = _settings.preferredChatId;
    if (preferred != null && !includedIds.contains(preferred)) {
      includedIds.add(preferred);
      summaries.add(
        ChatSummary(
          chat: TelegramChat(
            id: preferred,
            type: 'private',
            title: 'محادثة مفضلة',
          ),
          lastMessage: null,
          unreadCount: 0,
        ),
      );
    }
    for (final entry in _settings.customChatNames.entries) {
      if (includedIds.contains(entry.key)) {
        continue;
      }
      includedIds.add(entry.key);
      summaries.add(
        ChatSummary(
          chat: TelegramChat(
            id: entry.key,
            type: 'private',
            title: entry.value,
          ),
          lastMessage: null,
          unreadCount: 0,
        ),
      );
    }
    summaries.sort((a, b) {
      final aDate =
          a.lastMessage?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.lastMessage?.date ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return summaries;
  }

  @override
  void dispose() {
    _pollSession++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> bootstrap() async {
    _selectedChatId = _settings.preferredChatId;
    final archived = _settings.loadMessageArchive();
    _messagesByChat
      ..clear()
      ..addAll(archived);
    _chats
      ..clear()
      ..addEntries(
        archived.entries
            .where((entry) => entry.value.isNotEmpty)
            .map((entry) => MapEntry(entry.key, entry.value.last.chat)),
      );
    if (_selectedChatId == null && _chats.isNotEmpty) {
      _selectedChatId = _chats.keys.first;
    }
    notifyListeners();
    if (_settings.hasBotToken) {
      await connect(
        token: _settings.botToken,
        preferredChatId: _settings.preferredChatId,
        persist: false,
      );
    }
    _startAutoReconnect();
  }

  /// Keeps trying to sign in automatically while a token exists but the bot
  /// is not connected yet. This covers launching the app without internet and
  /// reconnecting as soon as the network becomes available.
  void _startAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_api != null && _bot != null) {
        return;
      }
      if (_isConnecting || !_settings.hasBotToken) {
        return;
      }
      unawaited(
        connect(
          token: _settings.botToken,
          preferredChatId: _settings.preferredChatId,
          persist: false,
        ),
      );
    });
  }

  Future<void> connect({
    required String token,
    String? apiBaseUrl,
    int? preferredChatId,
    bool persist = true,
  }) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      _lastError = 'أدخل رمز البوت أولاً.';
      notifyListeners();
      return;
    }

    _pollSession++;
    _isConnecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final resolvedBaseUrl = apiBaseUrl ?? _settings.apiBaseUrl;
      final api = TelegramBotApi(normalized, apiBaseUrl: resolvedBaseUrl);
      final identity = await api.getMe();
      _api = api;
      _bot = identity;
      _selectedChatId = preferredChatId ?? _selectedChatId;
      if (_selectedChatId != null) {
        _chats.putIfAbsent(
          _selectedChatId!,
          () => TelegramChat(id: _selectedChatId!, type: 'private'),
        );
      }
      if (persist) {
        await _settings.setBotConfig(
          token: normalized,
          apiBaseUrl: resolvedBaseUrl,
          preferredChatId: preferredChatId,
        );
      }
      _isConnecting = false;
      notifyListeners();
      _startPolling();
    } catch (error) {
      _isConnecting = false;
      _isPolling = false;
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  void selectChat(int chatId) {
    _selectedChatId = chatId;
    _chats.putIfAbsent(chatId, () => TelegramChat(id: chatId, type: 'private'));
    _unreadByChat[chatId] = 0;
    notifyListeners();
    final chat = _chats[chatId];
    if (chat != null && chat.isGroup) {
      unawaited(_refreshChatPermissions(chatId));
    }
  }

  void clearSelection() {
    _selectedChatId = null;
    notifyListeners();
  }

  Future<void> addManualChat({
    required int chatId,
    required String name,
  }) async {
    final title = name.trim().isEmpty ? 'محادثة $chatId' : name.trim();
    _chats[chatId] = TelegramChat(id: chatId, type: 'private', title: title);
    await _settings.setCustomChatName(chatId, title);
    selectChat(chatId);
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  Future<void> refreshNow() async {
    final api = _api;
    final bot = _bot;
    if (api == null || bot == null) {
      return;
    }
    try {
      final updates = await api.getUpdates(
        offset: _updateOffset,
        timeoutSeconds: 0,
      );
      _handleUpdates(updates, bot.id);
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  /// Queries the bot's own membership in a group to detect when the group
  /// owner has banned the bot or restricted it from sending messages.
  Future<void> _refreshChatPermissions(int chatId) async {
    final api = _api;
    final bot = _bot;
    final chat = _chats[chatId];
    if (api == null || bot == null || chat == null) {
      return;
    }
    if (!chat.isGroup) {
      _chatSendBlocked.remove(chatId);
      notifyListeners();
      return;
    }
    try {
      final member = await api.getChatMember(chatId: chatId, userId: bot.id);
      _applyChatMemberStatus(chatId, member);
    } catch (_) {
      // Keep the previous state when the membership cannot be resolved.
    }
  }

  void _applyChatMemberStatus(
    int chatId,
    Map<String, dynamic>? member,
  ) {
    if (member == null) {
      return;
    }
    final status = member['status']?.toString();
    final blocked = status == 'kicked' ||
        status == 'left' ||
        (status == 'restricted' && member['can_send_messages'] != true);
    final changed = _chatSendBlocked[chatId] != blocked;
    if (blocked) {
      _chatSendBlocked[chatId] = true;
    } else {
      _chatSendBlocked.remove(chatId);
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> sendText(String text, {int? replyToMessageId}) async {
    final api = _api;
    final bot = _bot;
    final chat = selectedChat;
    final trimmed = text.trimRight();
    if (api == null || bot == null || chat == null || trimmed.trim().isEmpty) {
      return;
    }

    final pending = TelegramMessage.localPending(
      chat: chat,
      temporaryMessageId: _temporaryMessageId--,
      text: trimmed,
      replyToMessageId: replyToMessageId,
    );
    _addOrReplaceMessage(pending);

    try {
      final sent = await api.sendText(
        chatId: chat.id,
        text: trimmed,
        botId: bot.id,
        replyToMessageId: replyToMessageId,
      );
      _replaceMessage(pending.id, sent);
      await _notifications.playSendSound();
    } catch (error) {
      _replaceMessage(
        pending.id,
        pending.copyWith(delivery: MessageDelivery.failed),
      );
      _maybeBlockChatOnError(chat, error);
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> sendFiles(
    List<String> paths, {
    required MessageFileMode mode,
    String? caption,
    int? replyToMessageId,
  }) async {
    final api = _api;
    final bot = _bot;
    final chat = selectedChat;
    if (api == null || bot == null || chat == null || paths.isEmpty) {
      return;
    }

    for (final path in paths) {
      final file = File(path);
      final size = await file.length();
      const maxTelegramLocalFileSize = 2000 * 1024 * 1024;
      if (size > maxTelegramLocalFileSize) {
        _lastError = 'الحد الأقصى للملف هو 2GB.';
        notifyListeners();
        continue;
      }
      final route = _routeForFile(path, mode);
      final pending = _pendingFileMessage(
        chat: chat,
        path: path,
        kind: route.kind,
        caption: caption,
        replyToMessageId: replyToMessageId,
      );
      _addOrReplaceMessage(pending);
      try {
        final sent = await api.sendMediaFile(
          chatId: chat.id,
          method: route.method,
          fieldName: route.fieldName,
          filePath: path,
          botId: bot.id,
          caption: caption,
          replyToMessageId: replyToMessageId,
        );
        _replaceMessage(pending.id, sent);
        await _notifications.playSendSound();
      } catch (error) {
        _replaceMessage(
          pending.id,
          pending.copyWith(delivery: MessageDelivery.failed),
        );
        _maybeBlockChatOnError(chat, error);
        _lastError = _friendlyError(error);
        notifyListeners();
      }
    }
  }

  Future<void> editMessage(TelegramMessage message, String text) async {
    final api = _api;
    final bot = _bot;
    final trimmed = text.trimRight();
    if (api == null ||
        bot == null ||
        !message.canEdit ||
        trimmed.trim().isEmpty) {
      return;
    }
    try {
      final edited = await api.editMessageText(
        chatId: message.chat.id,
        messageId: message.messageId,
        text: trimmed,
        botId: bot.id,
      );
      _replaceMessage(
        message.id,
        edited.copyWith(delivery: MessageDelivery.edited),
      );
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> deleteMessage(TelegramMessage message) async {
    final api = _api;
    if (api == null || !message.canDelete) {
      return;
    }
    try {
      await api.deleteMessage(
        chatId: message.chat.id,
        messageId: message.messageId,
      );
      _replaceMessage(
        message.id,
        message.copyWith(delivery: MessageDelivery.deleted),
      );
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> setReaction(TelegramMessage message, String emoji) async {
    final api = _api;
    if (api == null || message.messageId <= 0) {
      return;
    }
    try {
      await api.setReaction(
        chatId: message.chat.id,
        messageId: message.messageId,
        emoji: emoji,
      );
      _replaceMessage(
        message.id,
        message.copyWith(reactionEmoji: emoji, reactionActor: _selfActorName),
      );
      await _notifications.playSendSound();
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> startVoiceRecording() async {
    if (_isRecording) {
      return;
    }
    try {
      final recorder = _recorder ??= AudioRecorder();
      final allowed = await recorder.hasPermission();
      if (!allowed) {
        _lastError = 'لم يتم منح إذن الميكروفون.';
        notifyListeners();
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}${Platform.pathSeparator}kimome_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
          noiseSuppress: true,
          echoCancel: true,
        ),
        path: path,
      );
      _isRecording = true;
      _recordingStartedAt = DateTime.now();
      notifyListeners();
    } catch (error) {
      _isRecording = false;
      _recordingStartedAt = null;
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> stopVoiceRecordingAndSend() async {
    final recorder = _recorder;
    if (!_isRecording || recorder == null) {
      return;
    }
    try {
      final path = await recorder.stop();
      _isRecording = false;
      _recordingStartedAt = null;
      notifyListeners();
      if (path != null && path.isNotEmpty) {
        await sendFiles(<String>[path], mode: MessageFileMode.audio);
      }
    } catch (error) {
      _isRecording = false;
      _recordingStartedAt = null;
      _lastError = _friendlyError(error);
      notifyListeners();
    }
  }

  Future<void> cancelVoiceRecording() async {
    final recorder = _recorder;
    if (!_isRecording || recorder == null) {
      return;
    }
    await recorder.cancel();
    _isRecording = false;
    _recordingStartedAt = null;
    notifyListeners();
  }

  Future<File?> downloadAttachment(
    TelegramMessage message,
    TelegramAttachment attachment,
  ) async {
    final api = _api;
    if (api == null) {
      return null;
    }
    try {
      final file = await api.cacheAttachment(attachment);
      final updatedAttachments = message.attachments
          .map((item) {
            if (item.fileId == attachment.fileId) {
              return item.copyWith(localPath: file.path);
            }
            return item;
          })
          .toList(growable: false);
      _replaceMessage(
        message.id,
        message.copyWith(attachments: updatedAttachments),
      );
      return file;
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
      return null;
    }
  }

  Future<File?> saveAttachmentToDownloads(TelegramAttachment attachment) async {
    final api = _api;
    if (api == null) {
      return null;
    }
    try {
      return await api.saveAttachmentToDownloads(attachment);
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
      return null;
    }
  }

  Future<File?> saveAttachmentToPath(
    TelegramMessage message,
    TelegramAttachment attachment,
    String targetPath,
  ) async {
    try {
      File? source;
      final localPath = attachment.localPath;
      if (localPath != null && localPath.isNotEmpty) {
        final localFile = File(localPath);
        if (await localFile.exists()) {
          source = localFile;
        }
      }
      source ??= await downloadAttachment(message, attachment);
      if (source == null) {
        return null;
      }
      final target = File(targetPath);
      if (!await target.parent.exists()) {
        await target.parent.create(recursive: true);
      }
      if (source.path == target.path) {
        return target;
      }
      return source.copy(target.path);
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
      return null;
    }
  }

  Future<void> openAttachment(
    TelegramMessage message,
    TelegramAttachment attachment,
  ) async {
    final path = attachment.localPath;
    if (path != null && path.isNotEmpty && await File(path).exists()) {
      await OpenFilex.open(path);
      return;
    }
    final file = await downloadAttachment(message, attachment);
    if (file != null) {
      await OpenFilex.open(file.path);
    }
  }

  void _startPolling() {
    final api = _api;
    final bot = _bot;
    if (api == null || bot == null) {
      return;
    }
    final session = ++_pollSession;
    _isPolling = true;
    notifyListeners();
    unawaited(_pollLoop(session, api, bot.id));
  }

  Future<void> _pollLoop(int session, TelegramBotApi api, int botId) async {
    while (session == _pollSession) {
      try {
        final updates = await api.getUpdates(offset: _updateOffset);
        if (session != _pollSession) {
          return;
        }
        _handleUpdates(updates, botId);
        _lastError = null;
      } catch (error) {
        if (session != _pollSession) {
          return;
        }
        _lastError = _friendlyError(error);
        notifyListeners();
        await Future<void>.delayed(const Duration(seconds: 4));
      }
    }
    _isPolling = false;
    notifyListeners();
  }

  void _handleUpdates(List<Map<String, dynamic>> updates, int botId) {
    for (final update in updates) {
      final updateId = _asInt(update['update_id']);
      if (updateId != null) {
        _updateOffset = updateId + 1;
      }

      final reaction = _asMap(update['message_reaction']);
      if (reaction != null) {
        _handleReactionUpdate(reaction);
        continue;
      }

      final myChatMember = _asMap(update['my_chat_member']);
      if (myChatMember != null) {
        _handleMyChatMemberUpdate(myChatMember);
        continue;
      }

      final edited =
          update['edited_message'] != null ||
          update['edited_channel_post'] != null;
      final rawMessage =
          _asMap(update['message']) ??
          _asMap(update['edited_message']) ??
          _asMap(update['channel_post']) ??
          _asMap(update['edited_channel_post']);
      if (rawMessage == null) {
        continue;
      }
      final message = TelegramMessage.fromRawMessage(
        rawMessage,
        botId: botId,
        updateId: updateId,
        edited: edited,
      );
      final normalized =
          message.isOutgoing && message.delivery == MessageDelivery.received
          ? message.copyWith(delivery: MessageDelivery.sent)
          : message;
      final existed = _containsMessage(normalized.id);
      _addOrReplaceMessage(normalized);
      if (!normalized.isOutgoing && !edited && !existed) {
        if (normalized.chat.id != _selectedChatId) {
          _unreadByChat[normalized.chat.id] =
              (_unreadByChat[normalized.chat.id] ?? 0) + 1;
        }
        unawaited(_notifications.showIncomingMessage(normalized));
      }
    }
    notifyListeners();
  }

  void _handleMyChatMemberUpdate(Map<String, dynamic> myChatMember) {
    final chat = _asMap(myChatMember['chat']);
    final chatId = _asInt(chat?['id']);
    if (chatId == null) {
      return;
    }
    if (chat != null) {
      _chats[chatId] = TelegramChat.fromJson(chat);
    }
    final newMember = _asMap(myChatMember['new_chat_member']);
    _applyChatMemberStatus(chatId, newMember);
  }

  void _handleReactionUpdate(Map<String, dynamic> reaction) {
    final chat = _asMap(reaction['chat']);
    final chatId = _asInt(chat?['id']);
    final messageId = _asInt(reaction['message_id']);
    if (chatId == null || messageId == null) {
      return;
    }
    final newReaction = reaction['new_reaction'];
    final emojis = <String>[];
    if (newReaction is List && newReaction.isNotEmpty) {
      for (final item in newReaction) {
        final raw = _asMap(item);
        final emoji = _asString(raw?['emoji']);
        if (emoji != null) {
          emojis.add(emoji);
        }
      }
    }
    final emoji = emojis.isEmpty ? null : emojis.join(' ');
    final actor = _reactionActorName(reaction);
    final messages = _messagesByChat[chatId];
    if (messages == null) {
      return;
    }
    final index = messages.indexWhere(
      (message) => message.messageId == messageId,
    );
    if (index < 0) {
      return;
    }
    messages[index] = messages[index].copyWith(
      reactionEmoji: emoji,
      reactionActor: actor,
      clearReaction: emoji == null,
    );
    _persistArchive();
  }

  String get _selfActorName {
    final bot = _bot;
    if (bot == null) {
      return 'أنت';
    }
    if (bot.username.trim().isNotEmpty) {
      return '@${bot.username}';
    }
    if (bot.firstName.trim().isNotEmpty) {
      return bot.firstName;
    }
    return 'أنت';
  }

  String _reactionActorName(Map<String, dynamic> reaction) {
    final user = _asMap(reaction['user']);
    if (user != null) {
      return _actorName(user, fallback: 'مستخدم');
    }
    final actorChat = _asMap(reaction['actor_chat']);
    if (actorChat != null) {
      return _actorName(actorChat, fallback: 'محادثة');
    }
    return 'مستخدم';
  }

  String _actorName(Map<String, dynamic> json, {required String fallback}) {
    final username = _asString(json['username']);
    if (username != null) {
      return '@$username';
    }
    final title = _asString(json['title']);
    if (title != null) {
      return title;
    }
    final name = [
      _asString(json['first_name']),
      _asString(json['last_name']),
    ].whereType<String>().join(' ').trim();
    return name.isEmpty ? fallback : name;
  }

  bool _containsMessage(String id) {
    for (final messages in _messagesByChat.values) {
      if (messages.any((message) => message.id == id)) {
        return true;
      }
    }
    return false;
  }

  void _addOrReplaceMessage(TelegramMessage message) {
    _chats[message.chat.id] = message.chat;
    final messages = _messagesByChat.putIfAbsent(
      message.chat.id,
      () => <TelegramMessage>[],
    );
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index >= 0) {
      messages[index] = message;
    } else {
      messages.add(message);
    }
    messages.sort((a, b) => a.date.compareTo(b.date));
    _selectedChatId ??= message.chat.id;
    _persistArchive();
    notifyListeners();
  }

  void _replaceMessage(String oldId, TelegramMessage replacement) {
    final messages = _messagesByChat[replacement.chat.id];
    if (messages == null) {
      _addOrReplaceMessage(replacement);
      return;
    }
    final oldIndex = messages.indexWhere((message) => message.id == oldId);
    if (oldIndex >= 0) {
      messages[oldIndex] = replacement;
    } else {
      _addOrReplaceMessage(replacement);
      return;
    }
    messages.sort((a, b) => a.date.compareTo(b.date));
    _persistArchive();
    notifyListeners();
  }

  void _persistArchive() {
    unawaited(_settings.saveMessageArchive(_messagesByChat));
  }

  TelegramMessage _pendingFileMessage({
    required TelegramChat chat,
    required String path,
    required AttachmentKind kind,
    String? caption,
    int? replyToMessageId,
  }) {
    final temporaryId = _temporaryMessageId--;
    return TelegramMessage(
      id: '${chat.id}:$temporaryId',
      chat: chat,
      messageId: temporaryId,
      date: DateTime.now(),
      isOutgoing: true,
      delivery: MessageDelivery.sending,
      caption: caption,
      replyToMessageId: replyToMessageId,
      fromName: 'KimomeMessage',
      attachments: <TelegramAttachment>[
        TelegramAttachment(
          kind: kind,
          fileName: _filename(path),
          localPath: path,
        ),
      ],
    );
  }

  _FileRoute _routeForFile(String path, MessageFileMode mode) {
    final resolved = mode == MessageFileMode.auto ? _autoMode(path) : mode;
    return switch (resolved) {
      MessageFileMode.photo => const _FileRoute(
        'sendPhoto',
        'photo',
        AttachmentKind.photo,
      ),
      MessageFileMode.video => const _FileRoute(
        'sendVideo',
        'video',
        AttachmentKind.video,
      ),
      MessageFileMode.audio => const _FileRoute(
        'sendAudio',
        'audio',
        AttachmentKind.audio,
      ),
      MessageFileMode.voice => const _FileRoute(
        'sendVoice',
        'voice',
        AttachmentKind.voice,
      ),
      MessageFileMode.sticker => const _FileRoute(
        'sendSticker',
        'sticker',
        AttachmentKind.sticker,
      ),
      MessageFileMode.animation => const _FileRoute(
        'sendAnimation',
        'animation',
        AttachmentKind.animation,
      ),
      MessageFileMode.auto || MessageFileMode.document => const _FileRoute(
        'sendDocument',
        'document',
        AttachmentKind.document,
      ),
    };
  }

  MessageFileMode _autoMode(String path) {
    final extension = _extension(path);
    if (<String>{'jpg', 'jpeg', 'png'}.contains(extension)) {
      return MessageFileMode.photo;
    }
    if (<String>{'mp4', 'mov', 'm4v', 'mkv', 'webm'}.contains(extension)) {
      return MessageFileMode.video;
    }
    if (<String>{'mp3', 'm4a', 'aac', 'wav', 'flac'}.contains(extension)) {
      return MessageFileMode.audio;
    }
    if (<String>{'gif'}.contains(extension)) {
      return MessageFileMode.animation;
    }
    if (<String>{'webp', 'tgs'}.contains(extension)) {
      return MessageFileMode.sticker;
    }
    return MessageFileMode.document;
  }

  String _filename(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String _extension(String path) {
    final filename = _filename(path);
    final index = filename.lastIndexOf('.');
    if (index < 0 || index == filename.length - 1) {
      return '';
    }
    return filename.substring(index + 1).toLowerCase();
  }

  String _friendlyError(Object error) {
    if (error is TelegramApiException) {
      return error.message;
    }
    if (error is SocketException) {
      return 'لا يوجد اتصال مستقر بالإنترنت.';
    }
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال بتلغرام.';
    }
    return error.toString();
  }

  void _maybeBlockChatOnError(TelegramChat chat, Object error) {
    if (!chat.isGroup || error is! TelegramApiException) {
      return;
    }
    final lower = error.message.toLowerCase();
    final restricted = <String>[
      'forbidden',
      'kicked',
      'banned',
      'not enough rights',
      'write_forbidden',
      'chat_write_forbidden',
      'have no rights',
    ].any(lower.contains);
    if (restricted) {
      _chatSendBlocked[chat.id] = true;
    }
  }
}

class _FileRoute {
  const _FileRoute(this.method, this.fieldName, this.kind);

  final String method;
  final String fieldName;
  final AttachmentKind kind;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _asString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
