# ORBIT 自动化与接口说明（CLI & HTTP API）

> **适用版本**：首次公开发布 · 初版（`0.7.1`）

除了图形界面之外，ORBIT 还面向开发者与高级用户提供了 **命令行工具（CLI）** 以及 **需主动启用的本地 HTTP API**，方便你将环境检查、工程分析、音源分轨和离线渲染集成到自己的本地自动化脚本或流水线中。

接口参考已按实现补齐，完整参数见文末的生成帮助和随仓库 OpenAPI 文件。

---

## 一、命令行工具（CLI）

ORBIT 命令行工具目前包含以下 **8 个已知命令类别**：

| 命令类别 | 核心用途说明 |
| :--- | :--- |
| **`doctor`** | **环境诊断与自检**。用于检查 ORBIT 本地运行环境及外部依赖（如 Python 依赖包、FFmpeg 和内置 HRTF）的状态。 |
| **`inspect`** | **检查媒体信息**。解码音频并报告时长、声道与波形；工程信息使用 `project info`。 |
| **`analyze`** | **执行音频分析**。用于调用 ORBIT 的离线分析能力（如源音频频谱特征计算等）。 |
| **`run`** | **执行自动化任务流程**。用于按既定配置运行批处理或组合操作任务。 |
| **`project`** | **工程文件管理与操作**。用于通过命令行对 `.orbit` 工程进行创建、查询、对象编辑和关键帧操作。 |
| **`render`** | **离线渲染导出**。用于在不打开图形界面的情况下，将 `.orbit` 工程离线渲染并导出为目标双耳空间音频文件。 |
| **`separate`** | **音源分轨处理**。用于调用已接入的 Demucs 模型（`htdemucs`、`htdemucs_ft`、`htdemucs_6s`）通过 CPU 或兼容 GPU 执行音轨分离任务。 |
| **`serve`** | **启动本地 HTTP API 服务**。用于主动启动本地回环地址上的自动化 HTTP 接口服务。 |

---

## 二、本地 HTTP API 与安全边界

ORBIT 的本地 HTTP API **默认处于关闭状态**，需要由用户或开发者主动启用（例如通过 `serve` 命令类别启动）。
为了防止本地音频工具在开启服务后被恶意网页或局域网未授权请求滥用，ORBIT 的 HTTP API 设计了严格的安全边界与运行机制：

### 1. 默认绑定本机回环地址（Loopback Only）
- API 服务默认仅在本机回环地址上工作，不直接向局域网或公网暴露监听端口。

### 2. Bearer 鉴权机制（Bearer Authentication）
- 接口调用具备 Bearer 鉴权保护，客户端请求必须携带有效的凭据方可执行受保护的操作。

### 3. Host / Origin 检查
- 服务端会对传入请求的 `Host` 与 `Origin` 请求头进行校验，防御跨站请求伪造（CSRF）及来自非受信浏览器页面的本地探测调用。

### 4. 工作目录限制（Workspace Sandboxing）
- API 对文件系统的读写访问受限于允许的工作目录边界之内，校验路径是否越过工作目录；这不是操作系统级沙箱。

### 5. 有界任务队列与取消机制（Bounded Queue & Cancellation）
- 由于 Demucs 分轨、STFT 频谱分析与双耳空间音频离线渲染均为计算密集型任务，API 内部采用**有界任务队列**管理并发与排队，限制待处理任务数量；不能保证单个大型任务不会耗尽内存或显存。
- 支持对正在排队或执行中的任务发起**取消（Cancel）**操作，便于上层自动化程序及时中止超时的渲染或分轨任务。

---

## 三、已核实的调用入口与接口规范

### 1. 命令行入口与参数

便携包根目录使用 `orbit.cmd`；源码目录也可用 `python backend/cli.py`。它优先使用 `ORBIT_PYTHON`，否则寻找本地 `runtime/Scripts/python.exe`，最后使用 PATH 中的 `python`。FFmpeg 可由 `ORBIT_FFMPEG` 指定。

完整参数、必选项及帮助文字由实际命令行解析器生成，见 [CLI_HELP.txt](docs/CLI_HELP.txt)。每条命令都支持 `--help`；`run 请求.json` 接收一个 UTF-8 JSON 请求，`run -` 从标准输入读取，不执行任意系统命令。

```powershell
.\orbit.cmd --help
.\orbit.cmd doctor
.\orbit.cmd project new '.\demo.orbit' --name '雨夜示例' --duration 8
.\orbit.cmd project add '.\demo.orbit' --generator rain --overwrite
.\orbit.cmd render '.\demo.orbit' '.\demo.flac' --format flac
```

默认不覆盖文件；原地编辑需显式 `--overwrite`。拆分必须指定全新输出目录。工程操作还包括 edit/add/set/duplicate/unlink/remove/key/delete-key；完整选项见帮助文件。

成功时 stdout 为一行 `{"ok":true,"data":...}`，进度及错误写 stderr，JSON 使用 UTF-8。退出码：成功 0、执行失败 1、参数用法错误 2、键盘中断 130。`--help` / `--version` 为普通文本。

### 2. HTTP API 入口

在已经存在的专用目录启动：

```powershell
.\orbit.cmd serve --workspace 'C:\ORBIT-Workspace' --port 8765
```

固定绑定 `127.0.0.1`；端口默认 8765，`--port 0` 可让系统分配。默认生成工作目录中的 `.orbit-api-token`，也可用 `--token-file` 指定私有文件。已有令牌至少 32 个可打印 ASCII 字符；启动信息只给出令牌文件位置，不打印令牌。

所有路由均需要 `Authorization: Bearer <token>`。Host 必须为本服务端口的 localhost 或 127.0.0.1；拒绝带 Origin 的请求，不开放 CORS。JSON 正文需 Content-Type 和 Content-Length，大小 1 字节至 1 MiB，不支持分块上传。

| 方法与路由 | 用途 |
| --- | --- |
| GET `/v1/health` | 版本、工作目录、输出能力 |
| GET `/v1/capabilities` | 动作、格式、节点和动画通道 |
| GET `/v1/openapi.json` | 原始 OpenAPI 3.1 JSON，不包在 data 中 |
| POST `/v1/execute` | 同步 doctor / project.read |
| POST `/v1/jobs` | 排队执行 inspect/analyze/project.create/project.edit/render/separate |
| GET `/v1/jobs` | 任务列表 |
| GET `/v1/jobs/{id}` | 状态、进度、结果和错误 |
| DELETE `/v1/jobs/{id}` | 取消排队或执行中的任务 |

请求 Schema、响应包络、任务字段和错误状态见随仓库的 [OpenAPI 文件](backend/openapi.json)；便携包中位于 `app/backend/openapi.json`。客户端示例见 [scripts/api_example.py](scripts/api_example.py)，使用真实请求体，不依赖猜测接口。

成功响应通常为 `{"ok":true,"data":...}`，错误为 `{"ok":false,"error":{"code":"...","message":"..."}}`。提交任务返回 202 与 Location，只代表进入队列；需继续检查任务 state 和 error。状态为 queued/running/cancelling/succeeded/failed/cancelled。常见状态包括 400 无效请求、401 鉴权失败、403 Host/Origin/路径拒绝、404 不存在、409 冲突、411 缺长度、413 正文过大、415 非 JSON、429 队列已满；任务中的处理错误保存在 error 中。

队列一次执行一个任务，最多 16 个待处理/执行任务，最多保留 128 条内存历史；重启不恢复历史。默认渲染跨度上限 600 秒，可由 `--max-render-seconds` 调整，这不是内存配额。

API 原地编辑必须同时给出 `overwrite:true` 和读取工程得到的 `ifRevision`。CLI/API 操作的是磁盘工程，不控制已打开的界面，尚未保存的修改不可见；也没有跨进程文件锁，请勿同时让 GUI 和 API 改写同一工程。

工作目录约束不是操作系统沙箱，服务仍以启动用户权限运行。不要向公网或局域网暴露服务。取消不是撤销；若输出已在取消前完成发布，该输出仍可能保留，原文件和已经完成的成品不会被取消操作删除。
