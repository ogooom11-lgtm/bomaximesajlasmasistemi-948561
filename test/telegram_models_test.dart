import 'package:flutter_test/flutter_test.dart';
import 'package:kimomesage/src/models/telegram_models.dart';

void main() {
  test('parses multiline Telegram messages with downloadable media', () {
    final message = TelegramMessage.fromRawMessage(<String, dynamic>{
      'message_id': 12,
      'date': 1767225600,
      'chat': <String, dynamic>{
        'id': 77,
        'type': 'private',
        'first_name': 'Baraa',
      },
      'from': <String, dynamic>{'id': 9, 'first_name': 'Baraa'},
      'text': 'hello\nworld',
      'photo': <Map<String, dynamic>>[
        <String, dynamic>{
          'file_id': 'small',
          'file_unique_id': 'small_unique',
          'width': 64,
          'height': 64,
        },
        <String, dynamic>{
          'file_id': 'large',
          'file_unique_id': 'large_unique',
          'width': 1280,
          'height': 720,
          'file_size': 1048576,
        },
      ],
    }, botId: 42);

    expect(message.chat.displayTitle, 'Baraa');
    expect(message.isOutgoing, isFalse);
    expect(message.contentText, 'hello\nworld');
    expect(message.attachments.single.kind, AttachmentKind.photo);
    expect(message.attachments.single.fileId, 'large');
    expect(message.attachments.single.canDownload, isTrue);
    expect(message.canDelete, isFalse);
  });

  test('only outgoing sent messages can be deleted for everyone', () {
    final chat = TelegramChat(id: 77, type: 'private', title: 'Test chat');
    final incoming = TelegramMessage(
      id: '77:1',
      chat: chat,
      messageId: 1,
      date: DateTime(2026),
      isOutgoing: false,
      delivery: MessageDelivery.received,
      text: 'incoming',
    );
    final outgoing = TelegramMessage(
      id: '77:2',
      chat: chat,
      messageId: 2,
      date: DateTime(2026),
      isOutgoing: true,
      delivery: MessageDelivery.sent,
      text: 'outgoing',
    );

    expect(incoming.canDelete, isFalse);
    expect(outgoing.canDelete, isTrue);
  });
}
