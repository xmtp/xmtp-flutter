/// Library containing the XMTP client SDK
/// for Flutter applications written in dart.
library xmtp;

export 'src/common/api.dart' show Api;
export 'src/client.dart' show Client;
export 'src/conversation/conversation.dart' show Conversation;
export 'src/content/decoded.dart' show ContentDecoder, DecodedMessage;
export 'src/content/codec.dart' show Codec;
export 'src/content/codec_registry.dart' show CodecRegistry;
export 'src/content/text_codec.dart' show contentTypeText, TextCodec;
export 'package:xmtp_proto/xmtp_proto.dart';
