import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import 'adapters.dart';
import 'encryption.dart';

/// The generated code from the Table definitions.
///
/// To regenerate this code: $ flutter pub run build_runner build
part 'database.g.dart';

/// The table storing each [Conversation].
///
/// These are constructed from the [xmtp.Conversation] objects.
/// See adapters [XmtpToDbConversation] and [DbToXmtpConversation].
///
/// This [Table] definition generates some of the code in `database.g.dart`.
class Conversations extends Table {
  TextColumn get topic => text()();

  IntColumn get version => integer()();

  IntColumn get createdAt => integer()();

  BlobColumn get invite => blob()();

  TextColumn get me => text()();

  TextColumn get peer => text()();

  IntColumn get lastOpenedAt => integer()();

  @override
  Set<Column> get primaryKey => {topic};
}

/// The table storing each [Message].
///
/// These are constructed from the [xmtp.DecodedMessage] objects.
/// See adapters [XmtpToDbMessage] and [DbToXmtpMessage].
///
/// This [Table] definition generates some of the code in `database.g.dart`.
class Messages extends Table {
  TextColumn get id => text()();

  TextColumn get topic => text()();

  IntColumn get version => integer()();

  IntColumn get sentAt => integer()();

  TextColumn get sender => text()();

  BlobColumn get encoded => blob()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The local [DriftDatabase] for storing [Conversations] and [Messages].
///
/// This takes the [Table] definitions (and the explicit .drift file) to
/// generate the code in `database.g.dart`.
///
/// It exposes methods for querying the database.
///
/// And it also includes a constructor to [create] an instance
/// of this database using an encrypted local database.
/// See [getOrCreateEncryptionKey].
@DriftDatabase(
  tables: [Conversations, Messages],
  include: {'database.performance.drift'},
)
class Database extends _$Database {
  final xmtp.ContentDecoder decoder;

  Database(this.decoder, QueryExecutor executor) : super(executor);

  /// Create a local encrypted instance of the database.
  ///
  /// This creates (or opens) the database in the application
  /// documents directory using a randomly generated key for encryption.
  ///
  /// Since message content is stored as [xmtp.EncodedContent], this
  /// uses the [decoder] to get [xmtp.DecodedMessage.content] for display.
  static Database create(xmtp.ContentDecoder decoder) {
    configureSqlCipherLibraries();
    return Database(decoder, LazyDatabase(() async {
      var docs = await getApplicationDocumentsDirectory();
      var file = File(p.join(docs.path, 'db.sqlite'));
      var encryptionKey = await getOrCreateEncryptionKey();
      return NativeDatabase(
        file,
        logStatements: kDebugMode,
        setup: (db) {
          configureSqlCipherDatabase(db, encryptionKey);
        },
      );
    }));
  }

  @override
  int get schemaVersion => 1;

  /// Saves the given [conversations] to the database.
  ///
  /// When a conversation already exists the insert will be ignored.
  Future<void> saveConversations(List<xmtp.Conversation> conversations) =>
      batch((batch) => batch.insertAll(
            this.conversations,
            conversations.map((convo) => convo.toDb()),
            mode: InsertMode.insertOrIgnore,
          ));

  /// Saves the given [messages] to the database.
  ///
  /// When a message already exists the insert will be ignored.
  Future<void> saveMessages(List<xmtp.DecodedMessage> messages) =>
      batch((batch) => batch.insertAll(
            this.messages,
            messages.map((msg) => msg.toDb()),
            mode: InsertMode.insertOrIgnore,
          ));

  /// Record that we just opened the conversation.
  Future<void> updateLastOpenedAt(String topic) =>
      update(conversations).write(ConversationsCompanion(
        lastOpenedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

  /// Select the specified conversation.
  SingleOrNullSelectable<xmtp.Conversation> selectConversation(String topic) =>
      (conversations.select()..where((c) => c.topic.equals(topic)))
          .map((c) => c.toXmtp());

  /// List all conversations.
  MultiSelectable<xmtp.Conversation> selectConversations() =>
      conversations.select().map((convo) => convo.toXmtp());

  /// List messages in the conversation.
  MultiSelectable<xmtp.DecodedMessage> selectMessages(String topic) =>
      (messages.select()
            ..where((msg) => msg.topic.equals(topic))
            ..orderBy([
              (msg) => OrderingTerm(
                    expression: msg.sentAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .asyncMap((msg) async => msg.toXmtp(decoder));

  /// Delete all stored conversations and messages.
  Future<void> clear() async => Future.wait([
        delete(conversations).go(),
        delete(messages).go(),
      ]);
}
