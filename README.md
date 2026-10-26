# CodecSwitch for Lyrion Music Server

[中文说明](README.zh-CN.md)

`CodecSwitch` gives each player its own source-codec policy. For every source
codec you can choose:

- **Pass-through** — the plugin does not force a target; LMS plays the original
  stream when the player supports it and keeps its normal fallback otherwise.
- **Skip** — remove tracks of that codec from the current player queue when
  they are reached.
- **Convert to a target codec** — FLAC, WAV, AIFF/raw PCM, MP3, AAC, Ogg
  Vorbis, Opus or ALAC (ALAC is experimental).

The plugin does not patch LMS files. It registers per-player
`Slim::Player::TranscodingHelper` profiles at runtime and wraps
`getConvertCommand2` only while the plugin is active.

Tested with the official Docker images `lmscommunity/lyrionmusicserver:9.0.0`
and `:9.1.1`.

## Requirements

- Lyrion Music Server **9.0+** (tested with 9.0.0 and 9.1.1).
- The LMS image already contains `flac`, `sox` and `lame`; 9.1.1 also contains
  `opusenc`. Those tools cover FLAC, WAV, AIFF/raw PCM, MP3, Ogg Vorbis and
  Opus without extra packages.
- **FFmpeg is optional but recommended.** It is required for AAC, ALAC, most
  exotic source formats (WMA/APE/MPC/M4A/ALAC/DSD), and remote-stream target
  conversion. The official LMS image does not include FFmpeg.
- `flock` (util-linux) is needed only for the optional worker limit on Unix.

## Install

Build the installable folder:

```sh
make dist
```

Copy `dist/CodecSwitch` to the LMS plugin directory and restart LMS.

For the official Docker image the third-party plugin directory is
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

- **Transcoding workers** — maximum number of encoder processes running at the
  same time. `0` means unlimited (LMS default). On Unix this is enforced with a
  small `flock` gate shipped in `Bin/codecswitch-gate`; on Windows the limit is
  unavailable. Native pipelines gate the final encoder process.
- **Tool paths** — optional absolute paths for `ffmpeg`, `flac`, `lame`, `sox`
  and `opusenc`. Empty means auto-detect from the LMS `Bin` directory/PATH.
- **Encoder backends** — for FLAC, WAV, AIFF, MP3, Ogg Vorbis and Opus choose
  `Auto`, `FFmpeg` or `Native helper`. `Auto` prefers the LMS helper tools and
  falls back to FFmpeg. AAC and ALAC always use FFmpeg.

Changes are applied immediately; no LMS restart is needed.

## Player settings

The player page lists every known source codec with the available actions.
Targets are only offered when the player reports the matching LMS format and
the encoder is available. If a player reports no formats, only pass-through and
skip are shown.

Default: every source is pass-through.

### Skip semantics

When a skipped track reaches `playlist newsong`, the plugin issues
`playlist deleteitem` for it, which makes LMS advance to the next track. It also
removes up to five upcoming skipped tracks so they are not preloaded. This
changes only the current player queue — not the music library, saved playlists,
or other players.

### Direct / pass-through semantics

Pass-through means "the plugin does not force a target codec". If the player
supports the source codec, LMS streams it directly. If not, LMS's existing
fallback rules still apply.

## Target formats

| Target | LMS format | FFmpeg encoder | Native path | Notes |
|---|---|---|---|---|
| FLAC | `flc` | `flac` | SoX decode → `flac` | lossless |
| WAV | `wav` | `pcm_s16le` | SoX | 16-bit PCM WAV container |
| AIFF | `aif` | `pcm_s16be` | SoX raw big-endian | LMS `aif` stream is raw PCM, matching core `flc→aif` |
| MP3 | `mp3` | `libmp3lame` | SoX decode → `lame` | lossy |
| AAC | `aac` | `aac` | none | ADTS; FFmpeg required |
| Ogg Vorbis | `ogg` | `libvorbis` | SoX | lossy |
| Opus | `ops` | `libopus` | SoX decode → `opusenc` | Ogg Opus |
| ALAC | `alc` | `alac` | none | experimental, fragmented MP4 |

The target must be in the player's reported formats. For example, a player that
reports `pcm` but not `wav` will not be offered WAV; it can still receive FLAC,
MP3, Ogg Vorbis or AIFF if it reports those formats.

## Remote streams

Local files use the full native/FFmpeg toolchain. HTTP(S) streams get target
conversion only through FFmpeg; without FFmpeg they keep LMS's normal behavior.
Skip works for both local and remote tracks.

## Architecture

```text
lib/Plugins/CodecSwitch/
├── Plugin.pm          # LMS entry point, client events, startup
├── Config.pm          # source/target tables and mapping decisions
├── Toolchain.pm       # tool discovery, probing, backend selection
├── CommandBuilder.pm  # FFmpeg/native command templates
├── Profiles.pm        # per-player runtime commandTable profiles
├── Hooks.pm           # getConvertCommand2 wrapper
├── Skip.pm            # playlist newsong skip handler
├── Settings.pm        # server settings page
└── PlayerSettings.pm  # per-player mapping page
```

`Profiles.pm` registers local profiles with an `F` capability and remote
profiles with an `R` capability (the remote profile uses the `-1` duplicate
instance suffix understood by LMS). Existing profiles with the same exact key
are saved and restored when the plugin refreshes/removes its rules.

## Development

```sh
make test          # unit tests, command generation, real FFmpeg pipeline, gate
make dist          # installable dist/CodecSwitch
make verify-dist   # verify rendered manifest and modules
make bundle        # zip + tar.gz release archives
make smoke         # Docker 9.0.0 + 9.1.1 load/settings smoke test
```

The unit tests include a real FFmpeg pipeline test for every target and a
concurrency test for the worker gate. The Docker smoke test only verifies that
the server loads the plugin and serves the settings page; it does not create a
player or test player-side playback.

## Versioning and release

`VERSION` is the single source of truth. `install.xml.in` and `repo.xml.in`
contain `@VERSION@` / `@RELEASE_URL@` placeholders; `make dist` renders them
into `build/`. Override the catalog base with:

```sh
make bundle RELEASE_BASE=https://example.test/releases/download
```

## Limitations

- ALAC output is experimental; it uses fragmented MP4 for streaming.
- AIFF target is raw big-endian PCM with LMS stream format `aif`, not an AIFF
  container. This is intentional and matches LMS core's `flc→aif` rule.
- AAC/ALAC and exotic source codecs need FFmpeg.
- The worker limit relies on `flock`; it is not available on Windows.
- Pass-through is not a guarantee of bit-perfect output when the player does
  not support the source codec.
- The plugin does not modify LMS core files and does not handle player-side
  decoding.
