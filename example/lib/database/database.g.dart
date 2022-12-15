// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String topic;
  final int version;
  final int sentAt;
  final String sender;
  final Uint8List encoded;
  const Message(
      {required this.id,
      required this.topic,
      required this.version,
      required this.sentAt,
      required this.sender,
      required this.encoded});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['topic'] = Variable<String>(topic);
    map['version'] = Variable<int>(version);
    map['sent_at'] = Variable<int>(sentAt);
    map['sender'] = Variable<String>(sender);
    map['encoded'] = Variable<Uint8List>(encoded);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      topic: Value(topic),
      version: Value(version),
      sentAt: Value(sentAt),
      sender: Value(sender),
      encoded: Value(encoded),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      topic: serializer.fromJson<String>(json['topic']),
      version: serializer.fromJson<int>(json['version']),
      sentAt: serializer.fromJson<int>(json['sentAt']),
      sender: serializer.fromJson<String>(json['sender']),
      encoded: serializer.fromJson<Uint8List>(json['encoded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'topic': serializer.toJson<String>(topic),
      'version': serializer.toJson<int>(version),
      'sentAt': serializer.toJson<int>(sentAt),
      'sender': serializer.toJson<String>(sender),
      'encoded': serializer.toJson<Uint8List>(encoded),
    };
  }

  Message copyWith(
          {String? id,
          String? topic,
          int? version,
          int? sentAt,
          String? sender,
          Uint8List? encoded}) =>
      Message(
        id: id ?? this.id,
        topic: topic ?? this.topic,
        version: version ?? this.version,
        sentAt: sentAt ?? this.sentAt,
        sender: sender ?? this.sender,
        encoded: encoded ?? this.encoded,
      );
  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('topic: $topic, ')
          ..write('version: $version, ')
          ..write('sentAt: $sentAt, ')
          ..write('sender: $sender, ')
          ..write('encoded: $encoded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, topic, version, sentAt, sender, $driftBlobEquality.hash(encoded));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.topic == this.topic &&
          other.version == this.version &&
          other.sentAt == this.sentAt &&
          other.sender == this.sender &&
          $driftBlobEquality.equals(other.encoded, this.encoded));
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> topic;
  final Value<int> version;
  final Value<int> sentAt;
  final Value<String> sender;
  final Value<Uint8List> encoded;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.topic = const Value.absent(),
    this.version = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.sender = const Value.absent(),
    this.encoded = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String topic,
    required int version,
    required int sentAt,
    required String sender,
    required Uint8List encoded,
  })  : id = Value(id),
        topic = Value(topic),
        version = Value(version),
        sentAt = Value(sentAt),
        sender = Value(sender),
        encoded = Value(encoded);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? topic,
    Expression<int>? version,
    Expression<int>? sentAt,
    Expression<String>? sender,
    Expression<Uint8List>? encoded,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (topic != null) 'topic': topic,
      if (version != null) 'version': version,
      if (sentAt != null) 'sent_at': sentAt,
      if (sender != null) 'sender': sender,
      if (encoded != null) 'encoded': encoded,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? topic,
      Value<int>? version,
      Value<int>? sentAt,
      Value<String>? sender,
      Value<Uint8List>? encoded}) {
    return MessagesCompanion(
      id: id ?? this.id,
      topic: topic ?? this.topic,
      version: version ?? this.version,
      sentAt: sentAt ?? this.sentAt,
      sender: sender ?? this.sender,
      encoded: encoded ?? this.encoded,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<int>(sentAt.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (encoded.present) {
      map['encoded'] = Variable<Uint8List>(encoded.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('topic: $topic, ')
          ..write('version: $version, ')
          ..write('sentAt: $sentAt, ')
          ..write('sender: $sender, ')
          ..write('encoded: $encoded')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<int> sentAt = GeneratedColumn<int>(
      'sent_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
      'sender', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _encodedMeta =
      const VerificationMeta('encoded');
  @override
  late final GeneratedColumn<Uint8List> encoded = GeneratedColumn<Uint8List>(
      'encoded', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, topic, version, sentAt, sender, encoded];
  @override
  String get aliasedName => _alias ?? 'messages';
  @override
  String get actualTableName => 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(_sentAtMeta,
          sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta));
    } else if (isInserting) {
      context.missing(_sentAtMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(_senderMeta,
          sender.isAcceptableOrUnknown(data['sender']!, _senderMeta));
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('encoded')) {
      context.handle(_encodedMeta,
          encoded.isAcceptableOrUnknown(data['encoded']!, _encodedMeta));
    } else if (isInserting) {
      context.missing(_encodedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      sentAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sent_at'])!,
      sender: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender'])!,
      encoded: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}encoded'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String topic;
  final int version;
  final int createdAt;
  final Uint8List invite;
  final String me;
  final String peer;
  final int lastOpenedAt;
  const Conversation(
      {required this.topic,
      required this.version,
      required this.createdAt,
      required this.invite,
      required this.me,
      required this.peer,
      required this.lastOpenedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['topic'] = Variable<String>(topic);
    map['version'] = Variable<int>(version);
    map['created_at'] = Variable<int>(createdAt);
    map['invite'] = Variable<Uint8List>(invite);
    map['me'] = Variable<String>(me);
    map['peer'] = Variable<String>(peer);
    map['last_opened_at'] = Variable<int>(lastOpenedAt);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      topic: Value(topic),
      version: Value(version),
      createdAt: Value(createdAt),
      invite: Value(invite),
      me: Value(me),
      peer: Value(peer),
      lastOpenedAt: Value(lastOpenedAt),
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      topic: serializer.fromJson<String>(json['topic']),
      version: serializer.fromJson<int>(json['version']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      invite: serializer.fromJson<Uint8List>(json['invite']),
      me: serializer.fromJson<String>(json['me']),
      peer: serializer.fromJson<String>(json['peer']),
      lastOpenedAt: serializer.fromJson<int>(json['lastOpenedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'topic': serializer.toJson<String>(topic),
      'version': serializer.toJson<int>(version),
      'createdAt': serializer.toJson<int>(createdAt),
      'invite': serializer.toJson<Uint8List>(invite),
      'me': serializer.toJson<String>(me),
      'peer': serializer.toJson<String>(peer),
      'lastOpenedAt': serializer.toJson<int>(lastOpenedAt),
    };
  }

  Conversation copyWith(
          {String? topic,
          int? version,
          int? createdAt,
          Uint8List? invite,
          String? me,
          String? peer,
          int? lastOpenedAt}) =>
      Conversation(
        topic: topic ?? this.topic,
        version: version ?? this.version,
        createdAt: createdAt ?? this.createdAt,
        invite: invite ?? this.invite,
        me: me ?? this.me,
        peer: peer ?? this.peer,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('topic: $topic, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('invite: $invite, ')
          ..write('me: $me, ')
          ..write('peer: $peer, ')
          ..write('lastOpenedAt: $lastOpenedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(topic, version, createdAt,
      $driftBlobEquality.hash(invite), me, peer, lastOpenedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.topic == this.topic &&
          other.version == this.version &&
          other.createdAt == this.createdAt &&
          $driftBlobEquality.equals(other.invite, this.invite) &&
          other.me == this.me &&
          other.peer == this.peer &&
          other.lastOpenedAt == this.lastOpenedAt);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> topic;
  final Value<int> version;
  final Value<int> createdAt;
  final Value<Uint8List> invite;
  final Value<String> me;
  final Value<String> peer;
  final Value<int> lastOpenedAt;
  const ConversationsCompanion({
    this.topic = const Value.absent(),
    this.version = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.invite = const Value.absent(),
    this.me = const Value.absent(),
    this.peer = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String topic,
    required int version,
    required int createdAt,
    required Uint8List invite,
    required String me,
    required String peer,
    required int lastOpenedAt,
  })  : topic = Value(topic),
        version = Value(version),
        createdAt = Value(createdAt),
        invite = Value(invite),
        me = Value(me),
        peer = Value(peer),
        lastOpenedAt = Value(lastOpenedAt);
  static Insertable<Conversation> custom({
    Expression<String>? topic,
    Expression<int>? version,
    Expression<int>? createdAt,
    Expression<Uint8List>? invite,
    Expression<String>? me,
    Expression<String>? peer,
    Expression<int>? lastOpenedAt,
  }) {
    return RawValuesInsertable({
      if (topic != null) 'topic': topic,
      if (version != null) 'version': version,
      if (createdAt != null) 'created_at': createdAt,
      if (invite != null) 'invite': invite,
      if (me != null) 'me': me,
      if (peer != null) 'peer': peer,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
    });
  }

  ConversationsCompanion copyWith(
      {Value<String>? topic,
      Value<int>? version,
      Value<int>? createdAt,
      Value<Uint8List>? invite,
      Value<String>? me,
      Value<String>? peer,
      Value<int>? lastOpenedAt}) {
    return ConversationsCompanion(
      topic: topic ?? this.topic,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      invite: invite ?? this.invite,
      me: me ?? this.me,
      peer: peer ?? this.peer,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (topic.present) {
      map['topic'] = Variable<String>(topic.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (invite.present) {
      map['invite'] = Variable<Uint8List>(invite.value);
    }
    if (me.present) {
      map['me'] = Variable<String>(me.value);
    }
    if (peer.present) {
      map['peer'] = Variable<String>(peer.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<int>(lastOpenedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('topic: $topic, ')
          ..write('version: $version, ')
          ..write('createdAt: $createdAt, ')
          ..write('invite: $invite, ')
          ..write('me: $me, ')
          ..write('peer: $peer, ')
          ..write('lastOpenedAt: $lastOpenedAt')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _topicMeta = const VerificationMeta('topic');
  @override
  late final GeneratedColumn<String> topic = GeneratedColumn<String>(
      'topic', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _inviteMeta = const VerificationMeta('invite');
  @override
  late final GeneratedColumn<Uint8List> invite = GeneratedColumn<Uint8List>(
      'invite', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _meMeta = const VerificationMeta('me');
  @override
  late final GeneratedColumn<String> me = GeneratedColumn<String>(
      'me', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _peerMeta = const VerificationMeta('peer');
  @override
  late final GeneratedColumn<String> peer = GeneratedColumn<String>(
      'peer', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastOpenedAtMeta =
      const VerificationMeta('lastOpenedAt');
  @override
  late final GeneratedColumn<int> lastOpenedAt = GeneratedColumn<int>(
      'last_opened_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [topic, version, createdAt, invite, me, peer, lastOpenedAt];
  @override
  String get aliasedName => _alias ?? 'conversations';
  @override
  String get actualTableName => 'conversations';
  @override
  VerificationContext validateIntegrity(Insertable<Conversation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('topic')) {
      context.handle(
          _topicMeta, topic.isAcceptableOrUnknown(data['topic']!, _topicMeta));
    } else if (isInserting) {
      context.missing(_topicMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('invite')) {
      context.handle(_inviteMeta,
          invite.isAcceptableOrUnknown(data['invite']!, _inviteMeta));
    } else if (isInserting) {
      context.missing(_inviteMeta);
    }
    if (data.containsKey('me')) {
      context.handle(_meMeta, me.isAcceptableOrUnknown(data['me']!, _meMeta));
    } else if (isInserting) {
      context.missing(_meMeta);
    }
    if (data.containsKey('peer')) {
      context.handle(
          _peerMeta, peer.isAcceptableOrUnknown(data['peer']!, _peerMeta));
    } else if (isInserting) {
      context.missing(_peerMeta);
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
          _lastOpenedAtMeta,
          lastOpenedAt.isAcceptableOrUnknown(
              data['last_opened_at']!, _lastOpenedAtMeta));
    } else if (isInserting) {
      context.missing(_lastOpenedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {topic};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      topic: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}topic'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      invite: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}invite'])!,
      me: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}me'])!,
      peer: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}peer'])!,
      lastOpenedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_opened_at'])!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

abstract class _$Database extends GeneratedDatabase {
  _$Database(QueryExecutor e) : super(e);
  late final $MessagesTable messages = $MessagesTable(this);
  late final Index messageTopicSentAt = Index('message_topic_sent_at',
      'CREATE INDEX message_topic_sent_at ON messages (topic, sent_at)');
  late final $ConversationsTable conversations = $ConversationsTable(this);
  Selectable<int> selectTotalUnreadMessageCount() {
    return customSelect(
        'SELECT COUNT(*) AS _c0 FROM messages INNER JOIN conversations ON messages.topic = conversations.topic WHERE messages.sent_at > conversations.last_opened_at',
        variables: [],
        readsFrom: {
          messages,
          conversations,
        }).map((QueryRow row) => row.read<int>('_c0'));
  }

  Selectable<int> selectUnreadMessageCount(String topic) {
    return customSelect(
        'SELECT COUNT(*) AS _c0 FROM messages INNER JOIN conversations ON messages.topic = conversations.topic WHERE messages.sent_at > conversations.last_opened_at AND messages.topic = ?1',
        variables: [
          Variable<String>(topic)
        ],
        readsFrom: {
          messages,
          conversations,
        }).map((QueryRow row) => row.read<int>('_c0'));
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [messages, messageTopicSentAt, conversations];
}
