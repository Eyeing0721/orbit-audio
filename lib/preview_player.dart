import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'engine_service.dart';

/// Keep Windows playback outside Flutter's platform thread and native DLLs.
class PreviewPlayer {
  final EngineService engine;
  final _position = StreamController<Duration>.broadcast();
  final _complete = StreamController<void>.broadcast();
  Stream<Duration> get onPositionChanged => _position.stream;
  Stream<void> get onPlayerComplete => _complete.stream;
  Process? _process;
  Timer? _timer;
  bool _disposed = false;
  PreviewPlayer(this.engine);
  Future<void> play(String path) async {
    await stop();
    final proc = await Process.start(
      engine.python,
      ['-u', '${engine.root}/backend/player.py', path],
      workingDirectory: engine.root,
      environment: {'PYTHONIOENCODING': 'utf-8'},
    );
    _process = proc;
    final started = Completer<void>();
    final errors = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen(errors.write);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      try {
        final event = jsonDecode(line) as Map;
        if (event['event'] == 'playing') {
          final clock = Stopwatch()..start();
          _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
            if (!_disposed) _position.add(clock.elapsed);
          });
          if (!started.isCompleted) started.complete();
        }
        if (event['event'] == 'error') {
          errors.write(event['message']);
          if (!started.isCompleted) {
            started.completeError(Exception(event['message']));
          }
        }
      } catch (e) {
        if (!started.isCompleted) started.completeError(e);
      }
    });
    proc.exitCode.then((code) {
      if (_process != proc) return;
      _process = null;
      _timer?.cancel();
      if (!started.isCompleted) {
        started.completeError(
          Exception(errors.isEmpty ? '无法启动系统音频设备' : errors.toString()),
        );
      }
      if (!_disposed) _complete.add(null);
    });
    await started.future.timeout(const Duration(seconds: 10));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final proc = _process;
    _process = null;
    if (proc != null) {
      proc.kill();
      await proc.exitCode;
    }
  }

  void dispose() {
    _disposed = true;
    stop();
    _position.close();
    _complete.close();
  }
}
