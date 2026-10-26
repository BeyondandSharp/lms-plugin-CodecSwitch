# CodecSwitch（Lyrion Music Server 插件）

[English](README.md)

`CodecSwitch` 让每个播放器拥有独立的源编码策略。对每种源编码可以选择：

- **直出** —— 插件不强制目标编码；播放器支持源编码时由 LMS 直接播放，
  否则沿用 LMS 原有回退逻辑。
- **跳过** —— 播放到该编码的曲目时，将其从当前播放器队列移除。
- **转换为目标编码** —— FLAC、WAV、AIFF/裸 PCM、MP3、AAC、Ogg Vorbis、
  Opus 或 ALAC（ALAC 为实验性）。

插件不修改 LMS 核心文件：运行时按播放器注册
`Slim::Player::TranscodingHelper` 规则，并只在启用期间包装
`getConvertCommand2`。

已在官方 Docker 镜像 `lmscommunity/lyrionmusicserver:9.0.0` 和 `:9.1.1`
上验证。

## 依赖

- Lyrion Music Server **9.0+**（已验证 9.0.0、9.1.1）。
- LMS 镜像自带 `flac`、`sox`、`lame`，9.1.1 还带 `opusenc`。这些工具足以
  完成 FLAC、WAV、AIFF/裸 PCM、MP3、Ogg Vorbis、Opus 的转换。
- **FFmpeg 可选但推荐**。AAC、ALAC、多数特殊源格式（WMA/APE/MPC/M4A/ALAC/DSD）
  以及远程流目标转换需要 FFmpeg。官方 LMS 镜像不自带 FFmpeg。
- Unix 上可选的并发限制需要 `flock`（util-linux）。

## 安装

```sh
make dist
```

把 `dist/CodecSwitch` 复制到 LMS 插件目录并重启 LMS。

官方 Docker 镜像的第三方插件目录是 `/config/cache/Plugins`：

```sh
docker cp dist/CodecSwitch <container>:/config/cache/Plugins/CodecSwitch
```

也可以挂载：

```sh
-v /path/to/dist/CodecSwitch:/config/cache/Plugins/CodecSwitch
```

然后在 **设置 → 插件** 中启用 **CodecSwitch**。服务器设置页在
**设置 → CodecSwitch**；播放器设置在对应播放器的设置页中。

## 服务器设置

- **转码并发数** —— 同时运行的编码进程上限。`0` 表示不限制（LMS 默认）。
  Unix 下由 `Bin/codecswitch-gate` 使用 `flock` 槽位强制执行；Windows 下不可用。
  原生两段式管线限制最终编码进程。
- **工具路径** —— `ffmpeg`、`flac`、`lame`、`sox`、`opusenc` 的可选绝对路径。
  留空则从 LMS `Bin` 目录/PATH 自动查找。
- **编码后端** —— FLAC、WAV、AIFF、MP3、Ogg Vorbis、Opus 可选
  `自动`、`FFmpeg`、`原生工具`。自动优先使用 LMS 自带工具，失败回退 FFmpeg。
  AAC、ALAC 固定使用 FFmpeg。

保存后立即生效，无需重启 LMS。

## 播放器设置

播放器设置页会列出所有已知源编码及其可用动作。只有在播放器上报了对应
LMS 格式且编码器可用时，目标编码才会出现。若播放器没有上报格式，则只显示
直出和跳过。

默认全部为直出。

### 跳过行为

被标记为跳过的曲目到达 `playlist newsong` 时，插件执行
`playlist deleteitem`，LMS 随即播放下一首；同时会提前移除后续最多 5 首同样
标记为跳过的曲目，避免预加载。此操作只影响当前播放器队列，不修改音乐库、
保存的播放列表或其他播放器。

### 直出行为

直出表示「插件不强制目标编码」。播放器支持源编码时由 LMS 直接透传；不支持时
仍走 LMS 原有回退逻辑。

## 目标格式

| 目标 | LMS 格式 | FFmpeg 编码器 | 原生路径 | 说明 |
|---|---|---|---|---|
| FLAC | `flc` | `flac` | SoX 解码 → `flac` | 无损 |
| WAV | `wav` | `pcm_s16le` | SoX | 16-bit PCM WAV |
| AIFF | `aif` | `pcm_s16be` | SoX 裸大端 | LMS 的 `aif` 流为裸 PCM，与核心 `flc→aif` 一致 |
| MP3 | `mp3` | `libmp3lame` | SoX 解码 → `lame` | 有损 |
| AAC | `aac` | `aac` | 无 | ADTS；需要 FFmpeg |
| Ogg Vorbis | `ogg` | `libvorbis` | SoX | 有损 |
| Opus | `ops` | `libopus` | SoX 解码 → `opusenc` | Ogg Opus |
| ALAC | `alc` | `alac` | 无 | 实验性，分片 MP4 |

目标格式必须出现在播放器上报的 formats 中。例如播放器只上报 `pcm` 而没有
`wav` 时，不会提供 WAV；若它上报 `flc`/`mp3`/`ogg`/`aif`，仍可选择这些目标。

## SACDPlayer 集成（DST/DFF）

启用 `SACDPlayer` 时，CodecSwitch 不再注册竞争的 `dff`/`dsf` 规则，而是把
DSD 处理交给 SACDPlayer。若 DSD 源在 CodecSwitch 中配置了目标编码，链路为：

```text
DST/DFF/DSF -> SACDPlayer PCM/FLAC -> CodecSwitch 目标编码器 -> 播放器
```

说明：

- CodecSwitch 向 SACDPlayer 请求 FLAC/PCM 输出（强制 `flc`），再把该流送进
  目标编码器。播放器最终只会收到目标格式。
- 这要求 SACDPlayer 的 FFmpeg 路径可用，因为它的 FLAC/PCM 输出依赖 FFmpeg。
  第二段使用 CodecSwitch 配置的后端（原生工具或 FFmpeg）。
- 目标为 `FLAC` 时直接使用 SACDPlayer 的 FLAC 输出，不再进行第二段编码。
- DSD 源设置了目标编码时，SACDPlayer 自己的 Native/DoP 输出模式会被绕过，
  改用 PCM/FLAC 中间流。要保留 Native/DoP，请把 CodecSwitch 中的
  `dff`/`dsf` 设为 **直出**。
- SACDPlayer 未启用时，CodecSwitch 会在 FFmpeg 可用时回退到自己的 DFF 解码。
- SACDPlayer 没有可用的 FFmpeg 路径时，DSD 目标编码不会显示，只保留直出/跳过。

## 远程流

本地文件可以使用完整的原生/FFmpeg 工具链。HTTP(S) 远程流的目标转换只通过
FFmpeg 提供；没有 FFmpeg 时保持 LMS 原有行为。跳过对本地和远程曲目都生效。

## 架构

```text
lib/Plugins/CodecSwitch/
├── Plugin.pm          # LMS 入口、客户端事件、启动
├── Config.pm          # 源/目标表与映射决策
├── Toolchain.pm       # 工具发现、探测、后端选择
├── CommandBuilder.pm  # FFmpeg/原生命令模板
├── Profiles.pm        # 按播放器注册运行时 commandTable
├── Hooks.pm           # getConvertCommand2 包装
├── Skip.pm            # playlist newsong 跳过处理
├── Settings.pm        # 服务器设置页
└── PlayerSettings.pm  # 播放器映射页
```

`Profiles.pm` 为本地注册带 `F` capability 的规则，为远程注册带 `R` 的规则
（使用 LMS 支持的 `-1` 重复实例后缀）。同名已有规则会被保存，并在刷新/移除
插件规则时恢复。

## 开发与测试

```sh
make test          # 单元测试、命令生成、真实 FFmpeg 管线、并发门
make dist          # 生成 dist/CodecSwitch
make verify-dist   # 校验清单版本和模块
make bundle        # 生成 zip + tar.gz
make smoke         # Docker 9.0.0 + 9.1.1 加载/设置页冒烟测试
```

单元测试包含每个目标编码的真实 FFmpeg 管线测试，以及并发门测试。Docker
冒烟测试只验证服务器能加载插件并打开设置页，不创建播放器，不测试播放器端。

## 版本与发布

`VERSION` 是唯一版本来源。`install.xml.in`、`repo.xml.in` 只包含
`@VERSION@` / `@RELEASE_URL@` 占位符；`make dist` 渲染到 `build/`。
可覆盖 catalog 基址：

```sh
make bundle RELEASE_BASE=https://example.test/releases/download
```

## 限制

- ALAC 输出为实验性，使用分片 MP4 以支持流式输出。
- AIFF 目标是裸大端 PCM，LMS 流格式为 `aif`，不是 AIFF 容器；这与 LMS 核心
  `flc→aif` 规则一致。
- AAC/ALAC 和特殊源编码需要 FFmpeg。
- 并发限制依赖 `flock`，Windows 不可用。
- 播放器不支持源编码时，直出不保证比特完美。
- 同时启用 SACDPlayer 和 CodecSwitch 时，DSD 目标映射会使用 SACDPlayer 的
  PCM/FLAC 输出再接 CodecSwitch 编码器；这些映射会绕过 SACDPlayer 的
  Native/DoP 模式。
- 插件不修改 LMS 核心，也不处理播放器端解码。
