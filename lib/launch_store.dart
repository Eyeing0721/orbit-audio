import 'dart:convert';
import 'dart:io';

class LaunchStore {
  final String directory;
  LaunchStore({String? directory})
    : directory =
          directory ??
          '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}/OrbitAudio';

  File get file => File('$directory/first_run.json');

  Future<bool> isComplete() async {
    if (!await file.exists()) return false;
    try {
      final state = jsonDecode(await file.readAsString());
      return state is Map && state['onboardingComplete'] == true;
    } on FormatException {
      return false;
    }
  }

  Future<void> complete() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'onboardingComplete': true,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }
}
