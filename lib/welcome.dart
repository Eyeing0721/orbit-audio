import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'studio_style.dart';

class OrbitSplash extends StatefulWidget {
  final VoidCallback onFinished;
  const OrbitSplash({super.key, required this.onFinished});
  @override
  State<OrbitSplash> createState() => _OrbitSplashState();
}

class _OrbitSplashState extends State<OrbitSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation;
  bool finished = false, started = false;
  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) finish();
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) finish();
      });
    } else {
      animation.forward();
    }
  }

  void finish() {
    if (finished) return;
    finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Stack(
        children: [
          Center(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(animation.value);
                return Opacity(
                  opacity: (t * 3).clamp(0, 1),
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - t)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 290,
                          height: 200,
                          child: CustomPaint(painter: _OrbitMark(t)),
                        ),
                        const Text(
                          'ORBIT',
                          style: TextStyle(
                            fontFamily: 'Bahnschrift',
                            fontSize: 40,
                            letterSpacing: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '让声音，有自己的位置。',
                          style: TextStyle(
                            color: muted,
                            fontSize: 14,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 34),
                        const Text(
                          'SPATIAL AUDIO STUDIO',
                          style: TextStyle(
                            color: Color(0xFF798496),
                            fontSize: 10,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 24,
            right: 28,
            child: TextButton(onPressed: finish, child: const Text('跳过开场')),
          ),
          const Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '本地创作 · 无需付费插件',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrbitMark extends CustomPainter {
  final double progress;
  _OrbitMark(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((i - 1) * .62 + (1 - progress) * .24);
      final rect = Rect.fromCenter(center: Offset.zero, width: 230, height: 84);
      canvas.drawArc(
        rect,
        -.3,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = accent.withValues(alpha: .16 + i * .09)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      final angle = i * 2.3 + progress * .45;
      canvas.drawCircle(
        Offset(math.cos(angle) * 115, math.sin(angle) * 42),
        4,
        Paint()..color = accent.withValues(alpha: progress),
      );
      canvas.restore();
    }
    canvas.drawCircle(center, 29, Paint()..color = const Color(0xFF304772));
    for (var i = 0; i < 7; i++) {
      final height = (5 + 18 * math.sin((i + 1) * math.pi / 8)) * progress;
      canvas.drawLine(
        center + Offset((i - 3) * 5.0, -height / 2),
        center + Offset((i - 3) * 5.0, height / 2),
        Paint()
          ..color = accent
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitMark old) => old.progress != progress;
}

class OrbitOnboarding extends StatefulWidget {
  final Future<void> Function() onFinished;
  final bool revisiting;
  const OrbitOnboarding({
    super.key,
    required this.onFinished,
    this.revisiting = false,
  });
  @override
  State<OrbitOnboarding> createState() => _OrbitOnboardingState();
}

class _OrbitOnboardingState extends State<OrbitOnboarding> {
  int page = 0;
  bool finishing = false;
  static const steps = [
    (
      title: '先把声音，带进来。',
      subtitle: '01 / IMPORT & SEPARATE',
      description: '导入一首歌，或已经准备好的分轨。\n选择需要的人声、鼓组、贝斯等部件，\n在本机完成 AI 拆分。',
      hint: '首次拆分会下载模型。音频不会上传到云端。',
      icon: Icons.audio_file_outlined,
    ),
    (
      title: '像摆放对象一样，编排声音。',
      subtitle: '02 / PLACE & ANIMATE',
      description:
          '左键选择声音，按 G 移动对象。\n把播放头移到目标时间，按 I 插入关键帧，\n让人声从远处走近，或让雨幕悬在上方。',
      hint: 'X 左右 · Y 前后 · Z 高度。中键旋转，Shift+中键平移。',
      icon: Icons.view_in_ar_outlined,
    ),
    (
      title: '把空间感，变成听得见的作品。',
      subtitle: '03 / SHAPE & RENDER',
      description:
          '为每个对象加入混响、回声和失真。\n用耳机试听，再导出 WAV、FLAC 或 MP3。\n从一个干净的空工程开始，不预载示例。',
      hint: '试听为最多 20 秒预渲染；输出是双耳空间音频，不是 Atmos。',
      icon: Icons.spatial_audio_outlined,
    ),
  ];
  Future<void> finish() async {
    if (finishing) return;
    setState(() => finishing = true);
    try {
      await widget.onFinished();
    } finally {
      if (mounted) setState(() => finishing = false);
    }
  }

  void next() {
    if (finishing) return;
    if (page < 2) {
      setState(() => page++);
    } else {
      finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = steps[page];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): next,
        const SingleActivator(LogicalKeyboardKey.enter): next,
        const SingleActivator(LogicalKeyboardKey.escape): finish,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (page > 0 && !finishing) setState(() => page--);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final compact = bounds.maxHeight < 730;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: bounds.maxWidth < 1100 ? 36 : 64,
                    vertical: compact ? 24 : 40,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF304772),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.spatial_audio_off_outlined,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            'ORBIT',
                            style: TextStyle(
                              fontFamily: 'Bahnschrift',
                              fontSize: 22,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            widget.revisiting ? '快速入门' : '欢迎来到你的声音工作室',
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 11,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 32),
                                child: AnimatedSwitcher(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 220),
                                  child: Column(
                                    key: ValueKey(page),
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        step.subtitle,
                                        style: const TextStyle(
                                          color: accent,
                                          fontSize: 11,
                                          letterSpacing: 1.7,
                                        ),
                                      ),
                                      SizedBox(height: compact ? 16 : 24),
                                      Text(
                                        step.title,
                                        style: TextStyle(
                                          fontSize: compact ? 29 : 36,
                                          height: 1.4,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -.6,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Text(
                                        step.description,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: muted,
                                          height: 2,
                                        ),
                                      ),
                                      SizedBox(height: compact ? 20 : 30),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 16,
                                            color: accent,
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Text(
                                              step.hint,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: muted,
                                                height: 1.8,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 10,
                              child: AspectRatio(
                                aspectRatio: 1.15,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: panel,
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            step.icon,
                                            color: accent,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            ['声音对象', '空间与关键帧', '音效与输出'][page],
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: white,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Expanded(
                                        child: CustomPaint(
                                          painter: _GuideDiagram(page),
                                          size: Size.infinite,
                                        ),
                                      ),
                                      Text(
                                        [
                                          '导入 → 选择部件 → 独立对象',
                                          '摆放位置 → 插入 K 帧 → 形成轨迹',
                                          '塑造声音 → 耳机试听 → 无损导出',
                                        ][page],
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: finishing ? null : finish,
                            child: Text(widget.revisiting ? '返回工程' : '跳过引导'),
                          ),
                          const Spacer(),
                          ...List.generate(
                            3,
                            (i) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                width: i == page ? 28 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: i == page ? accent : line,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (page > 0)
                            TextButton(
                              onPressed: finishing
                                  ? null
                                  : () => setState(() => page--),
                              child: const Text('上一步'),
                            ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: finishing ? null : next,
                            icon: Icon(
                              page == 2
                                  ? Icons.arrow_forward
                                  : Icons.chevron_right,
                              size: 18,
                            ),
                            label: Text(
                              finishing
                                  ? '准备中…'
                                  : page == 2
                                  ? (widget.revisiting ? '返回工程' : '进入空工程')
                                  : '下一步',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideDiagram extends CustomPainter {
  final int page;
  _GuideDiagram(this.page);
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    if (page == 0) {
      for (var row = 0; row < 4; row++) {
        final y = center.dy - 63 + row * 42;
        final color = [
          accent,
          const Color(0xFF9CD2CA),
          const Color(0xFFD5A477),
          const Color(0xFFAA9CC7),
        ][row];
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(8, y - 13, s.width - 16, 30),
            const Radius.circular(8),
          ),
          Paint()..color = color.withValues(alpha: .10),
        );
        for (var i = 0; i < 44; i++) {
          final x = 22 + i * (s.width - 44) / 44,
              h = 3 + 12 * (math.sin(i * .72 + row) * math.sin(i * .27)).abs();
          c.drawLine(
            Offset(x, y - h / 2),
            Offset(x, y + h / 2),
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    } else if (page == 1) {
      for (final radius in [.22, .37, .49]) {
        c.drawOval(
          Rect.fromCenter(
            center: center,
            width: s.width * radius * 2,
            height: s.width * radius,
          ),
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke,
        );
      }
      c.drawCircle(center, 16, Paint()..color = const Color(0xFF364253));
      final start = center + Offset(-s.width * .32, -s.height * .23),
          end = center + Offset(s.width * .2, -s.height * .08);
      c.drawLine(
        start,
        end,
        Paint()
          ..color = accent.withValues(alpha: .6)
          ..strokeWidth = 2,
      );
      for (var i = 0; i < 3; i++) {
        final p = Offset.lerp(start, end, i / 2)!;
        c.drawCircle(
          p,
          i == 2 ? 12 : 5,
          Paint()..color = i == 2 ? accent : const Color(0xFF617BA4),
        );
      }
      final y = s.height - 24;
      c.drawLine(
        Offset(10, y),
        Offset(s.width - 10, y),
        Paint()
          ..color = line
          ..strokeWidth = 2,
      );
      for (var i = 0; i < 3; i++) {
        final x = 20 + (s.width - 40) * i / 2;
        c.save();
        c.translate(x, y);
        c.rotate(math.pi / 4);
        c.drawRect(const Rect.fromLTWH(-4, -4, 8, 8), Paint()..color = accent);
        c.restore();
      }
    } else {
      for (var i = 0; i < 3; i++) {
        final y = center.dy - 58 + i * 54,
            x = 26 + (s.width - 52) * [.66, .4, .22][i];
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(20, y - 4, s.width - 40, 8),
            const Radius.circular(4),
          ),
          Paint()..color = line,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(20, y - 4, x - 20, 8),
            const Radius.circular(4),
          ),
          Paint()..color = accent,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 4, height: 24),
            const Radius.circular(2),
          ),
          Paint()..color = accent,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GuideDiagram old) => old.page != page;
}
