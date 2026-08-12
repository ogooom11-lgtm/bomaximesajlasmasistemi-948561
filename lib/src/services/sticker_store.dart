import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/telegram_models.dart';

class SavedSticker {
  SavedSticker({
    required this.fileId,
    required this.uniqueId,
    this.emoji,
    this.fileName,
    this.localPath,
    this.isAnimated = false,
    this.isVideo = false,
    this.width,
    this.height,
    this.fileSize,
    int? addedAt,
  }) : addedAt = addedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String fileId;
  final String uniqueId;
  final String? emoji;
  final String? fileName;
  final String? localPath;
  final bool isAnimated;
  final bool isVideo;
  final int? width;
  final int? height;
  final int? fileSize;
  final int addedAt;

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'unique_id': uniqueId,
        'emoji': emoji,
        'file_name': fileName,
        'local_path': localPath,
        'is_animated': isAnimated,
        'is_video': isVideo,
        'width': width,
        'height': height,
        'file_size': fileSize,
        'added_at': addedAt,
      };

  factory SavedSticker.fromJson(Map<String, dynamic> json) => SavedSticker(
        fileId: json['file_id']?.toString() ?? '',
        uniqueId: json['unique_id']?.toString() ?? '',
        emoji: json['emoji']?.toString(),
        fileName: json['file_name']?.toString(),
        localPath: json['local_path']?.toString(),
        isAnimated: json['is_animated'] == true,
        isVideo: json['is_video'] == true,
        width: json['width'] is int ? json['width'] : int.tryParse(json['width']?.toString() ?? ''),
        height: json['height'] is int ? json['height'] : int.tryParse(json['height']?.toString() ?? ''),
        fileSize: json['file_size'] is int ? json['file_size'] : int.tryParse(json['file_size']?.toString() ?? ''),
        addedAt: json['added_at'] is int ? json['added_at'] : int.tryParse(json['added_at']?.toString() ?? ''),
      );

  factory SavedSticker.fromAttachment(TelegramAttachment attachment, {String? localPath}) {
    return SavedSticker(
      fileId: attachment.fileId ?? '',
      uniqueId: attachment.uniqueId ?? attachment.fileId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      emoji: attachment.emoji,
      fileName: attachment.fileName,
      localPath: localPath ?? attachment.localPath,
      isAnimated: attachment.isAnimatedSticker,
      isVideo: attachment.isVideoSticker,
      width: attachment.width,
      height: attachment.height,
      fileSize: attachment.fileSize,
    );
  }
}

class StickerStore extends ChangeNotifier {
  static const _prefsKey = 'saved_stickers_v1';
  static const _maxStickers = 500;

  SharedPreferences? _prefs;
  final List<SavedSticker> _stickers = [];

  List<SavedSticker> get stickers => List<SavedSticker>.unmodifiable(
      _stickers..sort((a, b) => b.addedAt.compareTo(a.addedAt)));

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final map = item.map((k, v) => MapEntry(k.toString(), v));
              final sticker = SavedSticker.fromJson(map);
              if (sticker.fileId.isNotEmpty) {
                _stickers.add(sticker);
              }
            }
          }
        }
      } catch (_) {}
    }
    // Clean up missing files
    await _pruneMissingFiles();
    _loaded = true;
    notifyListeners();
  }

  Future<void> addSticker(SavedSticker sticker) async {
    if (sticker.fileId.isEmpty) return;
    // Avoid duplicates by uniqueId
    final existingIdx = _stickers.indexWhere((s) => s.uniqueId == sticker.uniqueId || (s.fileId == sticker.fileId && sticker.fileId.isNotEmpty));
    if (existingIdx >= 0) {
      // Update local path if new one provided
      final existing = _stickers[existingIdx];
      if (sticker.localPath != null && sticker.localPath!.isNotEmpty) {
        _stickers[existingIdx] = SavedSticker(
          fileId: existing.fileId,
          uniqueId: existing.uniqueId,
          emoji: sticker.emoji ?? existing.emoji,
          fileName: sticker.fileName ?? existing.fileName,
          localPath: sticker.localPath,
          isAnimated: existing.isAnimated || sticker.isAnimated,
          isVideo: existing.isVideo || sticker.isVideo,
          width: existing.width ?? sticker.width,
          height: existing.height ?? sticker.height,
          fileSize: existing.fileSize ?? sticker.fileSize,
          addedAt: existing.addedAt,
        );
      }
      await _persist();
      notifyListeners();
      return;
    }

    _stickers.insert(0, sticker);
    if (_stickers.length > _maxStickers) {
      final removed = _stickers.removeLast();
      // optionally delete file
      if (removed.localPath != null) {
        try {
          final f = File(removed.localPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> addFromAttachment(TelegramAttachment attachment, {String? localPath}) async {
    if (attachment.kind != AttachmentKind.sticker) return;
    if (attachment.fileId == null || attachment.fileId!.isEmpty) return;
    final sticker = SavedSticker.fromAttachment(attachment, localPath: localPath ?? attachment.localPath);
    await addSticker(sticker);
  }

  Future<void> removeSticker(String uniqueId) async {
    _stickers.removeWhere((s) => s.uniqueId == uniqueId);
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _stickers.clear();
    await _persist();
    notifyListeners();
  }

  Future<Directory> _stickerDirectory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}stickers');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _pruneMissingFiles() async {
    bool changed = false;
    final toRemove = <SavedSticker>[];
    for (final s in _stickers) {
      if (s.localPath != null && s.localPath!.isNotEmpty) {
        final f = File(s.localPath!);
        if (!await f.exists()) {
          // keep sticker but clear path? Instead keep but path may be invalid later re-download
          // For now keep but don't remove
        }
      }
    }
    if (changed) await _persist();
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    final list = _stickers.map((s) => s.toJson()).toList();
    await _prefs?.setString(_prefsKey, jsonEncode(list));
  }

  bool contains(String fileId, String uniqueId) {
    return _stickers.any((s) => s.uniqueId == uniqueId || s.fileId == fileId);
  }
}
