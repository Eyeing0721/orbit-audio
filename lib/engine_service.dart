import 'dart:async';
import 'dart:convert';
import 'dart:io';

class EngineService {
  String python = Platform.environment['ORBIT_PYTHON'] ?? 'python';
  String ffmpeg = Platform.environment['ORBIT_FFMPEG'] ?? '';
  late String root;
  Process? _process;
  final List<String> logs = [];
  EngineService() {
    final candidates = [
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}app',
    ];
    root = candidates.firstWhere(
      (d) => File('$d/backend/worker.py').existsSync(),
      orElse: () => Directory.current.path,
    );
    final localPython = '$root/runtime/Scripts/python.exe';
    if (Platform.environment['ORBIT_PYTHON'] == null &&
        File(localPython).existsSync()) {
      python = localPython;
    }
  }
  bool get busy => _process != null;
  Future<Map<String, dynamic>> run(
    Map<String, dynamic> request, {
    void Function(double, String)? onProgress,
  }) async {
    if (busy) throw Exception('音频引擎正在工作，请稍候或取消当前任务。');
    logs.clear();
    final proc = await Process.start(
      python,
      ['-u', '$root/backend/worker.py'],
      workingDirectory: root,
      environment: {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        if (ffmpeg.isNotEmpty) 'ORBIT_FFMPEG': ffmpeg,
      },
    );
    _process = proc;
    final error = StringBuffer();
    Map<String, dynamic>? result;
    String? taskError;
    final stderrDone = proc.stderr.transform(utf8.decoder).listen((s) {
      error.write(s);
      logs.add(s);
    });
    proc.stdin.writeln(jsonEncode(request));
    await proc.stdin.close();
    try {
      await for (final line
          in proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final event = jsonDecode(line) as Map<String, dynamic>;
          if (event['event'] == 'progress') {
            logs.add(event['message'] as String);
            if (logs.length > 200) logs.removeAt(0);
            onProgress?.call(
              (event['value'] as num).toDouble(),
              event['message'] as String,
            );
          }
          if (event['event'] == 'result') {
            result = Map<String, dynamic>.from(event['data'] as Map);
          }
          if (event['event'] == 'error') taskError = event['message'] as String;
        } catch (_) {
          logs.add(line);
        }
      }
      final code = await proc.exitCode;
      await stderrDone.cancel();
      if (code != 0 || result == null) {
        throw Exception(
          taskError ??
              (error.isEmpty
                  ? '任务已取消或没有返回结果。'
                  : error
                        .toString()
                        .split('\n')
                        .where((s) => s.isNotEmpty)
                        .last),
        );
      }
      return result;
    } finally {
      _process = null;
    }
  }

  Future<void> cancel() async {
    final proc = _process;
    if (proc == null) return;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${proc.pid}', '/T', '/F']);
    } else {
      proc.kill();
    }
  }
}
