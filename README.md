# CodecSwitch for Lyrion Music Server

[中文说明](README.zh-CN.md)

`CodecSwitch` gives each player its own source-codec policy. For every source
codec you can choose:

- **Pass-through** — the plugin does not force a target; LMS plays the original
  stream when the player supports it and keeps its normal fallback otherwise.
- **Convert to a target codec** — FLAC, WAV, AIFF/raw PCM, MP3, AAC, Ogg
  Vorbis, Opus or ALAC (ALAC is experimental).

The plugin does not modify LMS core files. It registers per-player
`Slim::Player::TranscodingHelper` profiles at runtime and wraps
`getConvertCommand2` only while the plugin is active.

Tested with `lmscommunity/lyrionmusicserver:9.0.0` and `:9.1.1`.

## Requirements

- Lyrion Music Server **9.0+** (tested with 9.0.0 and 9.1.1).
- The LMS image already contains `flac`, `sox` and `lame`; 9.1.1 also contains
  `opusenc`. Those tools cover FLAC, WAV, AIFF/raw PCM, MP3, Ogg Vorbis and
  Opus without extra packages.
- **FFmpeg is optional but recommended.** It is required for AAC, ALAC, most
  exotic source formats (WMA/APE/MPC/M4A/ALAC/DSD), remote-stream target
  conversion, and bitrate-limited Ogg Vorbis.

## Install

```sh
make dist
```

Copy `dist/CodecSwitch` to the LMS plugin directory and restart LMS. For the
official Docker image the third-party plugin directory is
`/config/cache/Plugins`:

```sh
docker cp dist/CodecSwitch <container>:/config/cache/Plugins/CodecSwitch
```

or mount it:

```sh
-v /path/to/dist/CodecSwitch:/config/cache/Plugins/CodecSwitch
```

Then open **Settings → Plugins** and enable **CodecSwitch**. The server page is
**Settings → CodecSwitch**; per-player settings are under the player's
settings pages.

## Server settings

- **Tool paths** — optional absolute paths for `ffmpeg`, `flac`, `lame`, `sox`
  and `opusenc`. Empty means auto-detect from the LMS `Bin` directory/PATH.
- **Encoder backends** — for FLAC, WAV, AIFF, MP3, Ogg Vorbis and Opus choose
  `Auto`, `FFmpeg` or `Native helper`. `Auto` prefers the LMS helper tools and
  falls back to FFmpeg. AAC and ALAC always use FFmpeg.

Changes are applied immediately; no LMS restart is needed.

## Player settings

The player page lists every known source codec with the available actions.
Targets are only offered when the player reports the matching LMS format and
the encoder is available. If a player reports no formats, only pass-through is
shown.

Default: every source is pass-through.

### Direct / pass-through semantics

Pass-through means "the plugin does not force a target codec". If the player
supports the source codec, LMS streams it directly. If not, LMS's existing
fallback rules still apply.

## Target formats

| Target | LMS format | FFmpeg encoder | Native path | Notes |
|---|---|---|---|---|
| FLAC | `flc` | `flac` | SoX decode → `flac` | lossless |
| WAV | `wav` | `pcm_s16le` | SoX | 16-bit PCM WAV container |
| AIFF | `aif` | `pcm_s16be` | SoX raw big-endian | LMS `aif` stream is raw PCM |
| MP3 | `mp3` | `libmp3lame` | SoX decode → `lame` | lossy, supports B |
| AAC | `aac` | `aac` | none | ADTS; FFmpeg required; supports B |
| Ogg Vorbis | `ogg` | `libvorbis` | SoX | lossy; FFmpeg preferred for B |
| Opus | `ops` | `libopus` | SoX decode → `opusenc` | Ogg Opus; supports B |
| ALAC | `alc` | `alac` | none | experimental, fragmented MP4 |

The target must be in the player's reported formats.

## Bitrate limiting

LMS's per-player **Maximum Bitrate** setting (`maxBitrate`) is honored for
lossy targets: MP3, AAC, Ogg Vorbis and Opus. The plugin exposes the LMS `B`
capability on those profiles. Lossless targets do not expose `B` and are not
limited.

The target codec is still chosen by the CodecSwitch player mapping; the bitrate
setting is an upper bound, not a target-codec selector.

### Optional LMS core UI patch

LMS's stock audio-settings page only enables the bitrate selector when LAME is
available and describes it as MP3-only. To show the codec-agnostic labels and
allow the selector when FFmpeg/opusenc is available without LAME, apply the
optional core patch:

```sh
make lms-patch-check LMS_ROOT=/path/to/lms
make lms-patch       LMS_ROOT=/path/to/lms
```

The patch is also shipped in `dist/CodecSwitch/patches/lms/`. It modifies only
`Slim/Web/Settings/Player/Audio.pm` and
`HTML/EN/settings/player/audio.html`. LMS upgrades overwrite it; re-apply after
an upgrade. Without the patch, the bitrate limit still works when LAME is
present; only the UI wording/availability differs.

## DSD provider integration (DST/DFF)

CodecSwitch does not look for a specific plugin name. It detects whether LMS
already has a usable `dff`/`dsf → flc` profile registered by any provider.
The **SACD** plugin is one such provider; another DSD decoder plugin works the
same way. If a DSD source has a target format in CodecSwitch, the pipeline
becomes:

```text
DST/DFF/DSF -> registered DSD provider PCM/FLAC -> CodecSwitch target encoder -> player
```

Details:

- For lossy targets, CodecSwitch asks the provider for raw PCM (when supported)
  and pipes it into the target encoder. This avoids an extra FLAC encode/decode.
- For FLAC targets, the provider's FLAC output is the final stream; no second
  encode is performed.
- For lossless non-FLAC targets (WAV/AIFF/ALAC), CodecSwitch uses PCM from
  the provider and encodes the target once.
- The player only receives the final target format.
- When a DSD source has a target mapping, the provider's Native/DoP output
  mode is bypassed. To keep Native/DoP, set `dff`/`dsf` to **Pass-through**.
- If no provider has registered a DSD profile, CodecSwitch falls back to its own
  FFmpeg DFF path when FFmpeg is available.

## Remote streams

Local files use the full native/FFmpeg toolchain. HTTP(S) streams get target
conversion only through FFmpeg; without FFmpeg they keep LMS's normal behavior.

## Architecture

```text
lib/Plugins/CodecSwitch/
├── Plugin.pm          # LMS entry point, client events, startup
├── Config.pm          # source/target tables and mapping decisions
├── Capabilities.pm    # provider priorities and external-profile discovery
├── Orchestrator.pm    # DSD PCM/FLAC path selection and bitrate helper
├── Toolchain.pm       # tool discovery, probing, backend selection
├── CommandBuilder.pm  # FFmpeg/native command templates
├── Profiles.pm        # per-player runtime commandTable profiles
├── Hooks.pm           # getConvertCommand2 wrapper
├── Settings.pm        # server settings page
└── PlayerSettings.pm  # per-player mapping page
```

Provider priority (smaller wins):

```text
unknown / legacy profiles  0   (keeps original systems working)
DSD provider (e.g. SACD)    50
FFmpeg plugin              100
CodecSwitch native         200
```

Existing non-CodecSwitch profiles win over CodecSwitch rules. CodecSwitch only
fills gaps and handles DSD composition.

`Profiles.pm` registers local profiles with an `F` capability and remote
profiles with an `R` capability (the remote profile uses the `-1` duplicate
instance suffix understood by LMS).

## Debug logging

`Settings → CodecSwitch → Debug logging` lets you set the log levels for:

- `plugin.codecswitch`
- `plugin.sacdplayer`
- `player.source` (LMS transcoding)
- `plugin.ffmpeg`

Levels are `OFF`, `FATAL`, `ERROR`, `WARN`, `INFO` and `DEBUG`. Changes are
applied immediately and persisted to the LMS logging configuration. Use
`DEBUG` only while diagnosing; it can create large log files.

## Development

```sh
make test          # unit tests, command generation, real FFmpeg pipeline
make dist          # installable dist/CodecSwitch
make verify-dist   # verify rendered manifest and modules
make bundle        # zip + tar.gz release archives
make smoke         # Docker 9.0.0 + 9.1.1 load/settings smoke test
```

The Docker smoke test only verifies that the server loads the plugin and serves
the settings page; it does not create a player or test player-side playback.

## Versioning and release

`VERSION` is the single source of truth. `install.xml.in` and `repo.xml.in`
contain `@VERSION@` / `@RELEASE_URL@` placeholders; `make dist` renders them
into `build/`.

## Limitations

- ALAC output is experimental; it uses fragmented MP4 for streaming.
- AIFF target is raw big-endian PCM with LMS stream format `aif`, not an AIFF
  container.
- AAC/ALAC and exotic source codecs need FFmpeg.
- Pass-through is not a guarantee of bit-perfect output when the player does
  not support the source codec.
- The optional LMS core patch is outside the plugin and must be re-applied after
  LMS upgrades.
