import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:quiver/check.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import 'background_manager.dart';

/// This contains the dispatch table for all [XmtpIsolate] commands.
/// When a command is received by the isolate in the background,
/// these are invoked to hand it off to the [BackgroundManager].
Map<String, Future<Object?> Function(BackgroundManager manager, List args)>
    _commands = {
  "kill": (manager, args) => manager.stop(),
  "refreshConversations": (manager, args) => manager.refreshConversations(
        since: args[0] as DateTime?,
      ),
  "refreshMessages": (manager, args) => manager.refreshMessages(
        args[0] as List<String>,
        since: args[1] as DateTime?,
      ),
  "canMessage": (manager, args) => manager.canMessage(args[0] as String),
  "newConversation": (manager, args) => manager
      .newConversation(
        args[0] as String,
        conversationId: args[1] as String,
        metadata: args[2] as Map<String, String>,
      )
      .then((convo) => convo.topic),
  "sendMessage": (manager, args) => manager
      .sendMessage(
        args[0] as String,
        args[1] as xmtp.EncodedContent,
      )
      .then((sent) => sent.id),
};

/// When we spawn the [XmtpIsolate] this is the entrypoint (i.e. "main()").
/// It receives the UI's SendPort and the user's key bundle.
/// After it launches the XmtpManager to handle commands and
void _mainXmtpIsolate(List args) async {
  final responsePort = args[0] as SendPort;
  final keys = args[1] as xmtp.PrivateKeyBundle;
  debugPrint('starting xmtp worker for ${keys.wallet}');
  final manager = await BackgroundManager.create(keys);
  // Start listening for commands
  final ReceivePort workerPort = ReceivePort('xmtp worker');
  workerPort.listen((command) async {
    try {
      if (command is List && command.length == 3) {
        var id = command[0];
        var method = command[1];
        var args = command[2] ?? [];
        debugPrint('worker received command: $method');
        try {
          checkState(_commands.containsKey(method),
              message: "unknown command $method");
          var res = await _commands[method]!(manager, args);
          responsePort.send(["complete", id, true, res]);
        } catch (err) {
          debugPrint('worker failed to execute command: $method: $err');
          responsePort.send(["complete", id, false, null]);
        }
      } else {
        debugPrint('worker discarding malformed command: $command');
      }
    } catch (err) {
      debugPrint('error handling xmtp isolate request: $err');
    }
  });
  // Tell the UI where to send commands
  responsePort.send(["port", workerPort.sendPort]);
  manager.start();
}

/// This is the named port for the background isolate.
/// It is registered when we [XmtpIsolate.spawn] and
/// used for lookup when we [XmtpIsolate.find] and
/// removed from the registry when we [XmtpIsolate.kill].
const String _workerPortName = 'xmtp_worker';

/// This exists in the foreground to receive responses from the background.
/// It only marks pending requests as completed.
/// See also [ForegroundSession] (which handles the rest of the foreground i/o)
final _foregroundReceiver = ForegroundReceiver();

/// After [commandTimeout], all commands throw a [TimeoutException].
const _commandTimeout = Duration(seconds: 30);

/// Whenever we send a command from the foreground we increment this.
/// Among other things, this is used to uniquely identify each isolate command.
int _commandCount = 0;

/// This contains utilities to run XMTP in a background isolate.
class XmtpIsolate {
  /// After [commandTimeout], all commands throw a [TimeoutException].
  static const commandTimeout = Duration(seconds: 30);

  final SendPort sendToWorker;

  static Future<XmtpIsolate> spawn(xmtp.PrivateKeyBundle keys) async {
    var existing = find();
    if (existing != null) {
      debugPrint('using pre-existing xmtp isolate instead of spawning another');
      return existing;
    }
    debugPrint('starting xmtp isolate for ${keys.wallet}');
    // We expect the spawned isolate to first respond with the port it will
    // listen to for incoming commands. So we wait for that and register
    // it as the [sendToWorker] named port.

    _foregroundReceiver.listenForResponses();
    await Isolate.spawn(
        _mainXmtpIsolate, [_foregroundReceiver.port.sendPort, keys]);
    var sendToWorker = await _foregroundReceiver.listeningForPort.future
        .timeout(commandTimeout);
    return XmtpIsolate.fromPort(sendToWorker);
  }

  /// Returns the isolate if it has been started
  static XmtpIsolate? find() {
    var alreadyStarted = IsolateNameServer.lookupPortByName(_workerPortName);
    if (alreadyStarted == null) {
      debugPrint('unable to find pre-existing xmtp isolate');
      return null;
    }
    debugPrint('found pre-existing xmtp isolate');
    return XmtpIsolate.fromPort(alreadyStarted);
  }

  /// Throws if it has not been started.
  static XmtpIsolate get() => find()!;

  static Future<bool> kill() async {
    debugPrint('killing xmtp isolate');
    var existing = find();
    if (existing == null) {
      debugPrint('unable to find a pre-existing xmtp isolate to kill');
      return false;
    }
    IsolateNameServer.removePortNameMapping(_workerPortName);
    await existing.command("kill");
    return true;
  }

  XmtpIsolate.fromPort(this.sendToWorker);

  Future<T> command<T>(String method, {List args = const []}) async {
    var id = "${_commandCount++}-$method";
    debugPrint('sending command: $id');
    var result = _foregroundReceiver.waitForIdentifiedResult<T>(id);
    sendToWorker.send([id, method, args]);
    return result.timeout(commandTimeout);
  }
}

/// This tracks pending commands in the foreground isolate.
/// When one completes, this marks the corresponding [Future] as done.
/// It handles different types of messages from the background:
///  - "port": which tells the foreground where to send commands
///  - "complete": which marks a prior command as completed
class ForegroundReceiver {
  final port = ReceivePort('xmtp isolate connect');
  final Completer<SendPort> listeningForPort = Completer();
  final Map<String, Completer<Object?>> pending = {};
  bool isListening = false;

  /// This returns a [Future] that will resolve when we eventually
  /// receive a "complete" message for the corresponding [id]
  /// from the background isolate.
  ///
  /// If no "complete" is received within [_commandTimeout] then
  /// the returned [Future] will fail with a [TimeoutException].
  Future<T> waitForIdentifiedResult<T>(String id) {
    Completer<T> completer = (pending[id] = Completer<T>());
    return completer.future.timeout(_commandTimeout)
      ..whenComplete(() => pending.remove(id));
  }

  /// This listens for messages from the background isolate.
  /// It knows how to [_handlePort] when the background shares its send port.
  /// It also knows how to [_handleCompletion] messages when the background
  /// isolate is indicating that it has completed an identified command.
  void listenForResponses() {
    if (isListening) {
      debugPrint('xmtp foreground already listening for command responses');
      return;
    }
    debugPrint('xmtp foreground started listening for command responses');
    isListening = true;
    port.listen((res) {
      try {
        if (res is List && res.isNotEmpty) {
          debugPrint('UI received response: $res');
          var type = res[0];
          if (type == "port") {
            _handlePort(res[1] as SendPort);
          } else if (type == "complete") {
            _handleCompletion(
                res[1] as String, res[2] as bool, res[3] as Object?);
          } else {
            debugPrint('unexpected response: $res');
          }
        } else {
          debugPrint('malformed response: $res');
        }
      } catch (err) {
        debugPrint('error handling xmtp isolate response: $err');
      }
    });
  }

  /// This registers the worker's port and notifies anyone awaiting it.
  void _handlePort(SendPort workerPort) {
    checkState(!listeningForPort.isCompleted, message: "already handled port");
    IsolateNameServer.registerPortWithName(workerPort, _workerPortName);
    debugPrint('registered xmtp isolate at $_workerPortName');
    listeningForPort.complete(workerPort);
  }

  /// This marks the [pending] command as completed.
  void _handleCompletion(String id, bool success, Object? result) {
    if (!pending.containsKey(id)) {
      debugPrint('unexpected pending command completion: $id');
    }
    if (success) {
      pending[id]?.complete(result);
    } else {
      pending[id]?.completeError('command failed');
    }
    pending.remove(id);
  }
}
