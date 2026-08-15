import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/telegram_models.dart';
import 'notification_service.dart';
import 'settings_store.dart';
import 'sticker_store.dart';
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
    required StickerStore stickerStore,
  })  : _settings = settings,
        _notifications = notifications,
        _stickerStore = stickerStore;

  final SettingsStore _settings;
  final NotificationService _notifications;
  final StickerStore _stickerStore;

  TelegramBotApi? _api;
  BotIdentity? _bot;
  AudioRecorder? _recorder;
  int? _updateOffset;
  int _pollSession = 0;
  int _temporaryMessageId = -1;
  Timer? _reconnectTimer;
  Timer? _outboxRetryTimer;
  bool _isFlushingOutbox = false;
  final List<_QueuedTextMessage> _textOutbox = <_QueuedTextMessage>[];

  final Map<int, TelegramChat> _chats = <int, TelegramChat>{};
  final Map<int, bool> _canSendByChat = <int, bool>{};
  final Map<int, List<TelegramMessage>> _messagesByChat =
      <int, List<TelegramMessage>>{};
  final Map<int, int> _unreadByChat = <int, int>{};
  final Map<int, String> _firstUnreadByChat = <int, String>{};

  int? _selectedChatId;
  String? _selectedUnreadStartMessageId;
  bool _isConnecting = false;
  bool _isPolling = false;
  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  String? _lastError;

  BotIdentity? get bot => _bot;
  int? get selectedChatId => _selectedChatId;
  bool get isConnecting => _isConnecting;
  bool get isPolling => _isPolling;
  bool get isRecording => _isRecording;
  DateTime? get recordingStartedAt => _recordingStartedAt;
  bool get isConnected => _api != null && _bot != null && _lastError == null;
  String? get lastError => _lastError;
  String? get selectedUnreadStartMessageId => _selectedUnreadStartMessageId;
  int get queuedMessageCount => _textOutbox.length;
  bool get canSendToSelectedChat {
    final chat = selectedChat;
    if (chat == null) return false;
    return _canSendByChat[chat.id] ?? true;
  }

  String? get selectedChatSendRestriction => canSendToSelectedChat
      ? null
      : 'أوقف مالك المجموعة صلاحية إرسال الرسائل لهذا البوت.';

  int get totalUnread => _unreadByChat.values.fold(0, (a, b) => a + b);
  List<String> get unreadChatNames {
    return _unreadByChat.entries
        .map((e) => _chats[e.key]?.displayTitle ?? 'محادثة ${e.key}')
        .toList();
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
          .where((message) => message.delivery != MessageDelivery.deleted),
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
    _outboxRetryTimer?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  Future<void> bootstrap() async {
    _selectedChatId = _settings.preferredChatId;
    final archived = _sanitizeArchivedMessages(_settings.loadMessageArchive(
        accountId: _settings.activeAccountId));
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
    _restorePendingOutbox();
    notifyListeners();
    if (_settings.hasBotToken) {
      await connect(
        token: _settings.botToken,
        preferredChatId: _settings.preferredChatId,
        persist: false,
      );
    }
  }

  Future<void> switchToAccount(AccountProfile account) async {
    // Stop current polling
    _pollSession++;
    _isPolling = false;
    _api = null;
    _bot = null;
    _updateOffset = null;
    _chats.clear();
    _messagesByChat.clear();
    _unreadByChat.clear();
    _firstUnreadByChat.clear();
    _selectedUnreadStartMessageId = null;
    _canSendByChat.clear();
    _textOutbox.clear();
    _outboxRetryTimer?.cancel();
    _selectedChatId = account.preferredChatId;
    _lastError = null;
    notifyListeners();

    // Load archive for this account
    final archived = _sanitizeArchivedMessages(
        _settings.loadMessageArchive(accountId: account.id));
    _messagesByChat.addAll(archived);
    _chats.addEntries(archived.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => MapEntry(e.key, e.value.last.chat)));
    if (_selectedChatId == null && _chats.isNotEmpty) {
      _selectedChatId = _chats.keys.first;
    }
    _restorePendingOutbox();
    notifyListeners();

    if (account.botToken.trim().isNotEmpty) {
      await connect(
        token: account.botToken,
        apiBaseUrl: account.apiBaseUrl,
        preferredChatId: account.preferredChatId,
        persist: false,
      );
    }
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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

      // Telegram keeps bot updates while this device is offline. Drain all
      // immediately available batches before starting long polling so messages
      // sent during the outage appear as soon as the internet comes back.
      await _receiveMissedUpdates(api, identity.id);
      _isConnecting = false;
      notifyListeners();
      final selected = selectedChat;
      if (selected?.isCommunity == true) {
        unawaited(_refreshSendPermission(selected!.id));
      }
      _startPolling();
      unawaited(_flushTextOutbox());
    } catch (error) {
      _api = null;
      _bot = null;
      _isConnecting = false;
      _isPolling = false;
      _lastError = _friendlyError(error);
      notifyListeners();
      if (_isTransientConnectionError(error)) {
        _scheduleReconnect(
          token: normalized,
          apiBaseUrl: apiBaseUrl ?? _settings.apiBaseUrl,
          preferredChatId: preferredChatId,
        );
      }
    }
  }

  void selectChat(int chatId) {
    _selectedChatId = chatId;
    _selectedUnreadStartMessageId = _firstUnreadByChat.remove(chatId);
    _chats.putIfAbsent(chatId, () => TelegramChat(id: chatId, type: 'private'));
    _unreadByChat[chatId] = 0;
    unawaited(_notifications.onChatOpened(chatId));
    final chat = _chats[chatId];
    if (chat?.isCommunity == true) {
      unawaited(_refreshSendPermission(chatId));
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedChatId = null;
    _selectedUnreadStartMessageId = null;
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

  Future<void> _receiveMissedUpdates(
    TelegramBotApi api,
    int botId,
  ) async {
    // One Bot API response contains at most 100 updates. Keep draining bounded
    // batches to cover longer offline periods without blocking startup forever.
    for (var batch = 0; batch < 50; batch++) {
      final updates = await api.getUpdates(
        offset: _updateOffset,
        timeoutSeconds: 0,
      );
      if (updates.isEmpty) break;
      _handleUpdates(updates, botId);
      if (updates.length < 100) break;
    }
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

  Future<void> sendText(String text, {int? replyToMessageId}) async {
    final chat = selectedChat;
    final trimmed = text.trimRight();
    if (chat == null || trimmed.trim().isEmpty) return;
    if (!_ensureCanSend(chat)) return;

    final pending = TelegramMessage.localPending(
      chat: chat,
      temporaryMessageId: _temporaryMessageId--,
      text: trimmed,
      replyToMessageId: replyToMessageId,
    );
    _textOutbox.add(_QueuedTextMessage(pending));
    _addOrReplaceMessage(pending);
    notifyListeners();

    // The message stays in the outbox while offline. It is retried automatically
    // after polling or login succeeds, so closing the composer never loses it.
    await _flushTextOutbox();
  }

  Future<void> _flushTextOutbox() async {
    if (_isFlushingOutbox || _textOutbox.isEmpty) return;
    final api = _api;
    final bot = _bot;
    if (api == null || bot == null) {
      _scheduleOutboxRetry();
      if (_settings.hasBotToken && !_isConnecting) {
        _scheduleReconnect(
          token: _settings.botToken,
          apiBaseUrl: _settings.apiBaseUrl,
          preferredChatId: _settings.preferredChatId,
        );
      }
      return;
    }

    _isFlushingOutbox = true;
    try {
      while (_textOutbox.isNotEmpty) {
        final queued = _textOutbox.first;
        final pending = queued.message;
        if (!(_canSendByChat[pending.chat.id] ?? true)) {
          _replaceMessage(
            pending.id,
            pending.copyWith(delivery: MessageDelivery.failed),
          );
          _textOutbox.removeAt(0);
          continue;
        }
        try {
          final sent = await api.sendText(
            chatId: pending.chat.id,
            text: pending.text ?? '',
            botId: bot.id,
            replyToMessageId: pending.replyToMessageId,
          );
          _textOutbox.removeAt(0);
          _replaceMessage(pending.id, sent);
          await _notifications.playSendSound();
          _lastError = null;
        } catch (error) {
          _handlePossibleWriteRestriction(error, pending.chat.id);
          _lastError = _friendlyError(error);
          if (_isTransientConnectionError(error)) {
            _scheduleOutboxRetry();
            notifyListeners();
            return;
          }
          _textOutbox.removeAt(0);
          _replaceMessage(
            pending.id,
            pending.copyWith(delivery: MessageDelivery.failed),
          );
          notifyListeners();
        }
      }
    } finally {
      _isFlushingOutbox = false;
      notifyListeners();
    }
  }

  void _scheduleOutboxRetry() {
    if (_outboxRetryTimer?.isActive == true || _textOutbox.isEmpty) return;
    _outboxRetryTimer = Timer(const Duration(seconds: 4), () {
      _outboxRetryTimer = null;
      unawaited(_flushTextOutbox());
    });
  }

  void _restorePendingOutbox() {
    _textOutbox.clear();
    var lowestTemporaryId = -1;
    for (final messages in _messagesByChat.values) {
      for (final message in messages) {
        if (message.messageId < lowestTemporaryId) {
          lowestTemporaryId = message.messageId;
        }
        if (message.delivery == MessageDelivery.sending &&
            message.isOutgoing &&
            message.text?.trim().isNotEmpty == true) {
          _textOutbox.add(_QueuedTextMessage(message));
        }
      }
    }
    _textOutbox.sort((a, b) => a.message.date.compareTo(b.message.date));
    _temporaryMessageId = lowestTemporaryId - 1;
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
    if (!_ensureCanSend(chat)) return;

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
        // If sticker, save to store
        if (route.kind == AttachmentKind.sticker) {
          for (final att in sent.attachments) {
            if (att.kind == AttachmentKind.sticker) {
              await _stickerStore.addFromAttachment(att, localPath: path);
            }
          }
        }
        await _notifications.playSendSound();
      } catch (error) {
        _handlePossibleWriteRestriction(error, chat.id);
        _replaceMessage(
          pending.id,
          pending.copyWith(delivery: MessageDelivery.failed),
        );
        _lastError = _friendlyError(error);
        notifyListeners();
      }
    }
  }

  Future<void> sendSticker(SavedSticker sticker, {int? replyToMessageId}) async {
    final api = _api;
    final bot = _bot;
    final chat = selectedChat;
    if (api == null || bot == null || chat == null) return;
    if (!_ensureCanSend(chat)) return;

    // Prefer sending by fileId
    if (sticker.fileId.isNotEmpty) {
      final pending = _pendingStickerMessage(chat: chat, sticker: sticker, replyToMessageId: replyToMessageId);
      _addOrReplaceMessage(pending);
      try {
        final sent = await api.sendStickerByFileId(
          chatId: chat.id,
          stickerFileId: sticker.fileId,
          botId: bot.id,
          replyToMessageId: replyToMessageId,
        );
        _replaceMessage(pending.id, sent);
        await _notifications.playSendSound();
      } catch (e) {
        // Fallback: if fileId fails, try local path if exists
        if (sticker.localPath != null && await File(sticker.localPath!).exists()) {
          try {
            final sent = await api.sendMediaFile(
              chatId: chat.id,
              method: 'sendSticker',
              fieldName: 'sticker',
              filePath: sticker.localPath!,
              botId: bot.id,
              replyToMessageId: replyToMessageId,
            );
            _replaceMessage(pending.id, sent);
            await _notifications.playSendSound();
            return;
          } catch (_) {}
        }
        _handlePossibleWriteRestriction(e, chat.id);
        _replaceMessage(pending.id, pending.copyWith(delivery: MessageDelivery.failed));
        _lastError = _friendlyError(e);
        notifyListeners();
      }
    } else if (sticker.localPath != null) {
      await sendFiles([sticker.localPath!], mode: MessageFileMode.sticker, replyToMessageId: replyToMessageId);
    }
  }

  TelegramMessage _pendingStickerMessage({
    required TelegramChat chat,
    required SavedSticker sticker,
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
      replyToMessageId: replyToMessageId,
      fromName: 'KimomeMessage',
      attachments: [
        TelegramAttachment(
          kind: AttachmentKind.sticker,
          fileId: sticker.fileId,
          uniqueId: sticker.uniqueId,
          fileName: sticker.fileName,
          localPath: sticker.localPath,
          isVideoSticker: sticker.isVideo,
          isAnimatedSticker: sticker.isAnimated,
          emoji: sticker.emoji,
        )
      ],
    );
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
      final messages = _messagesByChat[message.chat.id];
      messages?.removeWhere((item) => item.id == message.id);
      _persistArchive();
      notifyListeners();
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
      // If sticker, auto-save
      if (attachment.kind == AttachmentKind.sticker) {
        await _stickerStore.addFromAttachment(attachment, localPath: file.path);
      }
      return file;
    } catch (error) {
      _lastError = _friendlyError(error);
      notifyListeners();
      return null;
    }
  }

  Future<String?> getStreamingUrl(TelegramAttachment attachment) async {
    final api = _api;
    if (api == null) return null;
    try {
      final uri = await api.tryGetFileUrlForAttachment(attachment);
      return uri?.toString();
    } catch (_) {
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
        if (_textOutbox.isNotEmpty) unawaited(_flushTextOutbox());
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

      final membership = _asMap(update['my_chat_member']);
      if (membership != null) {
        _handleMyChatMemberUpdate(membership);
        continue;
      }

      final reaction = _asMap(update['message_reaction']);
      if (reaction != null) {
        _handleReactionUpdate(reaction);
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
      if (normalized.chat.isCommunity &&
          !_canSendByChat.containsKey(normalized.chat.id)) {
        unawaited(_refreshSendPermission(normalized.chat.id));
      }

      // Auto-save stickers
      if (normalized.attachments.any((a) => a.kind == AttachmentKind.sticker)) {
        for (final att in normalized.attachments.where((a) => a.kind == AttachmentKind.sticker)) {
          unawaited(_autoCacheSticker(normalized, att));
        }
      }

      if (!normalized.isOutgoing && !edited && !existed) {
        if (normalized.chat.id != _selectedChatId) {
          _firstUnreadByChat.putIfAbsent(
            normalized.chat.id,
            () => normalized.id,
          );
          _unreadByChat[normalized.chat.id] =
              (_unreadByChat[normalized.chat.id] ?? 0) + 1;
        }
        unawaited(_notifications.showIncomingMessage(normalized));
      }
    }
    notifyListeners();
  }

  Future<void> _autoCacheSticker(TelegramMessage message, TelegramAttachment attachment) async {
    final api = _api;
    if (api == null) return;
    try {
      // Try to get local file without full download if already cached, else download
      if (attachment.localPath != null) {
        await _stickerStore.addFromAttachment(attachment);
        return;
      }
      // Download to cache via streaming
      final file = await api.cacheAttachment(attachment);
      await _stickerStore.addFromAttachment(attachment, localPath: file.path);
      // Update message attachment path
      final updated = message.attachments.map((a) {
        if (a.fileId == attachment.fileId) return a.copyWith(localPath: file.path);
        return a;
      }).toList();
      _replaceMessage(message.id, message.copyWith(attachments: updated));
    } catch (_) {}
  }

  void _handleMyChatMemberUpdate(Map<String, dynamic> update) {
    final chatJson = _asMap(update['chat']);
    final member = _asMap(update['new_chat_member']);
    final chatId = _asInt(chatJson?['id']);
    if (chatId == null || member == null) return;
    if (chatJson != null) _chats[chatId] = TelegramChat.fromJson(chatJson);
    _canSendByChat[chatId] = _memberCanSend(
      member,
      chat: _chats[chatId],
    );
  }

  Future<void> _refreshSendPermission(int chatId) async {
    final api = _api;
    final bot = _bot;
    final chat = _chats[chatId];
    if (api == null || bot == null || chat == null || !chat.isCommunity) return;
    try {
      final member = await api.getChatMember(chatId: chatId, userId: bot.id);
      _canSendByChat[chatId] = _memberCanSend(member, chat: chat);
      notifyListeners();
    } catch (_) {
      // Do not disable the composer on an inconclusive network failure. Telegram
      // will still reject a send and the regular error handling will explain it.
    }
  }

  bool _memberCanSend(Map<String, dynamic> member, {TelegramChat? chat}) {
    final status = _asString(member['status']) ?? '';
    if (status == 'left' || status == 'kicked') return false;
    if (status == 'restricted') return member['can_send_messages'] == true;
    if (chat?.isChannel == true) {
      return status == 'administrator' || status == 'creator';
    }
    return status == 'member' || status == 'administrator' || status == 'creator';
  }

  bool _ensureCanSend(TelegramChat chat) {
    if (_canSendByChat[chat.id] ?? true) return true;
    _lastError = 'لا يمكنك الإرسال: مالك المجموعة أوقف صلاحية إرسال الرسائل للبوت.';
    notifyListeners();
    return false;
  }

  void _handlePossibleWriteRestriction(Object error, int chatId) {
    final value = error.toString().toLowerCase();
    if (value.contains('chat_write_forbidden') ||
        value.contains('not enough rights') ||
        value.contains('bot was kicked') ||
        value.contains('forbidden: bot')) {
      _canSendByChat[chatId] = false;
    }
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
    unawaited(_settings.saveMessageArchive(_messagesByChat,
        accountId: _settings.activeAccountId));
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

  Map<int, List<TelegramMessage>> _sanitizeArchivedMessages(
    Map<int, List<TelegramMessage>> source,
  ) {
    final stickerPathCounts = <String, int>{};
    for (final messages in source.values) {
      for (final message in messages) {
        for (final attachment in message.attachments) {
          final path = attachment.localPath;
          if (attachment.kind == AttachmentKind.sticker && path != null) {
            stickerPathCounts[path] = (stickerPathCounts[path] ?? 0) + 1;
          }
        }
      }
    }
    return source.map((chatId, messages) {
      final cleaned = messages
          .where((message) => message.delivery != MessageDelivery.deleted)
          .map((message) {
            final attachments = message.attachments.map((attachment) {
              final path = attachment.localPath;
              if (attachment.kind == AttachmentKind.sticker &&
                  path != null &&
                  (stickerPathCounts[path] ?? 0) > 1) {
                return attachment.copyWith(clearLocalPath: true);
              }
              return attachment;
            }).toList(growable: false);
            return message.copyWith(attachments: attachments);
          })
          .toList(growable: true);
      return MapEntry(chatId, cleaned);
    });
  }

  void _scheduleReconnect({
    required String token,
    required String apiBaseUrl,
    int? preferredChatId,
  }) {
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      if (_api != null || _isConnecting) return;
      unawaited(connect(
        token: token,
        apiBaseUrl: apiBaseUrl,
        preferredChatId: preferredChatId,
        persist: false,
      ));
    });
  }

  bool _isTransientConnectionError(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    if (error is TelegramApiException) return false;
    final text = error.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network') ||
        text.contains('timed out') ||
        text.contains('failed host lookup');
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
}

class _QueuedTextMessage {
  const _QueuedTextMessage(this.message);

  final TelegramMessage message;
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
