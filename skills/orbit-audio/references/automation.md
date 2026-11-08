# ORBIT 自动化参考

按 ORBIT 0.7.1 核对。更换版本时先读实际 --help；完整结构位于源码 backend/openapi.json，便携包 app/backend/openapi.json。[上游仓库](https://github.com/Eyeing0721/orbit-audio)。

## CLI 基础

在 ORBIT 根目录的 PowerShell 中：

```powershell
.\orbit.cmd --version
.\orbit.cmd doctor
.\orbit.cmd inspect 'C:\Audio\source.flac'
.\orbit.cmd project new 'C:\Work\mix.orbit' --name '空间工程' --duration 30
.\orbit.cmd project add 'C:\Work\mix.orbit' --audio 'C:\Audio\source.flac' --overwrite
.\orbit.cmd project info 'C:\Work\mix.orbit'
.\orbit.cmd render 'C:\Work\mix.orbit' 'C:\Work\preview.flac' --format flac --start 0 --seconds 12
```

也可把每个命令接到本技能 scripts/orbit.py 后面。首次 new 后的 add 是有意修改新建工作副本；若已有同名用户工程，则先另存，不照抄 overwrite。

成功 stdout 是单个 JSON：{"ok":true,"data":...}；进度和错误在 stderr。失败 JSON 含 error.code/message。退出码 0 成功、1 执行失败、2 参数错误、130 中断。帮助/版本返回普通文字。

inspect 解码媒体，不读取 .orbit 工程；工程用 project info。不要将进程退出 0 与内部 ok=false 混为一谈。

## 分轨

```powershell
.\orbit.cmd separate 'C:\Audio\source.flac' 'C:\Work\stems-new' --model htdemucs_6s --parts vocals drums bass guitar piano other --device auto --shifts 1
```

- 输出目录必须不存在，没有可用的拆分 overwrite 模式。
- htdemucs_6s 支持六部件；htdemucs / htdemucs_ft 为 vocals/drums/bass/other。instrumental 是额外可选结果。
- --device 只接受 auto/cpu，不是 cuda；auto 在可用时用 CUDA，以返回 device 为准。
- shifts 是 0–10 的整数；较大值可能增加时间，不能承诺无伪影或一定更干净。
- 首次需要模型下载。模型可能计算/保留未选择的部件；只把返回 files 中用户需要的路径导入工程，保留模型子目录，不猜固定文件名。

## 编辑与保存

复杂请求写 UTF-8 JSON 后运行 orbit.cmd run request.json；也可将 JSON 通过 stdin 交给 run -。不通过拼接 shell 命令构造 JSON。

创建请求可带完整 scene，schemaVersion=2；此时 scene 决定设置，不与外层 name/duration 叠加。完整 scene 可指定唯一对象 ID；普通 add 自动分配 ID，需读取返回 edits[].id。

示例是完全程序化风声，没有真实人声或用户音乐：

```json
{
  "action": "project.create",
  "output": "C:/Work/wind.orbit",
  "scene": {
    "schemaVersion": 2,
    "name": "程序化风声示例",
    "duration": 8,
    "tail": 1,
    "masterGain": -6,
    "protectPeaks": true,
    "objects": [
      {"id":"wind","name":"风声","generator":"wind","duration":8,"x":0,"y":6,"z":0.2,"gain":-6}
    ]
  }
}
```

给上面的 wind 加接近动画与对象效果，可另存为新工程：

```json
{
  "action":"project.edit",
  "path":"C:/Work/wind.orbit",
  "output":"C:/Work/wind-edited.orbit",
  "operations":[
    {"op":"set","id":"wind","values":{"reverb":0.3,"room":"bathroom","decay":2.6}},
    {"op":"keyframe","id":"wind","time":0,"values":{"y":6,"y.outT":2,"y.outV":6},"interpolation":"bezier"},
    {"op":"keyframe","id":"wind","time":8,"values":{"y":1.2,"y.inT":6,"y.inV":1.2},"interpolation":"bezier"}
  ]
}
```

常用操作：

| op | 内容 |
| --- | --- |
| project | values 设置 duration、tail、masterGain、masterGraph、protectPeaks、listener、hrtf、name、workspace |
| add | values.path 导入音频，或 values.generator 添加 rain/wind/ocean/white/pink；返回新 ID |
| set | id + values 修改对象；修改 path 会重新检查音频 |
| duplicate | id、linked，可选 values 中的 name/x/y/z；XYZ 目标会连同位置关键帧和手柄一起平移 |
| unlink / remove | 解除共享 / 从工程移除，不删除源素材 |
| keyframe | id、time、values，可选 interpolation；同一时刻合并指定通道 |
| keyframe.remove | id、time；fields 可指定通道，省略删除该时刻全部通道 |

CLI 对应 project edit/add/set/duplicate/unlink/remove/key/delete-key；各自可用 --help。project edit --operations 接收操作数组文件。

对象字段使用 gain，不是 gainDb；音效常用 reverb/echo/distortion/spread（0–1）、highpass/lowpass（Hz）、delayMs、feedback、decay（秒）、offset（秒）、mute/solo/loop、clip、nodeGraph。不要自行修改 id/linkId/waveform。关键帧通道及手柄只使用实际支持的字段。

返回 project.read/project info 的 project 内嵌素材路径如 media/... 是容器内引用，不是独立磁盘路径。不要把读取结果重新当成一份外部 JSON 工程来创建；用原 .orbit 加 project.edit，避免丢失内嵌资源。

只改 gain、reverb 等标量时提交局部 values。若要整份替换含内嵌文件/IR 的 nodeGraph，不能直接把 info 返回的 media/... 再当作 assetPath 提交；先确定用户授权的实际素材路径。没有可用源素材时说明限制，不猜引擎临时解包目录，也不丢弃资产来强行保存。

原地编辑需 overwrite:true；建议同时提供 ifRevision，其值来自刚读取的 revision。整组操作通过才写工程，但文件级 revision 不是跨进程锁。

## 导出与检查

| format | 后缀与编码 |
| --- | --- |
| wav24 / wav32 | .wav，24 位整数 PCM / 32 位浮点 |
| flac | .flac，24 位整数无损 |
| aiff / caf / w64 | .aiff 24 位 PCM / .caf 32 位浮点 / .w64 24 位 PCM |
| mp3 | .mp3，320 kbps |
| aac / alac | .m4a，AAC 320 kbps / ALAC 24 位无损 |
| opus / vorbis | .opus 256 kbps / .ogg Vorbis Q8 |

这些预设输出 48 kHz 双声道。format 必须与后缀匹配。FLAC 不支持这里的浮点预设。MP3/AAC 等转码依赖 FFmpeg，其构建必须含所需编码器。

render 不带 seconds 时输出剩余工程与尾音；带 start/seconds 用于短段试听，不能把短段当成全曲成品。tail 0–10 秒。返回时长、peakDb、rmsDb、attenuationDb 是检查线索，不是 LUFS 或真峰值；有损编码后的采样峰值可能变化。

用 inspect 重新解码成品。waveform 是分块绝对峰值，可检查是否全为 0；不要用它声称听感良好。analyze path.orbit --object-id ID --seconds 12 分析所选对象的源/剪辑/节点结果，--raw 查看原源，最长 30 秒；不是最终主输出分析。

## HTTP：仅在需要时启用

```powershell
.\orbit.cmd serve --workspace 'C:\ORBIT-Workspace' --port 8765
```

workspace 必须已存在。固定绑定 127.0.0.1，--port 0 由启动行返回实际端口。默认令牌文件为 workspace/.orbit-api-token，可用 --token-file 指定。至少 32 个可打印 ASCII 字符，不在聊天、URL、日志或提交内容中打印令牌。

通过普通 HTTP 客户端调用，不通过浏览器网页调用：所有路由需要 Authorization: Bearer；Host 必须匹配 localhost/127.0.0.1 和端口，拒绝 Origin，不开放 CORS。JSON 请求需要 Content-Type: application/json 和 Content-Length，最大 1 MiB；urllib 等客户端会为字节正文生成长度。

| 方法 | 路由 | 作用 |
| --- | --- | --- |
| GET | /v1/health、/v1/capabilities | 状态 / 实际能力 |
| GET | /v1/openapi.json | 原始 OpenAPI JSON，不包在 data 内 |
| POST | /v1/execute | 同步 doctor、project.read |
| POST | /v1/jobs | inspect、analyze、project.create、project.edit、render、separate |
| GET | /v1/jobs、/v1/jobs/{id} | 列表 / 状态与结果 |
| DELETE | /v1/jobs/{id} | 取消任务；不撤销已完成输出 |

CLI JSON 请求同样可作为 execute/jobs 的 body。其他正常成功响应为 {"ok":true,"data":...}。提交返回 202 只表示排队，必须轮询至 succeeded/failed/cancelled，检查 result/error；不要将 queued/running/cancelling 当作成功。

队列一次执行一个任务，最多 16 个待处理/执行任务，历史保留至多 128 条、重启不保留。轮询可用 0.5–2 秒间隔；等待超时先保留任务 ID、查询状态，不重投可能已经成功的任务。

API 所有输入、工程、节点资产和输出都需在 workspace 内。相对路径基于 workspace，默认内置 HRTF 是受控例外。不能自动移动用户素材来绕过范围限制；确需复制时先明确范围，保留原件。路径限制不是 OS 沙箱。

API 原地编辑必须同时给出 overwrite:true 和刚读取的 ifRevision。revision_conflict 时先重新检查工程；401/403 时修正凭据/路径/Host，不关闭保护。渲染默认 max-render-seconds=600，还限制从 0 开始涉及的绝对跨度；长曲可在用户允许下用 CLI 或调整服务设置，不静默截断。完成后只停止自己启动的服务，不终止他人的进程。
