import 'package:drift/drift.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import '../codecs.dart';
import 'adapters.dart';
import 'isolate.dart';

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
/// of this database using a local database.
@DriftDatabase(
  tables: [Conversations, Messages],
  include: {'database.performance.drift'},
)
class Database extends _$Database {
  Database(QueryExecutor executor) : super(executor);

  Database.connect()
      : this(DatabaseConnection.delayed(connectToDatabase('app.db')));

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

  /// Select the most recently created conversation.
  SingleOrNullSelectable<xmtp.Conversation> selectLastConversation() =>
      (conversations.select()
            ..orderBy([
              (c) =>
                  OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(1))
          .map((c) => c.toXmtp());

  /// List all conversations.
  MultiSelectable<xmtp.Conversation> selectConversations() =>
      (conversations.select()
            ..orderBy([
              (c) =>
                  OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)
            ]))
          .map((convo) => convo.toXmtp());

  /// List conversations with no messages yet.
  MultiSelectable<xmtp.Conversation> selectEmptyConversations() {
    // TODO: perf tune (consider just writing the SQL)
    return (conversations.select()
          ..where((c) => notExistsQuery(
              messages.select()..where((msg) => msg.topic.equalsExp(c.topic)))))
        .map((convo) => convo.toXmtp());
  }

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
          .asyncMap((msg) async => msg.toXmtp(codecs));

  /// Select the last message in the conversation.
  SingleOrNullSelectable<xmtp.DecodedMessage> selectLastMessage(String topic) =>
      (messages.select()
            ..where((msg) => msg.topic.equals(topic))
            ..orderBy([
              (msg) => OrderingTerm(
                    expression: msg.sentAt,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(1))
          .asyncMap((msg) async => msg.toXmtp(codecs));

  SingleOrNullSelectable<DateTime?> selectLastReceivedSentAt() =>
      (messages.selectOnly()..addColumns([messages.sentAt.max()]))
          .map((res) => res.read(messages.sentAt.max()))
          .map((value) => value == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(value));

  /// Delete all tables
  Future<void> clear() async =>
      Future.wait(allTables.map((t) => delete(t).go()));
}
