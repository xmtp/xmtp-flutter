import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import 'database.dart' as db;

/// Adapters for converting conversations and messages for storage.
///
/// These convert between their [xmtp] form for display and
/// and their [Database] form for storage.

/// Adapts an [xmtp.Conversation] into a [db.Conversation] for storage.
extension XmtpToDbConversation on xmtp.Conversation {
  db.Conversation toDb() => db.Conversation(
        topic: topic,
        version: version.index,
        createdAt: createdAt.millisecondsSinceEpoch,
        invite: invite.writeToBuffer(),
        me: me.hexEip55,
        peer: peer.hexEip55,
        lastOpenedAt: 0,
      );
}

/// Adapts a [db.Conversation] into an [xmtp.Conversation] for display.
extension DbToXmtpConversation on db.Conversation {
  xmtp.Conversation toXmtp() {
    if (xmtp.Message_Version.values[version] == xmtp.Message_Version.v1) {
      return xmtp.Conversation.v1(
        DateTime.fromMillisecondsSinceEpoch(createdAt),
        me: EthereumAddress.fromHex(me),
        peer: EthereumAddress.fromHex(peer),
      );
    }
    return xmtp.Conversation.v2(
      xmtp.InvitationV1.fromBuffer(invite),
      DateTime.fromMillisecondsSinceEpoch(createdAt),
      me: EthereumAddress.fromHex(me),
      peer: EthereumAddress.fromHex(peer),
    );
  }
}

/// Adapts an [xmtp.DecodedMessage] into a [db.Message] for storage.
extension XmtpToDbMessage on xmtp.DecodedMessage {
  db.Message toDb() => db.Message(
        id: id,
        topic: topic,
        version: version.index,
        sentAt: sentAt.millisecondsSinceEpoch,
        encoded: encoded.writeToBuffer(),
        sender: sender.hexEip55,
      );
}

/// Adapts a [db.Message] into an [xmtp.DecodedMessage] for display.
extension DbToXmtpMessage on db.Message {
  Future<xmtp.DecodedMessage> toXmtp(
      xmtp.Codec<xmtp.DecodedContent> decoder) async {
    // We do not store the decoded content.
    // Instead we must decode it when we load from the DB for display.
    var encodedParsed = xmtp.EncodedContent.fromBuffer(encoded);
    var decoded = await decoder.decode(encodedParsed);
    return xmtp.DecodedMessage(
      topic: topic,
      id: id,
      xmtp.Message_Version.values[version],
      DateTime.fromMillisecondsSinceEpoch(sentAt),
      EthereumAddress.fromHex(sender),
      encodedParsed,
      decoded.contentType,
      decoded.content,
    );
  }
}
