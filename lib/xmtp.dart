/// Library containing the XMTP client SDK
/// for Flutter applications written in dart.
library xmtp;

export 'src/auth.dart' show CompatPrivateKeyBundle;
export 'src/common/api.dart' show Api, ApiEnv;
export 'src/common/signature.dart' show Signer, CredentialsToSigner;
export 'src/client.dart' show Client;
export 'src/conversation/conversation.dart' show Conversation, GroupConversation, DirectConversation;
export 'src/content/decoded.dart' show DecodedContent, DecodedMessage;
export 'src/content/codec.dart' show Codec;
export 'src/content/codec_registry.dart' show CodecRegistry;
export 'src/content/text_codec.dart' show contentTypeText, TextCodec;
export 'package:xmtp_proto/xmtp_proto.dart' hide DecodedMessage;
