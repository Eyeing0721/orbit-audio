import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import 'audio_graph.dart';
import 'studio_controller.dart';
import 'studio_slider.dart';
import 'studio_style.dart';

class NodeSocket {
  final String node;
  const NodeSocket(this.node);
}

class NodeEditor extends StatefulWidget {
  final StudioController controller;
  const NodeEditor({super.key, required this.controller});
  @override
  State<NodeEditor> createState() => NodeEditorState();
}

class NodeEditorState extends State<NodeEditor> {
  StudioController get c => widget.controller;
  final focus = FocusNode();
  final canvasKey = GlobalKey();
  double zoom = .75;
  Offset pan = const Offset(12, 12), pointer = Offset.zero;
  Size canvas = Size.zero;
  String? framed, pending;
  int framedCount = -1;
  static const nodeSize = Size(218, 142);
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  void fit() {
    final nodes = c.activeGraph?.nodes ?? [];
    if (nodes.isEmpty || canvas.isEmpty) return;
    final minX = nodes.map((n) => n.x).reduce(math.min),
        minY = nodes.map((n) => n.y).reduce(math.min);
    final maxX = nodes.map((n) => n.x).reduce(math.max) + nodeSize.width,
        maxY = nodes.map((n) => n.y).reduce(math.max) + nodeSize.height;
    zoom = math
        .min(
          (canvas.width - 35) / (maxX - minX),
          (canvas.height - 35) / (maxY - minY),
        )
        .clamp(.25, 1.1);
    pan = Offset(
      (canvas.width - (maxX - minX) * zoom) / 2 - minX * zoom,
      (canvas.height - (maxY - minY) * zoom) / 2 - minY * zoom,
    );
  }

  Offset socket(AudioNode node, {String? port}) =>
      pan +
      Offset(
            node.x + (port == null ? nodeSize.width - 8 : 8),
            node.y + 73 + (port == 'b' || port == 'key' ? 26 : 0),
          ) *
          zoom;

  void connect(String from, String to, String port) {
    c.connectNodes(from, to, port);
    setState(() => pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final object = c.selected, graph = c.activeGraph;
    if (graph == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '先选择或导入一个声音对象',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            TextButton(
              onPressed: () => c.setNodeContext(true),
              child: const Text('编辑主输出节点'),
            ),
          ],
        ),
      );
    }
    return Focus(
      focusNode: focus,
      onKeyEvent: (_, event) {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused?.widget is EditableText ||
            focused?.findAncestorStateOfType<EditableTextState>() != null) {
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.keyX) {
          c.deleteNode();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.home) {
          setState(fit);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          Container(
            height: 37,
            color: const Color(0xFF25272C),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  PopupMenuButton<bool>(
                    tooltip: '节点处理范围',
                    onSelected: c.busy ? null : c.setNodeContext,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: false,
                        enabled: object != null,
                        child: const Text('对象节点'),
                      ),
                      const PopupMenuItem(value: true, child: Text('主输出节点')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Text(
                            c.editingMasterGraph ? '主输出节点' : '对象节点',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const Icon(Icons.expand_more, size: 14),
                        ],
                      ),
                    ),
                  ),
                  Checkbox(
                    value: graph.enabled,
                    onChanged: c.busy
                        ? null
                        : (value) {
                            c.remember();
                            graph.enabled = value!;
                            c.changed();
                          },
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    graph.enabled ? '节点已启用' : '旁路全部节点',
                    style: TextStyle(
                      fontSize: 10,
                      color: graph.enabled ? accent : muted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  PopupMenuButton<String>(
                    tooltip: '添加音频节点',
                    onSelected: c.busy ? null : c.addNode,
                    itemBuilder: (_) => nodeSpecs.entries
                        .where(
                          (e) =>
                              e.key != 'input' &&
                              e.key != 'output' &&
                              (!c.editingMasterGraph ||
                                  !masterExcludedNodes.contains(e.key)),
                        )
                        .map(
                          (e) => PopupMenuItem(
                            value: e.key,
                            child: Text(
                              e.value.label,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 15),
                          SizedBox(width: 4),
                          Text('添加节点', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () {
                            c.remember();
                            if (c.editingMasterGraph) {
                              c.project.masterGraph = AudioGraph.bathroom();
                            } else {
                              object!.nodeGraph = AudioGraph.bathroom();
                            }
                            c.selectedNodeId = 'reverb';
                            c.changed();
                            framed = null;
                          },
                    child: const Text('浴室并联预设', style: TextStyle(fontSize: 10)),
                  ),
                  IconButton(
                    tooltip: '适配节点 Home',
                    onPressed: () => setState(fit),
                    icon: const Icon(Icons.fit_screen, size: 16),
                  ),
                  Text(
                    '${graph.nodes.length} NODES',
                    style: const TextStyle(
                      fontFamily: 'Bahnschrift',
                      fontSize: 9,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                canvas = bounds.biggest;
                final contextId = c.editingMasterGraph ? '_master' : object!.id;
                if (framed != contextId || framedCount != graph.nodes.length) {
                  framed = contextId;
                  framedCount = graph.nodes.length;
                  fit();
                }
                return ClipRect(
                  child: Listener(
                    onPointerDown: (_) => focus.requestFocus(),
                    onPointerMove: (event) {
                      if (event.buttons & kMiddleMouseButton != 0) {
                        setState(() => pan += event.delta);
                      }
                    },
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        setState(() {
                          final local = (event.localPosition - pan) / zoom;
                          zoom =
                              (zoom * math.exp(-event.scrollDelta.dy * .0015))
                                  .clamp(.25, 2);
                          pan = event.localPosition - local * zoom;
                        });
                      }
                    },
                    child: Stack(
                      key: canvasKey,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _NodeWires(
                              graph,
                              pan,
                              zoom,
                              c.selectedNodeId,
                              pending,
                              pointer,
                            ),
                          ),
                        ),
                        for (final node in graph.nodes)
                          Positioned(
                            left: pan.dx + node.x * zoom,
                            top: pan.dy + node.y * zoom,
                            child: Transform.scale(
                              scale: zoom,
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: nodeSize.width,
                                height: nodeSize.height,
                                child: nodeCard(node),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 12,
                          bottom: 9,
                          right: 12,
                          child: IgnorePointer(
                            child: Text(
                              graph.error ??
                                  '拖端口连线 / 点输出再点输入 · 拖标题移动 · 中键平移 · 滚轮缩放',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget nodeCard(AudioNode node) {
    final selected = c.selectedNodeId == node.id;
    return GestureDetector(
      onTap: () {
        focus.requestFocus();
        c.selectNode(node.id);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF303238),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? accent : const Color(0xFF595D66),
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 32,
              child: GestureDetector(
                key: ValueKey('node-header-${node.id}'),
                behavior: HitTestBehavior.opaque,
                onPanStart: c.busy
                    ? null
                    : (_) {
                        c.selectNode(node.id);
                        c.remember();
                      },
                onPanUpdate: c.busy
                    ? null
                    : (event) {
                        node.x = (node.x + event.delta.dx / zoom).clamp(
                          -100000,
                          100000,
                        );
                        node.y = (node.y + event.delta.dy / zoom).clamp(
                          -100000,
                          100000,
                        );
                        c.changed();
                      },
                child: Container(
                  decoration: BoxDecoration(
                    color: node.spec.color.withValues(alpha: .25),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(
                        node.type == 'mix'
                            ? Icons.merge_type
                            : Icons.graphic_eq,
                        size: 14,
                        color: node.spec.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          node.spec.label,
                          style: const TextStyle(fontSize: 12, color: white),
                        ),
                      ),
                      if (node.bypass)
                        const Text(
                          'BYPASS',
                          style: TextStyle(fontSize: 8, color: muted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              top: 42,
              child: Text(
                node.spec.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9, color: muted),
              ),
            ),
            for (final port in node.inputs)
              Positioned(
                left: 0,
                top: port == 'b' || port == 'key' ? 88 : 62,
                width: 80,
                height: 22,
                child: inputSocket(node, port),
              ),
            if (node.hasOutput)
              Positioned(
                right: 0,
                top: 62,
                width: 80,
                height: 22,
                child: outputSocket(node),
              ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 12,
              child: Text(
                node.spec.parameters.entries
                    .take(2)
                    .map(
                      (e) =>
                          '${e.value.label} ${node.value(e.key).toStringAsFixed(1)}${e.value.unit}',
                    )
                    .join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: white,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget dot(Color color) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: ink, width: 2),
    ),
  );
  Widget inputSocket(AudioNode node, String port) => DragTarget<NodeSocket>(
    onWillAcceptWithDetails: (details) =>
        !c.busy && details.data.node != node.id,
    onAcceptWithDetails: (details) => connect(details.data.node, node.id, port),
    builder: (context, incoming, rejected) => GestureDetector(
      key: ValueKey('node-in-${node.id}-$port'),
      behavior: HitTestBehavior.opaque,
      onTap: c.busy || pending == null
          ? null
          : () => connect(pending!, node.id, port),
      onSecondaryTap: c.busy ? null : () => c.disconnectNode(node.id, port),
      child: Row(
        children: [
          const SizedBox(width: 2),
          dot(incoming.isNotEmpty ? white : node.spec.color),
          const SizedBox(width: 5),
          Text(
            port == 'in' ? '音频' : port.toUpperCase(),
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ),
    ),
  );
  Widget outputSocket(AudioNode node) => Draggable<NodeSocket>(
    data: NodeSocket(node.id),
    maxSimultaneousDrags: c.busy ? 0 : 1,
    onDragStarted: () => setState(() {
      pending = node.id;
      pointer = socket(node);
    }),
    onDragUpdate: (details) {
      final box = canvasKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
        setState(() => pointer = box.globalToLocal(details.globalPosition));
      }
    },
    onDragEnd: (_) => setState(() => pending = null),
    feedback: Material(color: Colors.transparent, child: dot(node.spec.color)),
    child: GestureDetector(
      key: ValueKey('node-out-${node.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: c.busy
          ? null
          : () => setState(() {
              pending = node.id;
              pointer = socket(node) + const Offset(40, 0);
            }),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('输出', style: TextStyle(fontSize: 10, color: muted)),
          const SizedBox(width: 5),
          dot(node.spec.color),
          const SizedBox(width: 2),
        ],
      ),
    ),
  );
}

class _NodeWires extends CustomPainter {
  final AudioGraph graph;
  final Offset pan, pointer;
  final double zoom;
  final String? selected, pending;
  _NodeWires(
    this.graph,
    this.pan,
    this.zoom,
    this.selected,
    this.pending,
    this.pointer,
  );
  Offset at(AudioNode n, bool output, [String port = 'in']) =>
      pan +
      Offset(
            n.x + (output ? 210 : 8),
            n.y + 73 + (port == 'b' || port == 'key' ? 26 : 0),
          ) *
          zoom;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1C1E22),
    );
    final spacing = 28 * zoom;
    final dots = Paint()..color = const Color(0xFF34373D);
    for (var x = pan.dx % spacing; x < size.width; x += spacing) {
      for (var y = pan.dy % spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), .8, dots);
      }
    }
    void wire(Offset a, Offset b, Color color) {
      final bend = math.max(40.0, (b.dx - a.dx).abs() * .5);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx + bend, a.dy, b.dx - bend, b.dy, b.dx, b.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    for (final edge in graph.edges) {
      final a = graph.node(edge.from), b = graph.node(edge.to);
      if (a != null && b != null) {
        wire(
          at(a, true),
          at(b, false, edge.port),
          (edge.from == selected || edge.to == selected ? accent : a.spec.color)
              .withValues(alpha: graph.enabled ? .85 : .3),
        );
      }
    }
    final source = graph.node(pending);
    if (source != null) wire(at(source, true), pointer, accent);
  }

  @override
  bool shouldRepaint(covariant _NodeWires oldDelegate) => true;
}

class NodeProperties extends StatelessWidget {
  final StudioController controller;
  const NodeProperties({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller,
        node = controller.selectedNode,
        graph = controller.activeGraph;
    if (node == null || graph == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '点击节点，编辑实际音频处理参数\n输出端 → 输入端连线；输入端右键断线',
            style: TextStyle(fontSize: 11, color: muted, height: 1.9),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(17),
      children: [
        Text(
          node.spec.label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          node.spec.description,
          style: const TextStyle(fontSize: 11, height: 1.7, color: muted),
        ),
        const SizedBox(height: 14),
        if (c.editingMasterGraph)
          const Text(
            '主输出：对象双耳求和 → 主增益 → 此节点链 → 峰值保护。不会再执行 HRTF。',
            style: TextStyle(fontSize: 11, height: 1.7, color: accent),
          ),
        if (node.type == 'file' || node.type == 'convolution') ...[
          Text(
            node.assetPath.isEmpty
                ? (node.type == 'file' ? '未选择文件 · 输出静音' : '正在使用内置合成 IR')
                : node.assetPath.split(RegExp(r'[/\\]')).last,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(node.type == 'file' ? '选择输入音频' : '选择 IR 文件'),
            onPressed: c.busy
                ? null
                : () async {
                    final file = await openFile(
                      acceptedTypeGroups: [
                        const XTypeGroup(
                          label: '音频 / IR',
                          extensions: [
                            'wav',
                            'flac',
                            'aiff',
                            'mp3',
                            'm4a',
                            'm4s',
                            'ogg',
                          ],
                        ),
                      ],
                    );
                    if (file != null && !c.busy) {
                      c.remember();
                      node.assetPath = file.path;
                      c.changed();
                    }
                  },
          ),
          if (node.assetPath.isNotEmpty)
            TextButton(
              onPressed: c.busy
                  ? null
                  : () {
                      c.remember();
                      node.assetPath = '';
                      c.changed();
                    },
              child: const Text('清除文件引用'),
            ),
        ],
        if (node.type != 'input' && node.type != 'output')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('旁路此节点', style: TextStyle(fontSize: 11)),
            value: node.bypass,
            onChanged: c.busy
                ? null
                : (v) {
                    c.remember();
                    node.bypass = v;
                    c.changed();
                  },
          ),
        for (final entry in node.spec.parameters.entries) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.value.label,
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
              ),
              SizedBox(
                width: 88,
                child: TextFormField(
                  key: ValueKey(
                    '${node.id}-${entry.key}-${node.value(entry.key)}',
                  ),
                  initialValue: node.value(entry.key).toStringAsFixed(2),
                  enabled: !c.busy,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 11),
                  decoration: InputDecoration(
                    isDense: true,
                    suffixText: entry.value.unit,
                  ),
                  onFieldSubmitted: (text) {
                    final value = double.tryParse(text);
                    if (value == null || !value.isFinite) return;
                    c.remember();
                    c.updateNodeParameter(
                      entry.key,
                      value.clamp(entry.value.min, entry.value.max),
                    );
                  },
                ),
              ),
            ],
          ),
          StudioSlider(
            key: ValueKey('node-param-${entry.key}'),
            value: node
                .value(entry.key)
                .clamp(entry.value.min, entry.value.max),
            min: entry.value.min,
            max: entry.value.max,
            onChangeStart: (_) => c.remember(),
            onChanged: c.busy
                ? null
                : (v) => c.updateNodeParameter(entry.key, v),
          ),
          if (node.type == 'environment' && entry.key == 'kind')
            Text(
              ['雨声', '风声', '海浪', '粉红噪音', '白噪音'][node.value('kind').round()],
              style: const TextStyle(fontSize: 10, color: accent),
            ),
          if (node.type == 'convolution' && entry.key == 'room')
            Text(
              ['明亮浴室', '暗色房间', '延迟大厅'][node.value('room').round()],
              style: const TextStyle(fontSize: 10, color: accent),
            ),
        ],
        const SizedBox(height: 20),
        const Divider(),
        for (final port in node.inputs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              '输入 ${port.toUpperCase()}',
              style: const TextStyle(fontSize: 11),
            ),
            subtitle: Text(
              graph.edges
                      .where((e) => e.to == node.id && e.port == port)
                      .map((e) => graph.node(e.from)?.spec.label ?? '')
                      .firstOrNull ??
                  '未连接 · 静音',
              style: const TextStyle(fontSize: 10, color: muted),
            ),
            trailing: IconButton(
              tooltip: '断开输入',
              onPressed: c.busy ? null : () => c.disconnectNode(node.id, port),
              icon: const Icon(Icons.link_off, size: 16),
            ),
          ),
        if (node.type != 'input' && node.type != 'output')
          TextButton.icon(
            onPressed: c.busy ? null : c.deleteNode,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('删除节点', style: TextStyle(fontSize: 11)),
          ),
        const SizedBox(height: 20),
        Text(
          c.editingMasterGraph
              ? '主输出输入端接收已经空间化的双耳求和信号。压缩 / 均衡 / 调制等节点在此后处理，最后统一进行采样峰值保护。\n\n主输出节点参数是静态值，不与对象关联。源级频谱面板不会显示此处的处理结果。'
              : '裁剪 / 淡化 → 节点图 → 对象音效与自动化 → HRTF → 主输出\n\n可听链路包含启用的 HRTF 节点时，跳过末端对象空间化，只保留对象增益动画，避免双重 HRTF。节点参数是静态值；移动声源请使用对象位置关键帧。\n\n文件输入按工程绝对时间对齐。KEY 只检测、不发声。关联副本共享节点与剪辑。',
          style: const TextStyle(fontSize: 10, color: muted, height: 1.8),
        ),
      ],
    );
  }
}
