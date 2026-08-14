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
  }) : _apiBaseUrl = _normalizeBaseUrl(apiBaseUrl),
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

  Future<Map<String, dynamic>?> getChatMember({
    required int chatId,
    required int userId,
  }) async {
    final data = await _postJson('getChatMember', <String, Object?>{
      'chat_id': chatId,
      'user_id': userId,
    });
    return _asMap(data['result']);
  }

  Future<List<Map<String, dynamic>>> getUpdates({
    required int? offset,
    int timeoutSeconds = 25,
  }) async {
    final payload = <String, Object?>{
      'timeout': timeoutSeconds,
      'allowed_updates': const <String>[
        'message',
        'edited_message',
        'channel_post',
        'edited_channel_post',
        'message_reaction',
        'my_chat_member',
        'chat_member',
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
    final fileData = await _postJson('getFile', <String, Object?>{
      'file_id': fileId,
    });
    final filePath = _asString(_asMap(fileData['result'])?['file_path']);
    if (filePath == null || filePath.isEmpty) {
      throw TelegramApiException('لم يرجع تلغرام مسار الملف.');
    }

    final response = await _client.get(_fileUri(filePath));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TelegramApiException('فشل تنزيل الملف: ${response.statusCode}');
    }

    final directory = saveToDownloads
        ? await _downloadDirectory()
        : await _cacheDirectory();
    final filename = _uniqueFilename(attachment, filePath);
    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  /// Builds a collision-free cache filename. Telegram reports a generic name
  /// (e.g. `sticker.webp`) for many media types, so two different stickers
  /// would otherwise overwrite each other. A short hash of the unique id is
  /// inserted before the extension to keep every attachment distinct.
  String _uniqueFilename(TelegramAttachment attachment, String filePath) {
    final base = _safeFilename(attachment.fileName, filePath);
    final unique = attachment.uniqueId ?? attachment.fileId;
    if (unique == null || unique.isEmpty) {
      return base;
    }
    final hash = _shortHash(unique);
    final dot = base.lastIndexOf('.');
    if (dot < 0) {
      return '${base}_$hash';
    }
    return '${base.substring(0, dot)}_$hash${base.substring(dot)}';
  }

  String _shortHash(String input) {
    var hash = 0;
    for (final code in input.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(36);
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
    final base =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}KimomeMessage',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Directory> _cacheDirectory() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}media_cache',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _safeFilename(String? preferred, String filePath) {
    final fallback = filePath.split('/').last;
    final name = (preferred == null || preferred.trim().isEmpty)
        ? fallback
        : preferred;
    final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (cleaned.trim().isEmpty) {
      return 'telegram_file_${DateTime.now().millisecondsSinceEpoch}';
    }
    return cleaned;
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
  final normalized = value.trim().isEmpty
      ? 'https://api.telegram.org'
      : value.trim();
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

String? _asString(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}
