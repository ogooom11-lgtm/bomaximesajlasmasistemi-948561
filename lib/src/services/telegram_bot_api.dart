import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/telegram_models.dart';

class TelegramApiException implements Exception {
  TelegramApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TelegramBotApi {
  TelegramBotApi(
    this.token, {
    String apiBaseUrl = 'https://api.telegram.org',
    http.Client? client,
  })  : _apiBaseUrl = _normalizeBaseUrl(apiBaseUrl),
        _client = client ?? http.Client();

  final String token;
  final String _apiBaseUrl;
  final http.Client _client;

  Uri _apiUri(String method) => Uri.parse('$_apiBaseUrl/bot$token/$method');

  Uri _fileUri(String filePath) {
    return Uri.parse('$_apiBaseUrl/file/bot$token/$filePath');
  }

  Future<BotIdentity> getMe() async {
    final data = await _postJson('getMe', const <String, Object?>{});
    return BotIdentity.fromJson(_asMap(data['result']) ?? {});
  }

  Future<Map<String, dynamic>> getChatMember({
    required int chatId,
    required int userId,
  }) async {
    final data = await _postJson('getChatMember', <String, Object?>{
      'chat_id': chatId,
      'user_id': userId,
    });
    return _asMap(data['result']) ?? const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> getUpdates({
    required int? offset,
    int timeoutSeconds = 25,
  }) async {
    final payload = <String, Object?>{
      'timeout': timeoutSeconds,
      'limit': 100,
      'allowed_updates': const <String>[
        'message',
        'edited_message',
        'channel_post',
        'edited_channel_post',
        'message_reaction',
        'my_chat_member',
      ],
    };
    if (offset != null) {
      payload['offset'] = offset;
    }
    final data = await _postJson(
      'getUpdates',
      payload,
    ).timeout(Duration(seconds: timeoutSeconds + 10));
    final result = data['result'];
    if (result is! List) {
      return const <Map<String, dynamic>>[];
    }
    return result
        .map((item) => _asMap(item))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<TelegramMessage> sendText({
    required int chatId,
    required String text,
    required int botId,
    int? replyToMessageId,
  }) async {
    final payload = <String, Object?>{
      'chat_id': chatId,
      'text': text,
      'disable_web_page_preview': false,
    };
    if (replyToMessageId != null) {
      payload['reply_parameters'] = <String, Object?>{
        'message_id': replyToMessageId,
        'allow_sending_without_reply': true,
      };
    }
    final data = await _postJson('sendMessage', payload);
    return TelegramMessage.fromRawMessage(
      _asMap(data['result']) ?? {},
      botId: botId,
    ).copyWith(delivery: MessageDelivery.sent);
  }

  Future<TelegramMessage> sendMediaFile({
    required int chatId,
    required String method,
    required String fieldName,
    required String filePath,
    required int botId,
    String? caption,
    int? replyToMessageId,
  }) async {
    final request = http.MultipartRequest('POST', _apiUri(method));
    request.fields['chat_id'] = chatId.toString();
    if (caption != null &&
        caption.trim().isNotEmpty &&
        method != 'sendSticker') {
      request.fields['caption'] = caption.trim();
    }
    if (replyToMessageId != null) {
      request.fields['reply_parameters'] = jsonEncode(<String, Object?>{
        'message_id': replyToMessageId,
        'allow_sending_without_reply': true,
      });
    }
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    final data = _decodeResponse(response);
    return TelegramMessage.fromRawMessage(
      _asMap(data['result']) ?? {},
      botId: botId,
    ).copyWith(delivery: MessageDelivery.sent);
  }

  Future<TelegramMessage> sendStickerByFileId({
    required int chatId,
    required String stickerFileId,
    required int botId,
    int? replyToMessageId,
  }) async {
    final payload = <String, Object?>{
      'chat_id': chatId,
      'sticker': stickerFileId,
    };
    if (replyToMessageId != null) {
      payload['reply_parameters'] = <String, Object?>{
        'message_id': replyToMessageId,
        'allow_sending_without_reply': true,
      };
    }
    final data = await _postJson('sendSticker', payload);
    return TelegramMessage.fromRawMessage(
      _asMap(data['result']) ?? {},
      botId: botId,
    ).copyWith(delivery: MessageDelivery.sent);
  }

  Future<TelegramMessage> editMessageText({
    required int chatId,
    required int messageId,
    required String text,
    required int botId,
  }) async {
    final data = await _postJson('editMessageText', <String, Object?>{
      'chat_id': chatId,
      'message_id': messageId,
      'text': text,
    });
    final result = data['result'];
    if (result is bool) {
      throw TelegramApiException(
        'تلغرام أكد التعديل لكن لم يرجع الرسالة المعدلة.',
      );
    }
    return TelegramMessage.fromRawMessage(
      _asMap(result) ?? {},
      botId: botId,
      edited: true,
    );
  }

  Future<void> deleteMessage({
    required int chatId,
    required int messageId,
  }) async {
    await _postJson('deleteMessage', <String, Object?>{
      'chat_id': chatId,
      'message_id': messageId,
    });
  }

  Future<void> setReaction({
    required int chatId,
    required int messageId,
    required String emoji,
  }) async {
    await _postJson('setMessageReaction', <String, Object?>{
      'chat_id': chatId,
      'message_id': messageId,
      'reaction': <Map<String, String>>[
        <String, String>{'type': 'emoji', 'emoji': emoji},
      ],
      'is_big': false,
    });
  }

  // --- File handling: large files + streaming ---

  Future<String> getFilePath(String fileId) async {
    if (fileId.isEmpty) throw TelegramApiException('معرف الملف فارغ');
    final fileData = await _postJson('getFile', <String, Object?>{'file_id': fileId});
    final filePath = _asString(_asMap(fileData['result'])?['file_path']);
    if (filePath == null || filePath.isEmpty) {
      throw TelegramApiException('لم يرجع تلغرام مسار الملف.');
    }
    return filePath;
  }

  Future<Uri> getFileUrl(String fileId) async {
    final path = await getFilePath(fileId);
    return _fileUri(path);
  }

  Future<Uri?> tryGetFileUrlForAttachment(TelegramAttachment attachment) async {
    final fid = attachment.fileId;
    if (fid == null || fid.isEmpty) return null;
    try {
      return await getFileUrl(fid);
    } catch (_) {
      return null;
    }
  }

  Future<File> cacheAttachment(TelegramAttachment attachment) async {
    return _downloadAttachment(attachment, saveToDownloads: false);
  }

  Future<File> saveAttachmentToDownloads(TelegramAttachment attachment) async {
    return _downloadAttachment(attachment, saveToDownloads: true);
  }

  Future<File> _downloadAttachment(
    TelegramAttachment attachment, {
    required bool saveToDownloads,
  }) async {
    final fileId = attachment.fileId;
    if (fileId == null || fileId.isEmpty) {
      throw TelegramApiException('هذا المرفق لا يحتوي ملفاً قابلاً للتنزيل.');
    }
    final filePath = await getFilePath(fileId);

    final directory = saveToDownloads ? await _downloadDirectory() : await _cacheDirectory();
    final filename = _safeFilename(attachment, filePath);
    final file = File('${directory.path}${Platform.pathSeparator}$filename');

    // Streaming download to support large files (up to 2GB via Local Bot API)
    final request = http.Request('GET', _fileUri(filePath));
    final streamed = await _client.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw TelegramApiException('فشل تنزيل الملف: ${streamed.statusCode}');
    }

    final sink = file.openWrite();
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      // Try to delete partial file
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }

    return file;
  }

  Future<Map<String, dynamic>> _postJson(
    String method,
    Map<String, Object?> payload,
  ) async {
    final response = await _client.post(
      _apiUri(method),
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw TelegramApiException('استجابة غير متوقعة من تلغرام.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        json['ok'] != true) {
      final description = _asString(json['description']) ?? 'خطأ غير معروف';
      throw TelegramApiException(description);
    }
    return json;
  }

  Future<Directory> _downloadDirectory() async {
    final base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}KimomeMessage');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> _cacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}media_cache');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> stickerCacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}stickers');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _safeFilename(TelegramAttachment attachment, String filePath) {
    final fallback = filePath.split('/').last;
    final preferred = attachment.fileName;
    final name = (preferred == null || preferred.trim().isEmpty) ? fallback : preferred;
    final cleaned = name.replaceAll(RegExp(r'[<>:\"/\\|?*\x00-\x1F]'), '_');
    final usableName = cleaned.trim().isEmpty ? 'telegram_file' : cleaned;

    // Telegram commonly calls every sticker "sticker.webp". Reusing that name
    // overwrote the old file, which made all rendered stickers turn into the
    // latest one. A stable Telegram unique id gives every attachment its own
    // immutable cache file while still retaining a useful extension.
    final identity = attachment.uniqueId ?? attachment.fileId ?? filePath;
    final safeIdentity = identity
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final dot = usableName.lastIndexOf('.');
    final base = dot > 0 ? usableName.substring(0, dot) : usableName;
    final extension = dot > 0 ? usableName.substring(dot) : '';
    final suffix = safeIdentity.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : safeIdentity;
    return '${base}_$suffix$extension';
  }
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

String _normalizeBaseUrl(String value) {
  final normalized = value.trim().isEmpty ? 'https://api.telegram.org' : value.trim();
  return normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
}

String? _asString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}
