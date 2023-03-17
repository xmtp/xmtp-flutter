import 'package:xmtp/xmtp.dart' as xmtp;

/// These are all the codecs supported in the app.
final xmtp.CodecRegistry codecs = xmtp.CodecRegistry()
  ..registerCodec(xmtp.TextCodec());
