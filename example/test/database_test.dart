import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/database/database.dart' as db;

import 'test_data.dart';

void main() {
  late db.Database database;
  setUp(() async {
    database = db.Database(NativeDatabase.memory());
  });
  tearDown(() async {
    await database.close();
  });
  test('watching and saving conversations', () async {
    // First we start watching the conversations list and
    // record each emitted update to the listings that we get
    var emitted = [];
    var watching = database
        .selectConversations()
        .watch()
        .listen((list) => emitted.add(list.map((c) => c.topic).toList()));

    // Now pretend that we update listings twice.
    await database.saveConversations([convoAandB]);
    await delayMs(100);
    await database.saveConversations([convoAandC]);
    await delayMs(100);

    // Then we should have captured 3 listings
    expect(emitted.length, 3);
    // First it should have emitted the empty list
    expect(emitted[0], []);
    // Then the first and later the second update.
    expect(emitted[1], [convoAandB.topic]);
    expect(emitted[2], [convoAandB.topic, convoAandC.topic]);
    await watching.cancel();
  });

  test('watching and saving messages', () async {
    // First we start watching the conversations list and
    // record each emitted update to the listings that we get
    var emitted = [];
    var watching = database
        .selectMessages(convoAandB.topic)
        .watch()
        .listen((list) => emitted.add(list.map((msg) => msg.id).toList()));

    // Now pretend that we update listings twice.
    await database.saveMessages([messageAtoB]);
    await delayMs(100);
    await database.saveMessages([messageBtoA]);
    await delayMs(100);

    // Then we should have captured 3 listings
    expect(emitted.length, 3);
    // First it should have emitted the empty list
    expect(emitted[0], []);
    // Then the first and later the second update.
    expect(emitted[1], [messageAtoB.id]);
    expect(emitted[2], [messageBtoA.id, messageAtoB.id]);
    await watching.cancel();
  });
}

// Helpers
delayMs(ms) => Future.delayed(Duration(milliseconds: ms));
