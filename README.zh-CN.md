# CodecSwitch for Lyrion Music Server

![GitHub Release](https://img.shields.io/github/v/release/BeyondandSharp/lms-plugin-CodecSwitch)

[English](README.md)

`CodecSwitch` 为每个播放器单独配置源编码策略。对每种源编码可以选择：

- **直出** — 插件不强制目标编码；播放器支持时由 LMS 直接播放，否则走 LMS 原有回退逻辑。
- **转换为目标编码** — FLAC、WAV、AIFF/raw PCM、MP3、AAC、Ogg Vorbis、Opus 或 ALAC（ALAC 实验性）。

插件不修改 LMS 核心文件，只按播放器动态注册 `Slim::Player::TranscodingHelper` profile，并在启用期间包装 `getConvertCommand2`。

已测试 `lmscommunity/lyrionmusicserver:9.0.0` 与 `:9.1.1`。

## 依赖

- Lyrion Music Server **9.0+**。
- LMS 镜像已含 `flac`、`sox`、`lame`；9.1.1 还含 `opusenc`。
- **FFmpeg 可选但推荐**：AAC、ALAC、大多数特殊源格式（WMA/APE/MPC/M4A/ALAC/DSD）、远程流转换、带码率限制的 Ogg Vorbis 需要它。

## 安装

```sh
make dist
```

把 `dist/CodecSwitch` 复制到 LMS 插件目录并重启。官方 Docker 镜像的第三方插件目录是 `/config/cache/Plugins`：

```sh
docker cp dist/CodecSwitch <container>:/config/cache/Plugins/CodecSwitch
```

或挂载：

```sh
-v /path/to/dist/CodecSwitch:/config/cache/Plugins/CodecSwitch
```

在 **Settings → Plugins** 启用 CodecSwitch。服务器页是 **Settings → CodecSwitch**，播放器页在各播放器设置中。

## 服务器设置

- **工具路径** — 可选配置 `ffmpeg`、`flac`、`lame`、`sox`、`opusenc`；留空自动从 LMS `Bin` 或 PATH 查找。
- **编码后端** — FLAC/WAV/AIFF/MP3/Ogg Vorbis/Opus 可选 `Auto`、`FFmpeg`、`Native helper`；AAC/ALAC 始终使用 FFmpeg。

保存后立即生效，无需重启。

## 播放器设置

播放器页列出所有源编码；只有播放器上报了目标格式且编码器可用时才会显示该目标。未上报任何格式时只显示直出。

默认全部直出。

## 目标格式

| 目标 | LMS 格式 | FFmpeg 编码器 | Native 路径 | 说明 |
|---|---|---|---|---|
| FLAC | `flc` | `flac` | SoX → `flac` | 无损 |
| WAV | `wav` | `pcm_s16le` | SoX | 16-bit PCM |
| AIFF | `aif` | `pcm_s16be` | SoX raw big-endian | LMS `aif` 为 raw PCM |
| MP3 | `mp3` | `libmp3lame` | SoX → `lame` | 有损，支持 B |
| AAC | `aac` | `aac` | 无 | ADTS；需要 FFmpeg；支持 B |
| Ogg Vorbis | `ogg` | `libvorbis` | SoX | 有损；带码率限制时优先 FFmpeg |
| Opus | `ops` | `libopus` | SoX → `opusenc` | Ogg Opus；支持 B |
| ALAC | `alc` | `alac` | 无 | 实验性 |

目标格式必须在播放器上报的 `formats()` 中。

## 码率限制

LMS 每播放器的 **Maximum Bitrate** (`maxBitrate`) 对 MP3、AAC、Ogg Vorbis、Opus 生效。插件在这些 profile 上声明 LMS `B` capability；无损目标不声明 B，不受限制。

目标编码仍由 CodecSwitch 播放器映射决定；码率设置只是上限，不是目标编码选择器。

### 可选 LMS 核心 UI 补丁

LMS 原生页面只在 LAME 存在时启用码率下拉框，且文案只提 MP3。若要让下拉框在只有 FFmpeg/opusenc 时也可用，并显示通用文案，可应用可选补丁：

```sh
make lms-patch-check LMS_ROOT=/path/to/lms
make lms-patch       LMS_ROOT=/path/to/lms
```

补丁也随 `dist/CodecSwitch/patches/lms/` 发布。它只修改 `Slim/Web/Settings/Player/Audio.pm` 和 `HTML/EN/settings/player/audio.html`。LMS 升级会覆盖，升级后需重新应用。不应用补丁时，只要 LAME 存在，码率限制仍然生效，只是 UI 文案/可用性不同。

## DSD provider 集成（DST/DFF）

CodecSwitch 不检查具体插件名，而是检测 LMS 中是否已有可用的 `dff`/`dsf → flc` profile。**SACD** 插件只是其中一种 provider，其他 DSD 解码插件同样适用。

```text
DST/DFF/DSF -> 已注册的 DSD provider PCM/FLAC -> CodecSwitch 目标编码 -> 播放器
```

- 有损目标：CodecSwitch 请求 provider 输出 raw PCM（若支持），再直接编码，避免多一次 FLAC 编解码。
- FLAC 目标：provider 的 FLAC 就是最终流，不再二次 FLAC 编码。
- WAV/AIFF/ALAC 目标：请求 PCM，再编码一次目标。
- 有 DSD 目标映射时会绕过 provider 的 Native/DoP；要保留 Native/DoP，把 `dff`/`dsf` 设为直出。
- 没有 provider 注册 DSD profile 时，CodecSwitch 在 FFmpeg 可用时使用自己的 DFF 路径。

## 远程流

本地文件使用完整 Native/FFmpeg 工具链；HTTP(S) 流的目标转换只走 FFmpeg。

## 架构与优先级

```text
unknown / legacy profiles  0   最高，尽量保留原系统
DSD provider（如 SACD）    50
FFmpeg plugin              100
CodecSwitch native         200
```

已有的非 CodecSwitch profile 优先；CodecSwitch 只补缺失规则和处理 DSD 组合。

```text
lib/Plugins/CodecSwitch/
├── Plugin.pm
├── Config.pm
├── Capabilities.pm
├── Orchestrator.pm
├── Toolchain.pm
├── CommandBuilder.pm
├── Profiles.pm
├── Hooks.pm
├── Settings.pm
└── PlayerSettings.pm
```

## 调试日志

插件注册了自己的日志类别，因此会出现在 LMS 标准日志设置页：

```text
Settings → Advanced → Logging → Advanced logging settings
```

在那里设置 `plugin.codecswitch`、`plugin.sacdplayer`、`plugin.ffmpeg` 和核心的 `player.source` 类别。仅在排查问题时使用 `DEBUG`，可能产生较大的日志文件。CodecSwitch 不再在自己的设置页提供单独的日志设置。

## 开发

```sh
make test
make dist
make verify-dist
make bundle
make smoke
```

Docker smoke 只验证服务器加载和设置页，不测试播放器端播放。

## 限制

- ALAC 实验性。
- AIFF 目标实际是 raw big-endian PCM，LMS 格式为 `aif`。
- AAC/ALAC 与特殊源格式需要 FFmpeg。
- 可选 LMS 核心补丁需在 LMS 升级后重新应用。
