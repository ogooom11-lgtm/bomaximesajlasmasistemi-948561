enum AttachmentKind {
  photo,
  document,
  video,
  audio,
  voice,
  videoNote,
  sticker,
  animation,
  contact,
  location,
  venue,
  poll,
  dice,
  unknown,
}

enum MessageDelivery { received, sending, sent, failed, edited, deleted }

class TelegramChat {
  const TelegramChat({
    required this.id,
    required this.type,
    this.title,
    this.username,
    this.firstName,
    this.lastName,
  });

  final int id;
  final String type;
  final String? title;
  final String? username;
  final String? firstName;
  final String? lastName;

  bool get isGroup => type == 'group' || type == 'supergroup';

  bool get isChannel => type == 'channel';

  String get displayTitle {
    final resolved =
        title ??
        [firstName, lastName]
            .where((part) => part != null && part.trim().isNotEmpty)
            .join(' ')
            .trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }
    if (username != null && username!.trim().isNotEmpty) {
      return '@$username';
    }
    return 'محادثة $id';
  }

  factory TelegramChat.fromJson(Map<String, dynamic> json) {
    return TelegramChat(
      id: _asInt(json['id']) ?? 0,
      type: _asString(json['type']) ?? 'private',
      title: _asString(json['title']),
      username: _asString(json['username']),
      firstName: _asString(json['first_name']),
      lastName: _asString(json['last_name']),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'title': title,
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
    };
  }
}

class TelegramAttachment {
  const TelegramAttachment({
    required this.kind,
    this.fileId,
    this.uniqueId,
    this.fileName,
    this.mimeType,
    this.fileSize,
    this.width,
    this.height,
    this.duration,
    this.emoji,
    this.description,
    this.localPath,
    this.isAnimatedSticker = false,
    this.isVideoSticker = false,
  });

  final AttachmentKind kind;
  final String? fileId;
  final String? uniqueId;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;
  final int? width;
  final int? height;
  final int? duration;
  final String? emoji;
  final String? description;
  final String? localPath;
  final bool isAnimatedSticker;
  final bool isVideoSticker;

  bool get canDownload => fileId != null && fileId!.isNotEmpty;

  String get label {
    if (description != null && description!.trim().isNotEmpty) {
      return description!;
    }
    final base = switch (kind) {
      AttachmentKind.photo => 'صورة',
      AttachmentKind.document => 'ملف',
      AttachmentKind.video => 'فيديو',
      AttachmentKind.audio => 'صوت',
      AttachmentKind.voice => 'رسالة صوتية',
      AttachmentKind.videoNote => 'فيديو دائري',
      AttachmentKind.sticker => 'ملصق ${emoji ?? ''}'.trim(),
      AttachmentKind.animation => 'صورة متحركة',
      AttachmentKind.contact => 'جهة اتصال',
      AttachmentKind.location => 'موقع',
      AttachmentKind.venue => 'مكان',
      AttachmentKind.poll => 'استطلاع',
      AttachmentKind.dice => 'نرد',
      AttachmentKind.unknown => 'مرفق',
    };
    final name = fileName;
    if (name == null || name.isEmpty || name == base) {
      return base;
    }
    return '$base · $name';
  }

  String get sizeLabel {
    final size = fileSize;
    if (size == null || size <= 0) {
      return '';
    }
    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  TelegramAttachment copyWith({String? localPath}) {
    return TelegramAttachment(
      kind: kind,
      fileId: fileId,
      uniqueId: uniqueId,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: fileSize,
      width: width,
      height: height,
      duration: duration,
      emoji: emoji,
      description: description,
      localPath: localPath ?? this.localPath,
      isAnimatedSticker: isAnimatedSticker,
      isVideoSticker: isVideoSticker,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'kind': kind.name,
      'file_id': fileId,
      'unique_id': uniqueId,
      'file_name': fileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'width': width,
      'height': height,
      'duration': duration,
      'emoji': emoji,
      'description': description,
      'local_path': localPath,
      'is_animated_sticker': isAnimatedSticker,
      'is_video_sticker': isVideoSticker,
    };
  }

  factory TelegramAttachment.fromCacheJson(Map<String, dynamic> json) {
    return TelegramAttachment(
      kind:
          _enumByName(AttachmentKind.values, _asString(json['kind'])) ??
          AttachmentKind.unknown,
      fileId: _asString(json['file_id']),
      uniqueId: _asString(json['unique_id']),
      fileName: _asString(json['file_name']),
      mimeType: _asString(json['mime_type']),
      fileSize: _asInt(json['file_size']),
      width: _asInt(json['width']),
      height: _asInt(json['height']),
      duration: _asInt(json['duration']),
      emoji: _asString(json['emoji']),
      description: _asString(json['description']),
      localPath: _asString(json['local_path']),
      isAnimatedSticker: json['is_animated_sticker'] == true,
      isVideoSticker: json['is_video_sticker'] == true,
    );
  }
}

class TelegramMessage {
  const TelegramMessage({
    required this.id,
    required this.chat,
    required this.messageId,
    required this.date,
    required this.isOutgoing,
    required this.delivery,
    this.updateId,
    this.fromName,
    this.text,
    this.caption,
    this.reactions = const <String, String>{},
    this.replyToMessageId,
    this.attachments = const <TelegramAttachment>[],
  });

  final String id;
  final TelegramChat chat;
  final int messageId;
  final int? updateId;
  final DateTime date;
  final bool isOutgoing;
  final MessageDelivery delivery;
  final String? fromName;
  final String? text;
  final String? caption;
  final Map<String, String> reactions;
  final int? replyToMessageId;
  final List<TelegramAttachment> attachments;

  String? get reactionEmoji =>
      reactions.isEmpty ? null : reactions.values.first;

  String get contentText {
    final value = text ?? caption;
    if (value != null && value.trim().isNotEmpty) {
      return value;
    }
    if (delivery == MessageDelivery.deleted) {
      return 'تم حذف الرسالة';
    }
    if (attachments.isNotEmpty) {
      return attachments.map((item) => item.label).join('، ');
    }
    return 'رسالة بدون نص';
  }

  String get previewText {
    final text = contentText.replaceAll('\n', ' ').trim();
    if (text.length <= 80) {
      return text;
    }
    return '${text.substring(0, 80)}...';
  }

  bool get canEdit =>
      isOutgoing &&
      delivery != MessageDelivery.deleted &&
      (text != null || caption != null) &&
      attachments.isEmpty;

  bool get canDelete =>
      isOutgoing &&
      delivery != MessageDelivery.deleted &&
      delivery != MessageDelivery.sending &&
      delivery != MessageDelivery.failed &&
      messageId > 0;

  TelegramMessage copyWith({
    MessageDelivery? delivery,
    String? text,
    String? caption,
    String? reactionEmoji,
    String? reactionActor,
    Map<String, String>? reactions,
    bool clearReaction = false,
    List<TelegramAttachment>? attachments,
  }) {
    final resolvedReactions = <String, String>{
      ...this.reactions,
      if (reactions != null) ...reactions,
    };
    if (clearReaction) {
      if (reactionActor == null) {
        resolvedReactions.clear();
      } else {
        resolvedReactions.remove(reactionActor);
      }
    } else if (reactionEmoji != null) {
      resolvedReactions[reactionActor ?? 'أنت'] = reactionEmoji;
    }
    return TelegramMessage(
      id: id,
      chat: chat,
      messageId: messageId,
      updateId: updateId,
      date: date,
      isOutgoing: isOutgoing,
      delivery: delivery ?? this.delivery,
      fromName: fromName,
      text: text ?? this.text,
      caption: caption ?? this.caption,
      reactions: resolvedReactions,
      replyToMessageId: replyToMessageId,
      attachments: attachments ?? this.attachments,
    );
  }

  factory TelegramMessage.localPending({
    required TelegramChat chat,
    required int temporaryMessageId,
    required String text,
    int? replyToMessageId,
  }) {
    return TelegramMessage(
      id: '${chat.id}:$temporaryMessageId',
      chat: chat,
      messageId: temporaryMessageId,
      date: DateTime.now(),
      isOutgoing: true,
      delivery: MessageDelivery.sending,
      text: text,
      replyToMessageId: replyToMessageId,
      fromName: 'KimomeMessage',
    );
  }

  factory TelegramMessage.fromRawMessage(
    Map<String, dynamic> json, {
    required int botId,
    int? updateId,
    bool edited = false,
  }) {
    final chat = TelegramChat.fromJson(_asMap(json['chat']) ?? {});
    final from = _asMap(json['from']);
    final fromId = _asInt(from?['id']);
    final fromName = _senderName(from);
    final messageId = _asInt(json['message_id']) ?? 0;
    final attachments = _attachmentsFrom(json);
    final dateSeconds = _asInt(json['edit_date']) ?? _asInt(json['date']) ?? 0;
    return TelegramMessage(
      id: '${chat.id}:$messageId',
      chat: chat,
      messageId: messageId,
      updateId: updateId,
      date: DateTime.fromMillisecondsSinceEpoch(dateSeconds * 1000),
      isOutgoing: fromId == botId,
      delivery: edited ? MessageDelivery.edited : MessageDelivery.received,
      fromName: fromName,
      text: _asString(json['text']),
      caption: _asString(json['caption']),
      replyToMessageId: _asInt(_asMap(json['reply_to_message'])?['message_id']),
      attachments: attachments,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'id': id,
      'chat': chat.toCacheJson(),
      'message_id': messageId,
      'update_id': updateId,
      'date': date.millisecondsSinceEpoch,
      'is_outgoing': isOutgoing,
      'delivery': delivery.name,
      'from_name': fromName,
      'text': text,
      'caption': caption,
      'reactions': reactions,
      'reply_to_message_id': replyToMessageId,
      'attachments': attachments.map((item) => item.toCacheJson()).toList(),
    };
  }

  factory TelegramMessage.fromCacheJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    final rawReactions = json['reactions'];
    final reactions = <String, String>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        final actor = entry.key.toString();
        final emoji = entry.value?.toString();
        if (actor.trim().isNotEmpty &&
            emoji != null &&
            emoji.trim().isNotEmpty) {
          reactions[actor] = emoji;
        }
      }
    } else {
      final emoji = _asString(json['reaction_emoji']);
      if (emoji != null) {
        reactions['أنت'] = emoji;
      }
    }
    return TelegramMessage(
      id: _asString(json['id']) ?? '',
      chat: TelegramChat.fromJson(_asMap(json['chat']) ?? {}),
      messageId: _asInt(json['message_id']) ?? 0,
      updateId: _asInt(json['update_id']),
      date: DateTime.fromMillisecondsSinceEpoch(_asInt(json['date']) ?? 0),
      isOutgoing: json['is_outgoing'] == true,
      delivery:
          _enumByName(MessageDelivery.values, _asString(json['delivery'])) ??
          MessageDelivery.received,
      fromName: _asString(json['from_name']),
      text: _asString(json['text']),
      caption: _asString(json['caption']),
      reactions: reactions,
      replyToMessageId: _asInt(json['reply_to_message_id']),
      attachments: rawAttachments is List
          ? rawAttachments
                .map((item) => _asMap(item))
                .whereType<Map<String, dynamic>>()
                .map(TelegramAttachment.fromCacheJson)
                .toList(growable: false)
          : const <TelegramAttachment>[],
    );
  }
}

class BotIdentity {
  const BotIdentity({
    required this.id,
    required this.username,
    required this.firstName,
  });

  final int id;
  final String username;
  final String firstName;

  factory BotIdentity.fromJson(Map<String, dynamic> json) {
    return BotIdentity(
      id: _asInt(json['id']) ?? 0,
      username: _asString(json['username']) ?? '',
      firstName: _asString(json['first_name']) ?? 'Telegram Bot',
    );
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

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) {
    return null;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
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
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}

String? _senderName(Map<String, dynamic>? from) {
  if (from == null) {
    return null;
  }
  final username = _asString(from['username']);
  if (username != null) {
    return '@$username';
  }
  final name = [
    _asString(from['first_name']),
    _asString(from['last_name']),
  ].whereType<String>().join(' ').trim();
  return name.isEmpty ? null : name;
}

String _fallbackAttachmentName(
  AttachmentKind kind,
  Map<String, dynamic> item,
  String? fallbackName,
) {
  if (kind == AttachmentKind.sticker) {
    if (item['is_video'] == true) {
      return 'sticker.webm';
    }
    if (item['is_animated'] == true) {
      return 'sticker.tgs';
    }
    return fallbackName ?? 'sticker.webp';
  }
  return fallbackName ?? kind.name;
}

List<TelegramAttachment> _attachmentsFrom(Map<String, dynamic> json) {
  final attachments = <TelegramAttachment>[];

  final photos = json['photo'];
  if (photos is List && photos.isNotEmpty) {
    final raw =
        photos
            .map((item) => _asMap(item))
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort((a, b) {
            final aSize =
                (_asInt(a['width']) ?? 0) * (_asInt(a['height']) ?? 0);
            final bSize =
                (_asInt(b['width']) ?? 0) * (_asInt(b['height']) ?? 0);
            return bSize.compareTo(aSize);
          });
    final photo = raw.first;
    attachments.add(
      TelegramAttachment(
        kind: AttachmentKind.photo,
        fileId: _asString(photo['file_id']),
        uniqueId: _asString(photo['file_unique_id']),
        fileSize: _asInt(photo['file_size']),
        width: _asInt(photo['width']),
        height: _asInt(photo['height']),
        fileName:
            'photo_${_asString(photo['file_unique_id']) ?? 'telegram'}.jpg',
      ),
    );
  }

  void addFileAttachment(
    String field,
    AttachmentKind kind, {
    String? fallbackName,
  }) {
    final item = _asMap(json[field]);
    if (item == null) {
      return;
    }
    attachments.add(
      TelegramAttachment(
        kind: kind,
        fileId: _asString(item['file_id']),
        uniqueId: _asString(item['file_unique_id']),
        fileName:
            _asString(item['file_name']) ??
            _fallbackAttachmentName(kind, item, fallbackName),
        mimeType: _asString(item['mime_type']),
        fileSize: _asInt(item['file_size']),
        width: _asInt(item['width']),
        height: _asInt(item['height']),
        duration: _asInt(item['duration']),
        emoji: _asString(item['emoji']),
        isAnimatedSticker:
            kind == AttachmentKind.sticker && item['is_animated'] == true,
        isVideoSticker:
            kind == AttachmentKind.sticker && item['is_video'] == true,
      ),
    );
  }

  addFileAttachment(
    'document',
    AttachmentKind.document,
    fallbackName: 'document',
  );
  addFileAttachment('video', AttachmentKind.video, fallbackName: 'video.mp4');
  addFileAttachment('audio', AttachmentKind.audio, fallbackName: 'audio');
  addFileAttachment('voice', AttachmentKind.voice, fallbackName: 'voice.ogg');
  addFileAttachment(
    'video_note',
    AttachmentKind.videoNote,
    fallbackName: 'video_note.mp4',
  );
  addFileAttachment(
    'sticker',
    AttachmentKind.sticker,
    fallbackName: 'sticker.webp',
  );
  addFileAttachment(
    'animation',
    AttachmentKind.animation,
    fallbackName: 'animation.mp4',
  );

  final contact = _asMap(json['contact']);
  if (contact != null) {
    final name = [
      _asString(contact['first_name']),
      _asString(contact['last_name']),
    ].whereType<String>().join(' ').trim();
    attachments.add(
      TelegramAttachment(
        kind: AttachmentKind.contact,
        description:
            '${name.isEmpty ? 'جهة اتصال' : name} · ${_asString(contact['phone_number']) ?? ''}',
      ),
    );
  }

  final location = _asMap(json['location']);
  if (location != null) {
    attachments.add(
      TelegramAttachment(
        kind: AttachmentKind.location,
        description:
            'موقع: ${location['latitude'] ?? '-'}, ${location['longitude'] ?? '-'}',
      ),
    );
  }

  final venue = _asMap(json['venue']);
  if (venue != null) {
    attachments.add(
      TelegramAttachment(
        kind: AttachmentKind.venue,
        description:
            'مكان: ${_asString(venue['title']) ?? 'بدون اسم'} · ${_asString(venue['address']) ?? ''}',
      ),
    );
  }

  final poll = _asMap(json['poll']);
  if (poll != null) {
    attachments.add(
      TelegramAttachment(
        kind: AttachmentKind.poll,
        description: 'استطلاع: ${_asString(poll['question']) ?? ''}',
      ),
    );
  }

  final dice = _asMap(json['dice']);
  if (dice != null) {
    attachments.add(
      TelegramAttachment(
        kind: AttachmentKind.dice,
        description:
            '${_asString(dice['emoji']) ?? '🎲'} ${_asInt(dice['value']) ?? ''}',
      ),
    );
  }

  return attachments;
}
