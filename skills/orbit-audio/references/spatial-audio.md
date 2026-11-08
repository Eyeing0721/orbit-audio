# 空间、节点与调音

仅在本次创作需要时使用下列设计，不将某首歌的效果偏好推广成所有任务的固定模板。

## 空间与动画

X 右、Y 前、Z 上（米）。对象位置相对 listener；gain/masterGain 是 dB。静态 lowpass/highpass 单位 Hz、delayMs 单位 ms、decay 单位秒。

可动画 x/y/z/gain/spread/reverb/echo/distortion。插值 smooth/linear/step/bezier；可按通道设置 interpolationByField。手柄 field.inT/outT 是工程绝对秒，field.inV/outV 是通道值。设置全局 interpolation 会清除旧的通道覆盖，除非同时提交 interpolationByField。

对象位置曲线与效果曲线分别存在。删除 key 时只删除用户要求的 fields，避免把音量、位置和混响一起误删。不要给节点 params 添加 keyframes 字段。

需要运动定位：对象 nodeGraph 不包含可听的显式 hrtf 节点，由引擎根据对象 XYZ/位置动画自动空间化。需要静态独立定位：显式 hrtf 的 azimuth/elevation/distance/spread 生效，正 azimuth 向左；可听链路使用此节点后不会再应用对象 XYZ 空间化，后续对象 gain 仍生效。只接在侧链检测分支的 HRTF 不替代可听空间化。

对象 clip 支持 trimStart/trimEnd（秒，trimEnd=0 到源尾）、fadeIn/fadeOut（0–30 秒）、speed（0.25–4）、reverse、invert、normalize、targetPeak（-24–0 dB）。speed 改变音高；normalize 是峰值归一化，不是响度匹配。

关联复制共享声音/clip/nodeGraph/效果及非位置动画；XYZ/位置曲线、名称与颜色独立。不要为了让雨声“更宽”无意间把所有实例的种子、效果和动画一起改动。

## 节点数据

nodeGraph 是对象字段；masterGraph 是工程字段。图是有向无环图：2–64 个节点、最多 128 条边，必须恰好一个 input 和一个 output，节点 ID 唯一。

```json
{
  "enabled": true,
  "nodes": [
    {"id":"in","type":"input"},
    {"id":"wet","type":"convolution","params":{"room":0,"decay":3.8,"predelayMs":22,"wet":0.45}},
    {"id":"out","type":"output"}
  ],
  "edges": [
    {"from":"in","to":"wet","port":"in"},
    {"from":"wet","to":"out","port":"in"}
  ]
}
```

这份图可用于会移动的对象，因为没有显式 hrtf，最终仍由对象 XYZ 自动空间化。默认合成 IR 不是实测房间 IR。

节点 type 共 19 种：input/output/gain/filter/eq/compressor/gate/echo/reverb/distortion/mix/hrtf/chorus/microshift/diffuser/convolution/environment/file/duck。

- 常规节点输入 in；mix 用 a/b；duck 用 in/key。每个输入端口只接一根线，上游输出可以分支。
- input、environment、file 没有输入；output 没有输出。未连接输出可导致静音；不连接到有效输出的节点不会执行 DSP。
- mix 是 A×(1-balance)+B×balance，不是任意多路求和；超过两路需串接 mix。
- file/convolution 的素材路径放在节点顶层 assetPath，不放在 params；保存 .orbit 时会内嵌。
- environment 只生成环境音，kind=0 雨/1 风/2 海浪/3 粉红/4 白噪声；文件用 file，不给 environment 填音频路径。
- duck 主信号接 in、检测信号接 key；KEY 只检测不发声，没接 KEY 时不闪避。
- masterGraph 的输入已经是双耳混合并应用主增益的音频，只可做总线处理，禁止 hrtf/file/environment。节点限制在编辑阶段就会检查。

常用节点参数（默认值；括号为范围）：

| type | params |
| --- | --- |
| gain | gain=0 dB (-60–24) |
| filter | highpass=40 Hz (20–20000)，lowpass=18000 Hz (200–21000)，高通须小于低通 |
| eq | low/mid/high=0 dB (-24–24)，固定 250 Hz 低架 / 1 kHz 峰值 / 4 kHz 高架 |
| compressor | threshold=-24 dB (-60–0)，ratio=4 (1–20)，attack=10 ms (1–200)，release=120 ms (10–2000)，makeup=0 dB (-12–24) |
| gate | threshold=-45 dB (-90–-6)，attack=5 ms (1–200)，release=120 ms (10–2000)；不是 AI 降噪 |
| echo | delayMs=280 (1–2000)，feedback=.42 (0–.85)，wet=.3 (0–1) |
| reverb | decay=2.6 秒 (.15–8)，wet=.5 (0–1) |
| distortion | drive=4 (1–20)，wet=.3 (0–1) |
| mix | balance=.5 (0–1) |
| hrtf | azimuth=0° (-180–180)，elevation=0° (-40–90)，distance=1.5 米 (.15–20)，spread=.2 (0–1) |
| chorus | rate=.23 Hz (.02–3)，depthMs=5 (0–10)，delayMs=18 (12–40)，wet=.35 (0–1) |
| microshift | cents=9 (0–50)，delayMs=12 (1–40)，wet=.3 (0–1) |
| diffuser | amount=.55 (0–.8)，size=1 (.25–2)，wet=.65 (0–1) |
| convolution | decay=3.8 秒 (.15–7.5)，predelayMs=22 (0–250)，wet=.5 (0–1)，room=0 (0/1/2)，normalize=1 (0–1) |
| environment | kind=0 (0–4)，gain=-12 dB (-60–12)，seed=71 (0–65535) |
| file | gain=0 dB (-60–24)，offset=0 秒 (0–86400) |
| duck | threshold=-32 dB (-90–0)，ratio=6 (1–20)，attack=15 ms (1–200)，release=450 ms (10–2000)，depth=12 dB (0–36) |

convolution room=0 明亮浴室、1 暗色房间、2 延迟大厅。自定义 IR 最长 8 秒、最大 256 MiB；normalize>=.5 时归一化 IR 能量。上述为节点范围，不是对象级效果范围。

## 设计示例：靠近的人声与后侧环境

这是用户提出类似目标时的起点，不是必选效果，也不是试听过所有歌曲的“最佳参数”。

- 人声对象可从前方约 6–8 米靠近至 1–1.5 米，结合音量、扩散与混响变化；过渡时长按素材段落决定，不默认绕圈。
- 伴奏分布两侧后方，先检查整体平衡。低频保持克制，不靠极端扩展掩盖分离伪影。
- 浴室感可用 convolution 的明亮浴室 IR，再按需加 diffuser；调高湿声后检查人声可懂度和尾音，避免对象 reverb 与节点混响叠加过量。
- 并联轻失真可保留干声，将失真支路用 mix 叠回；不要把 wet 和 drive 同时拉满来代替调音。
- 微移调/合唱用于增厚，不是位置旋转。静态节点不会自动跟随对象曲线改变参数。
- 环境雨声可分成独立对象，设置不同方位与合适电平；用户需要人声避让时，把独立 file 节点的人声检测源连到 duck.key。只有生成器类型不同并不保证实例独立，关联副本会共享相关参数。
- 保留主输出余量，先比较干湿、开启/旁路、单独人声与全混合。近耳声源和大量高频雨声不一定更沉浸，可能更累耳。

## 真实边界

输出是 48 kHz 双耳立体声，推荐耳机。通用 KEMAR HRTF 的前后/高度定位可能因听者与耳机而异，不能承诺杜比或个体化定位效果。

protectPeaks 默认开启，仅当超出约 -1.2 dBFS 采样峰值上限时整体衰减，不自动抬高安静音频，不是限制器母带链、真峰值或 LUFS 工具。MP3 编码后需重新检查采样峰值。没有实际试听时，不声称已评估音色、情绪、伪影或眩晕感。
