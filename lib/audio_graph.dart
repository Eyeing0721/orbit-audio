import 'package:flutter/material.dart';

const masterExcludedNodes = {'hrtf', 'file', 'environment'};

class NodeParameter {
  final String label, unit;
  final double min, max, initial;
  const NodeParameter(
    this.label,
    this.min,
    this.max,
    this.initial, [
    this.unit = '',
  ]);
}

class NodeSpec {
  final String label, description;
  final Color color;
  final Map<String, NodeParameter> parameters;
  const NodeSpec(this.label, this.description, this.color, this.parameters);
}

const nodeSpecs = <String, NodeSpec>{
  'input': NodeSpec('音频输入', '裁剪与源级处理后的音频', Color(0xFF86AFD1), {}),
  'output': NodeSpec('对象输出', '接入对象音效与 HRTF；未连接则静音', Color(0xFF86AFD1), {}),
  'gain': NodeSpec('增益', '线性幅度调整，不自动归一化', Color(0xFF77B8AA), {
    'gain': NodeParameter('增益', -60, 24, 0, 'dB'),
  }),
  'filter': NodeSpec('高低切滤波', '二阶带通滤波', Color(0xFF77B8AA), {
    'highpass': NodeParameter('低切', 20, 20000, 40, 'Hz'),
    'lowpass': NodeParameter('高切', 200, 21000, 18000, 'Hz'),
  }),
  'eq': NodeSpec('三段均衡', '250 Hz 低架 / 1 kHz 峰值 / 4 kHz 高架', Color(0xFF77B8AA), {
    'low': NodeParameter('低频', -24, 24, 0, 'dB'),
    'mid': NodeParameter('中频', -24, 24, 0, 'dB'),
    'high': NodeParameter('高频', -24, 24, 0, 'dB'),
  }),
  'compressor': NodeSpec('压缩器', '联动声道的包络压缩，不是响度标准化', Color(0xFFC7A977), {
    'threshold': NodeParameter('阈值', -60, 0, -24, 'dB'),
    'ratio': NodeParameter('压缩比', 1, 20, 4, ':1'),
    'attack': NodeParameter('启动', 1, 200, 10, 'ms'),
    'release': NodeParameter('释放', 10, 2000, 120, 'ms'),
    'makeup': NodeParameter('补偿', -12, 24, 0, 'dB'),
  }),
  'gate': NodeSpec('噪声门', '抑制阈值以下的信号；不是 AI 降噪', Color(0xFFC7A977), {
    'threshold': NodeParameter('阈值', -90, -6, -45, 'dB'),
    'attack': NodeParameter('启动', 1, 200, 5, 'ms'),
    'release': NodeParameter('释放', 10, 2000, 120, 'ms'),
  }),
  'echo': NodeSpec('延迟回声', '最多 12 次反馈；保持输出时长', Color(0xFFA79BC3), {
    'delayMs': NodeParameter('延迟', 1, 2000, 280, 'ms'),
    'feedback': NodeParameter('反馈', 0, .85, .42),
    'wet': NodeParameter('湿声', 0, 1, .3),
  }),
  'reverb': NodeSpec('浴室混响', '瓷砖早期反射与扩散尾音', Color(0xFFA79BC3), {
    'decay': NodeParameter('衰减', .15, 8, 2.6, 's'),
    'wet': NodeParameter('湿声', 0, 1, .5),
  }),
  'distortion': NodeSpec('饱和失真', '软饱和并行混合', Color(0xFFCA9587), {
    'drive': NodeParameter('驱动', 1, 20, 4),
    'wet': NodeParameter('湿声', 0, 1, .3),
  }),
  'mix': NodeSpec('并联混合', 'A × (1−平衡) + B × 平衡', Color(0xFF8BA3C6), {
    'balance': NodeParameter('A / B 平衡', 0, 1, .5),
  }),
  'hrtf': NodeSpec('HRTF 空间化', '静态双耳定位；接入输出后不再重复对象空间化', Color(0xFF86AFD1), {
    'azimuth': NodeParameter('方位角（正值向左）', -180, 180, 0, '°'),
    'elevation': NodeParameter('仰角', -40, 90, 0, '°'),
    'distance': NodeParameter('距离', .15, 20, 1.5, 'm'),
    'spread': NodeParameter('扩展', 0, 1, .2),
  }),
  'chorus': NodeSpec('合唱', '左右错相的微小延迟调制，不让声源绕圈', Color(0xFFA79BC3), {
    'rate': NodeParameter('速率', .02, 3, .23, 'Hz'),
    'depthMs': NodeParameter('深度', 0, 10, 5, 'ms'),
    'delayMs': NodeParameter('基准延迟', 12, 40, 18, 'ms'),
    'wet': NodeParameter('湿声', 0, 1, .35),
  }),
  'microshift': NodeSpec('微移调', '左右相反的微音分移调，双读头平滑交叉', Color(0xFFA79BC3), {
    'cents': NodeParameter('左右移调幅度', 0, 50, 9, 'cent'),
    'delayMs': NodeParameter('预延迟', 1, 40, 12, 'ms'),
    'wet': NodeParameter('湿声', 0, 1, .3),
  }),
  'diffuser': NodeSpec('扩散器', '四级全通网络，打散反射而不旋转声源', Color(0xFFA79BC3), {
    'amount': NodeParameter('扩散反馈', 0, .8, .55),
    'size': NodeParameter('尺寸', .25, 2, 1),
    'wet': NodeParameter('湿声', 0, 1, .65),
  }),
  'convolution': NodeSpec(
    '卷积混响',
    '内置合成 IR，或导入最长 8 秒的单/双声道 IR',
    Color(0xFFA79BC3),
    {
      'decay': NodeParameter('内置 IR 衰减', .15, 7.5, 3.8, 's'),
      'predelayMs': NodeParameter('预延迟', 0, 250, 22, 'ms'),
      'wet': NodeParameter('湿声', 0, 1, .5),
      'room': NodeParameter('内置空间', 0, 2, 0),
      'normalize': NodeParameter('自定义 IR 能量归一化', 0, 1, 1),
    },
  ),
  'environment': NodeSpec(
    '环境音输入',
    '本地生成雨 / 风 / 海浪 / 粉红 / 白噪音',
    Color(0xFF77B8AA),
    {
      'kind': NodeParameter('环境类型', 0, 4, 0),
      'gain': NodeParameter('增益', -60, 12, -12, 'dB'),
      'seed': NodeParameter('随机种子', 0, 65535, 71),
    },
  ),
  'file': NodeSpec('文件输入', '独立文件输入，可作为侧链检测信号；保存时内嵌', Color(0xFF77B8AA), {
    'gain': NodeParameter('增益', -60, 24, 0, 'dB'),
    'offset': NodeParameter('起始偏移', 0, 86400, 0, 's'),
  }),
  'duck': NodeSpec('侧链闪避', 'KEY 只检测不发声；未接 KEY 时不压低音频', Color(0xFFC7A977), {
    'threshold': NodeParameter('阈值', -90, 0, -32, 'dB'),
    'ratio': NodeParameter('压缩比', 1, 20, 6, ':1'),
    'attack': NodeParameter('启动', 1, 200, 15, 'ms'),
    'release': NodeParameter('释放', 10, 2000, 450, 'ms'),
    'depth': NodeParameter('最大闪避', 0, 36, 12, 'dB'),
  }),
};

class AudioNode {
  String id, type;
  double x, y;
  bool bypass;
  String assetPath;
  Map<String, double> params;
  AudioNode(
    this.id,
    this.type,
    this.x,
    this.y, {
    this.bypass = false,
    this.assetPath = '',
    Map<String, double>? params,
  }) : params = params ?? {};
  NodeSpec get spec => nodeSpecs[type]!;
  double value(String field) =>
      params[field] ?? spec.parameters[field]!.initial;
  List<String> get inputs => ['input', 'environment', 'file'].contains(type)
      ? []
      : type == 'mix'
      ? ['a', 'b']
      : type == 'duck'
      ? ['in', 'key']
      : ['in'];
  bool get hasOutput => type != 'output';
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'x': x,
    'y': y,
    'bypass': bypass,
    'params': params,
    if (assetPath.isNotEmpty) 'assetPath': assetPath,
  };
  factory AudioNode.fromJson(Map<String, dynamic> json) => AudioNode(
    json['id'] as String,
    json['type'] as String,
    (json['x'] as num? ?? 0).toDouble(),
    (json['y'] as num? ?? 0).toDouble(),
    bypass: json['bypass'] == true,
    assetPath: json['assetPath'] as String? ?? '',
    params: (json['params'] as Map? ?? {}).map(
      (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
    ),
  );
}

class AudioEdge {
  final String from, to, port;
  const AudioEdge(this.from, this.to, [this.port = 'in']);
  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'port': port};
}

class AudioGraph {
  bool enabled;
  List<AudioNode> nodes;
  List<AudioEdge> edges;
  AudioGraph({
    this.enabled = false,
    List<AudioNode>? nodes,
    List<AudioEdge>? edges,
  }) : nodes =
           nodes ??
           [
             AudioNode('input', 'input', 20, 100),
             AudioNode('gain', 'gain', 300, 100),
             AudioNode('output', 'output', 580, 100),
           ],
       edges =
           edges ??
           [
             const AudioEdge('input', 'gain'),
             const AudioEdge('gain', 'output'),
           ];
  AudioNode? node(String? id) => nodes.where((n) => n.id == id).firstOrNull;
  String? get error {
    final ids = nodes.map((n) => n.id).toSet();
    if (nodes.length < 2 ||
        nodes.length > 64 ||
        ids.length != nodes.length ||
        edges.length > 128) {
      return '节点或连线数量无效';
    }
    if (nodes.where((n) => n.type == 'input').length != 1 ||
        nodes.where((n) => n.type == 'output').length != 1) {
      return '需要一个输入和一个输出';
    }
    final degrees = {for (final n in nodes) n.id: 0}, ports = <String>{};
    for (final e in edges) {
      if (node(e.from)?.hasOutput != true ||
          node(e.to)?.inputs.contains(e.port) != true) {
        return '端口类型不匹配';
      }
      if (!ports.add('${e.to}:${e.port}')) return '每个输入端口只能接一根线';
      degrees[e.to] = degrees[e.to]! + 1;
    }
    final queue = degrees.keys.where((k) => degrees[k] == 0).toList();
    var count = 0;
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      count++;
      for (final e in edges.where((e) => e.from == id)) {
        degrees[e.to] = degrees[e.to]! - 1;
        if (degrees[e.to] == 0) queue.add(e.to);
      }
    }
    return count == nodes.length ? null : '不能连接成反馈环；请使用延迟节点的反馈参数';
  }

  String? connect(String from, String to, String port) {
    final old = List<AudioEdge>.of(edges);
    edges.removeWhere((e) => e.to == to && e.port == port);
    edges.add(AudioEdge(from, to, port));
    final message = error;
    if (message != null) edges = old;
    return message;
  }

  void remove(String id) {
    if (node(id)?.type == 'input' || node(id)?.type == 'output') return;
    nodes.removeWhere((n) => n.id == id);
    edges.removeWhere((e) => e.from == id || e.to == id);
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
  };
  factory AudioGraph.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return AudioGraph();
    final graph = AudioGraph(
      enabled: json['enabled'] == true,
      nodes: (json['nodes'] as List)
          .map((n) => AudioNode.fromJson(Map<String, dynamic>.from(n)))
          .toList(),
      edges: (json['edges'] as List)
          .map(
            (e) => AudioEdge(
              e['from'] as String,
              e['to'] as String,
              e['port'] as String? ?? 'in',
            ),
          )
          .toList(),
    );
    for (final node in graph.nodes) {
      if (!nodeSpecs.containsKey(node.type) ||
          node.id.isEmpty ||
          !node.x.isFinite ||
          !node.y.isFinite ||
          node.x.abs() > 100000 ||
          node.y.abs() > 100000) {
        throw const FormatException('不支持的节点或节点位置');
      }
      if (node.assetPath.length > 4096 ||
          node.assetPath.contains('\u0000') ||
          (node.assetPath.isNotEmpty &&
              !['file', 'convolution'].contains(node.type))) {
        throw const FormatException('无效的节点素材');
      }
      for (final entry in node.params.entries) {
        final spec = node.spec.parameters[entry.key];
        if (spec == null ||
            !entry.value.isFinite ||
            entry.value < spec.min ||
            entry.value > spec.max) {
          throw const FormatException('无效的节点参数');
        }
      }
      if (node.type == 'filter' &&
          node.value('highpass') >= node.value('lowpass')) {
        throw const FormatException('滤波频率范围无效');
      }
    }
    final error = graph.error;
    if (error != null) throw FormatException(error);
    return graph;
  }
  factory AudioGraph.bathroom() => AudioGraph(
    enabled: true,
    nodes: [
      AudioNode('input', 'input', 20, 120),
      AudioNode(
        'filter',
        'filter',
        300,
        40,
        params: {'highpass': 180, 'lowpass': 9000},
      ),
      AudioNode('reverb', 'reverb', 580, 40, params: {'decay': 3.6, 'wet': 1}),
      AudioNode('gain', 'gain', 300, 280),
      AudioNode('mix', 'mix', 860, 130, params: {'balance': .6}),
      AudioNode('output', 'output', 1140, 130),
    ],
    edges: [
      const AudioEdge('input', 'filter'),
      const AudioEdge('filter', 'reverb'),
      const AudioEdge('input', 'gain'),
      const AudioEdge('gain', 'mix', 'a'),
      const AudioEdge('reverb', 'mix', 'b'),
      const AudioEdge('mix', 'output'),
    ],
  );
}
