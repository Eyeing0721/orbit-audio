import 'package:flutter/material.dart';

import 'launch_store.dart';
import 'studio.dart';
import 'studio_controller.dart';
import 'welcome.dart';

enum LaunchPhase { loading, splash, onboarding, workspace }

class StartupGate extends StatefulWidget {
  final LaunchStore? store;
  final StudioController? controller;
  final bool initializeEngine;
  const StartupGate({
    super.key,
    this.store,
    this.controller,
    this.initializeEngine = true,
  });
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final LaunchStore store;
  LaunchPhase phase = LaunchPhase.loading;
  bool firstLaunch = true;
  @override
  void initState() {
    super.initState();
    store = widget.store ?? LaunchStore();
    load();
  }

  Future<void> load() async {
    var complete = false;
    try {
      complete = await store.isComplete();
    } catch (_) {
      /* Keep onboarding usable if preferences cannot be read. */
    }
    if (!mounted) return;
    setState(() {
      firstLaunch = !complete;
      phase = complete ? LaunchPhase.workspace : LaunchPhase.splash;
    });
  }

  Future<void> finish() async {
    String? warning;
    try {
      await store.complete();
    } catch (_) {
      warning = '无法记住引导完成状态，下次启动可能再次显示。工程仍可正常使用。';
    }
    if (!mounted) return;
    setState(() => phase = LaunchPhase.workspace);
    if (warning != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(warning!)));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => switch (phase) {
    LaunchPhase.loading => const Scaffold(
      body: Center(
        child: Icon(Icons.spatial_audio_off_outlined, color: accent, size: 36),
      ),
    ),
    LaunchPhase.splash => OrbitSplash(
      onFinished: () => setState(() => phase = LaunchPhase.onboarding),
    ),
    LaunchPhase.onboarding => OrbitOnboarding(onFinished: finish),
    LaunchPhase.workspace => Studio(
      controller: widget.controller,
      initializeEngine: widget.initializeEngine,
      restoreAutosave: !firstLaunch,
    ),
  };
}
