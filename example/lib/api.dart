import 'package:xmtp/xmtp.dart' as xmtp;

xmtp.Api createApi() =>
    // xmtp.Api.create(host: '127.0.0.1', port: 5556, isSecure: false)
// xmtp.Api.create(host: 'dev.xmtp.network', isSecure: true)
xmtp.Api.create(host: 'production.xmtp.network', isSecure: true)
    ;
