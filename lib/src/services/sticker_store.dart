import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/telegram_models.dart';
import 'telegram_bot_api.dart';

/// Persists received stickers to a dedicated directory so the user can reuse
/// them from a gallery without re-downloading them every time.
class StickerStore {
  Directory? _dir;

  static const Set<String> _extensions = <String>{
    '.webp',
    '.tgs',
    '.webm',
    '.png',
    '.jpg',
    '.jpeg',
  };

  Future<Directory> _directory() async {
    final cached = _dir;
    if (cached != null) {
      return cached;
    }
    final base = await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}stickers',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return _dir = directory;
  }

  /// All saved stickers, newest first.
  Future<List<File>> listStickers() async {
    final directory = await _directory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => _extensions.contains(_extensionOf(file.path)))
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return files;
  }

  /// Downloads and saves a sticker once, keyed by its unique id so the same
  /// sticker is never duplicated.
  Future<File?> saveSticker(
    TelegramAttachment attachment,
    TelegramBotApi api,
  ) async {
    final uniqueId = attachment.uniqueId ?? attachment.fileId;
    if (uniqueId == null || uniqueId.trim().isEmpty) {
      return null;
    }
    if (!attachment.canDownload) {
      return null;
    }
    final directory = await _directory();
    final extension = _extensionOf(attachment.fileName);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '${_safeName(uniqueId)}$extension',
    );
    if (await target.exists()) {
      return target;
    }
    try {
      final downloaded = await api.cacheAttachment(attachment);
      await downloaded.copy(target.path);
      return target;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSticker(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _extensionOf(String? filename) {
    if (filename == null) {
      return '.webp';
    }
    final index = filename.lastIndexOf('.');
    if (index < 0 || index == filename.length - 1) {
      return '.webp';
    }
    final extension = filename.substring(index).toLowerCase();
    return _extensions.contains(extension) ? extension : '.webp';
  }

  String _safeName(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }
}
