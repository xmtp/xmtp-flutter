import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp/src/common/signature.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/contact.dart';

import 'test_server.dart';

void main() {
  test("adapting PrivateKeyBundle", () async {
    var keyBundle = xmtp.PrivateKeyBundle.fromBuffer([
      // This is a serialized PrivateKeyBundle version v2
      18, 134, 3, 10, 192, 1, 18, 34, 10, 32, 95, 35, 115,
      48, 194, 238, 23, 157, 157, 209, 5, 17, 243, 98, 39,
      121, 44, 2, 188, 41, 78, 161, 238, 42, 172, 203, 168,
      99, 179, 37, 78, 177, 26, 153, 1, 10, 79, 8, 192,
      153, 230, 166, 168, 239, 134, 149, 23, 26, 67, 10, 65,
      4, 55, 167, 183, 148, 199, 205, 246, 252, 70, 163, 96,
      96, 114, 50, 96, 202, 125, 45, 57, 216, 125, 203, 175,
      243, 180, 182, 42, 202, 97, 94, 201, 1, 237, 115, 15,
      157, 151, 40, 82, 14, 108, 211, 202, 216, 129, 102,
      149, 62, 198, 15, 118, 191, 114, 178, 214, 231, 11,
      200, 207, 132, 33, 22, 159, 195, 18, 70, 10, 68, 10,
      64, 20, 178, 29, 62, 89, 49, 12, 213, 154, 34, 28,
      21, 217, 220, 32, 179, 164, 166, 230, 189, 96, 230,
      246, 234, 140, 2, 108, 82, 107, 50, 49, 177, 34, 45,
      249, 195, 40, 19, 98, 180, 208, 240, 191, 196, 1, 237,
      157, 197, 189, 78, 187, 255, 112, 251, 26, 249, 10,
      218, 245, 214, 115, 223, 214, 236, 16, 0, 18, 192, 1,
      18, 34, 10, 32, 25, 143, 224, 23, 188, 9, 98, 182, 171,
      45, 130, 146, 73, 87, 45, 142, 194, 67, 89, 216, 193,
      35, 16, 162, 129, 80, 151, 216, 39, 167, 197, 46, 26,
      153, 1, 10, 79, 8, 192, 188, 169, 238, 168, 239, 134,
      149, 23, 26, 67, 10, 65, 4, 207, 197, 146, 222, 239,
      91, 255, 254, 1, 18, 127, 40, 209, 204, 214, 23, 189,
      205, 28, 164, 150, 197, 154, 35, 45, 173, 179, 55, 159,
      102, 227, 48, 60, 242, 36, 173, 173, 246, 231, 135, 178,
      115, 120, 10, 175, 106, 241, 251, 245, 181, 145, 45, 243,
      56, 235, 181, 11, 176, 8, 80, 114, 161, 75, 115, 18, 70,
      10, 68, 10, 64, 137, 137, 33, 205, 111, 88, 178, 159, 92,
      81, 230, 107, 5, 86, 74, 72, 69, 38, 247, 170, 219, 90,
      11, 130, 126, 198, 58, 116, 252, 203, 149, 150, 57, 96,
      172, 174, 23, 216, 5, 95, 97, 181, 72, 22, 68, 135, 211,
      178, 213, 204, 26, 75, 92, 233, 80, 192, 182, 201, 106,
      202, 182, 151, 44, 55, 16, 0,
    ]);
    var contactV1 = createContactBundleV1(keyBundle);
    var contactV2 = createContactBundleV2(keyBundle);
    expect(contactV1.whichVersion(), xmtp.ContactBundle_Version.v1);
    expect(contactV2.whichVersion(), xmtp.ContactBundle_Version.v2);

    for (var contact in [contactV1, contactV2]) {
      expect(
        contact.wallet.hexEip55,
        "0xb570d16466D9B35D1E96FA8bAdCe7C5c263C7c73",
      );
      expect(
        contact.identity.hexEip55,
        "0x5756f2Aa08d52111f2900c6C97b9611940620684",
      );
      expect(
        contact.pre.hexEip55,
        "0xBe658075774806ADf3E441870b1E6a4448682fec",
      );
    }
  });

  const serializedPublicKeyBundle = [
    // This is a serialized PublicKeyBundle (instead of a ContactBundle)
    10, 146, 1, 8, 236, 130, 192, 166, 148, 48, 18, 68,
    10, 66, 10, 64, 70, 34, 101, 46, 39, 87, 114, 210,
    103, 135, 87, 49, 162, 200, 82, 177, 11, 4, 137,
    31, 235, 91, 185, 46, 177, 208, 228, 102, 44, 61,
    40, 131, 109, 210, 93, 42, 44, 235, 177, 73, 72,
    234, 18, 32, 230, 61, 146, 58, 65, 78, 178, 163,
    164, 241, 118, 167, 77, 240, 13, 100, 151, 70, 190,
    15, 26, 67, 10, 65, 4, 8, 71, 173, 223, 174, 185,
    150, 4, 179, 111, 144, 35, 5, 210, 6, 60, 21, 131,
    135, 52, 37, 221, 72, 126, 21, 103, 208, 31, 182,
    76, 187, 72, 66, 92, 193, 74, 161, 45, 135, 204,
    55, 10, 20, 119, 145, 136, 45, 194, 140, 164, 124,
    47, 238, 17, 198, 243, 102, 171, 67, 128, 164, 117,
    7, 83,
  ];

  test("fallback parsing of PublicKeyBundle", () async {
    // The contact topic is supposed to contain `ContactBundle` messages.
    // But sometimes it contains `PublicKeyBundle` messages that we need to handle.
    var envelopeSurprise = xmtp.Envelope(
      // This is a serialized PublicKeyBundle (instead of a ContactBundle)
      message: serializedPublicKeyBundle,
    );
    var envelopeExpected = xmtp.Envelope(
      // This is what is _should_ have contained
      message: xmtp.ContactBundle(
        v1: xmtp.ContactBundleV1(
            keyBundle: xmtp.PublicKeyBundle.fromBuffer(
          serializedPublicKeyBundle,
        )),
      ).writeToBuffer(),
    ).toContactBundle();

    expect(envelopeSurprise.toContactBundle(), envelopeExpected);
  });

  test(
    skip: "manual testing only",
    "dev: inspecting contacts for particular wallets on dev network",
    () async {
      // Setup the API client.
      var api = Api.create(
        host: 'dev.xmtp.network',
        port: 5556,
        isSecure: true,
      );
      var contacts = ContactManager(api);
      for (var address in [
        "0x359B0ceb2daBcBB6588645de3B480c8203aa5b76", // dmccartney.eth
        "0xf0EA7663233F99D0c12370671abBb6Cca980a490", // saulmc.eth
        "0x66942eC8b0A6d0cff51AEA9C7fd00494556E705F", // anoopr.eth
      ]) {
        var cs = await contacts.getUserContacts(address);
        debugPrint("$address has ${cs.length} published contacts");
        for (var i = 0; i < cs.length; ++i) {
          var c = cs[i];
          var wallet = c.wallet.hexEip55;
          var identity = c.identity.hexEip55;
          var pre = c.hasPre ? c.pre.hexEip55 : "(none)";
          debugPrint("[$i] ${c.whichVersion()}: wallet $wallet");
          debugPrint(" -> identity $identity");
          debugPrint("  -> pre $pre");
          expect(c.wallet.hexEip55, address);
        }
      }
    },
  );

  test(
    skip: skipUnlessTestServerEnabled,
    "contact creation / loading",
    () async {
      // Setup the API client.
      var api = createTestServerApi();
      var contacts = ContactManager(api);
      var alice = await EthPrivateKey.createRandom(Random.secure()).asSigner();

      // First lookup if she has a contact (i.e. if she has an account)
      var stored = await contacts.getUserContacts(alice.address.hexEip55);
      expect(stored.length, 0); // nope, no account

      // So we create an identity and authenticate
      var keys = await AuthManager(alice.address, api)
          .authenticateWithCredentials(alice);

      // And then we save the contact for that new identity.
      await contacts.saveContact(keys);

      // Now when we lookup alice again, she should have
      // both a v1 and a v2 contact.
      stored = await contacts.getUserContacts(alice.address.hexEip55);
      expect(stored.length, 2);
      var storedV1 = await contacts.getUserContactV1(alice.address.hexEip55);
      var storedV2 = await contacts.getUserContactV2(alice.address.hexEip55);
      expect(storedV1.wallet, alice.address);
      expect(storedV1.whichVersion(), xmtp.ContactBundle_Version.v1);
      expect(storedV2.wallet, alice.address);
      expect(storedV2.whichVersion(), xmtp.ContactBundle_Version.v2);
      // Note: there's a difference here between the contact and auth token.
      //       The go backend expects auth tokens signed with `ecdsaCompact`.
      //       The js-lib expects contacts signed with `walletEcdsaCompact`.
      // TODO: teach both ^ to accept either.
      // For now this is what the js-lib expects inside the contact.
      expect(
        storedV1.v1.keyBundle.identityKey
            .recoverWalletSignerPublicKey()
            .toEthereumAddress(),
        alice.address,
      );
    },
  );
}
