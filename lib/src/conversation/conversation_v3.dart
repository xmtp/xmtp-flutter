
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:quiver/iterables.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../common/api.dart';
import '../common/time64.dart';
import '../content/decoded.dart';
import '../content/codec_registry.dart';
import '../content/text_codec.dart';
import 'conversation.dart';
import 'package:xmtp_bindings_flutter/xmtp_bindings_flutter.dart' as libxmtp;

/// This manages all V3 (MLS) conversations.
/// It provides instances of the V3 implementation of [Conversation].
/// NOTE: it aims to limit exposure of the V3 specific details.
class ConversationManagerV3 {
  final EthereumAddress _me;
  final libxmtp.Client _client;
  final CodecRegistry _codecs;

  ConversationManagerV3(
    this._me,
    this._client,
    this._codecs,
  );

  Future<List<GroupConversation>> listGroups(
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort, // TODO: sort these
  ) async {
    var listing = await _client.listGroups(
      createdAfterNs: start?.toNs64().toInt(),
      createdBeforeNs: end?.toNs64().toInt(),
      limit: limit,
    );
    return listing
        .map((group) => GroupConversation.v3(
            group.groupId, Int64(group.createdAtNs).toDateTime()))
        .toList();
  }

  Stream<GroupConversation> streamConversations() {
    return const Stream.empty(); // TODO:
    // return _client.streamGroups().map((group) {
    //   return GroupConversation.v3(
    //       group.groupId, Int64(group.createdAtNs).toDateTime());
    // });
  }

  Future<GroupConversation> createGroup(List<String> addresses) async {
    var g = await _client.createGroup(accountAddresses: addresses);
    return GroupConversation.v3(g.groupId, Int64(g.createdAtNs).toDateTime());
  }

  /// This lists the current messages in the [conversations]
  Future<List<DecodedMessage>> listMessages(
    Iterable<GroupConversation> conversations, {
    Iterable<Pagination>? paginations,
    xmtp.SortDirection? sort,
  }) async {
    if (conversations.isEmpty) {
      return [];
    }
    var ps = paginations?.toList();
    // For now the batch lists are performed separately.
    // TODO: support batch listing in rust
    var listings = await Future.wait(
        enumerate(conversations).map((c) => _client.listMessages(
              groupId: c.value.groupId,
              sentAfterNs: ps?[c.index].start?.toNs64().toInt(),
              sentBeforeNs: ps?[c.index].end?.toNs64().toInt(),
              limit: ps?[c.index].limit,
            )));
    // await the list of lists of decoding messages
    var decoding = await Future.wait(listings.map((listing) =>
        Future.wait(listing.map((encoded) => _createDecodedMessage(encoded)))));
    return decoding
        // flatten the list of lists
        .expand((l) => l)
        // drop any null values (failed to decode)
        .whereType<DecodedMessage>()
        .toList()
      ..sorted((DecodedMessage e1, DecodedMessage e2) =>
          sort == xmtp.SortDirection.SORT_DIRECTION_ASCENDING
              ? e1.sentAt.compareTo(e2.sentAt)
              : e2.sentAt.compareTo(e1.sentAt));
  }

  /// This creates the [DecodedMessage] from the various parts.
  Future<DecodedMessage?> _createDecodedMessage(
    libxmtp.Message msg,
  ) async {
    var encoded = xmtp.EncodedContent.fromBuffer(msg.contentBytes);
    var decoded = await _codecs.decode(encoded);
    var id = bytesToHex(msg.id);
    var sender = EthereumAddress.fromHex(msg.senderAccountAddress);
    var sentAt = Int64(msg.sentAtNs).toDateTime();
    var topic =
        bytesToHex(msg.groupId); // HACK: to be refactored out eventually
    return DecodedMessage(
      xmtp.Message_Version.notSet, // TODO: consider refactor to clarify
      sentAt,
      sender,
      encoded,
      decoded.contentType,
      decoded.content,
      id: id,
      topic: topic,
    );
  }

  Future<DecodedMessage> sendMessage(
    GroupConversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
  }) async {
    contentType ??= contentTypeText;
    var encoded = await _codecs.encode(DecodedContent(contentType, content));
    var sent = await sendMessageEncoded(conversation, encoded);
    return sent!;
  }

  Future<DecodedMessage?> sendMessageEncoded(
    GroupConversation conversation,
    xmtp.EncodedContent encoded,
  ) async {
    var contentBytes = encoded.writeToBuffer();
    await _client.sendMessage(
      groupId: conversation.groupId,
      contentBytes: contentBytes,
    );
    return _createDecodedMessage(libxmtp.Message(
      id: Uint8List(0), // TODO: return the real ID from rust
      sentAtNs: nowNs().toInt(), // TODO: return the real sentAt from rust
      groupId: conversation.groupId,
      senderAccountAddress: _me.hex,
      contentBytes: contentBytes,
    ));
  }

  Stream<DecodedMessage> streamMessages(
      Iterable<GroupConversation> conversations) {
    if (conversations.isEmpty) {
      return const Stream.empty();
    }
    // TODO: support streaming messages in libxmtp bindings
    var stream = const Stream.empty();
    // var stream = _client.streamMessages(
    //   groupIds: conversations.map((c) => c.groupId).toList(),
    // );

    return stream.asyncMap((msg) => _createDecodedMessage(msg))
        // Remove nulls (which couldn't be decoded).
        .where((msg) => msg != null)
        .map((msg) => msg!);
  }
}
