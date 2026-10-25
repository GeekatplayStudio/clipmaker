<p align="center">
  <img src="docs/pipeline.svg" alt="ClipMaker pipeline" width="100%">
</p>

# ClipMaker

**Shorts editor for macOS by [Geekatplay Studio](https://www.geekatplay.com) — compact, native, fast.**
Drop long videos (and photos), describe the short you want, and ClipMaker
transcribes on-device, has a language model pick and order the best moments,
shows you the edit plan for approval, and renders a 9:16 short with subject-tracking
reframe, beat-synced cuts, animated captions, music and ready-to-paste
title/description/hashtags.

C++20 core + Objective-C++ on AVFoundation, Speech, Vision and Accelerate.
No ffmpeg, no Electron, no third-party libraries. ~400 KB binary.

> 📖 **[User manual](docs/MANUAL.md)** · 🏗 **[Architecture](docs/ARCHITECTURE.md)** · 🎬 **[Sample outputs](samples/)**

## How it works

| 1 · Add media & describe the short | 2 · Analyze → review the edit plan |
|---|---|
| ![Sources](docs/img/02-sources-preview.png) | ![Edit plan](docs/img/03-edit-plan-script.png) |
| Videos and images (slides with pan/zoom), a music track, your brief, the engine and output settings. Click any source to preview it. | Transcription (on-device, cached), frame descriptions, beat detection, then the engine proposes ordered moments with hooks, overlays and a rationale. |

| 3 · Transcript, frames, publish copy | 4 · Generate |
|---|---|
| ![Transcript](docs/img/04-transcript-frames.png) | ![Generated](docs/img/07-generated.png) |
| Full timestamped transcript, what each segment and image shows, and editable title · description · hashtags with one-click copy. | 1080×1920 H.264 with smart reframe, beat-snapped cuts, captions, hook title, ducked music — plus a `.txt` with the publish text. |

## Features

- **Transcript-driven selection** — on-device Speech with word timings; cuts snap to word boundaries.
- **Engines** — Claude API (`claude-sonnet-5-5`), local Ollama, any OpenAI-compatible endpoint, or an offline ranker (also the automatic fallback).
- **Edit plan for approval** — rationale, ordered cut list, transcript with frame descriptions, generated title/description/hashtags. Approve, tweak, or re-run.
- **Images as slides** — photos become pan-and-zoom slides placed where they support the narration, with short overlay text.
- **Smart 9:16 reframe** — Vision faces/saliency tracked across each clip; smooth pan plus optional push-in.
- **Beat sync** — tempo and phase detected from your music; the short starts on a downbeat and every cut lands on a beat; music ducked under voice with fade-out.
- **Captions with effects** — Bold pop, Karaoke word highlight, Minimal pill, Outline; font, size, five vertical positions for captions and for the hook title.
- **Length window** — min/max seconds; the planner fills to the minimum and never exceeds the maximum.
- **Headless CLI** — same engine from scripts.

## Build

macOS 13+, Command Line Tools (or Xcode), CMake ≥ 3.20.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
open build/ClipMaker.app
```

First *Analyze* asks for Speech Recognition permission (and again after each
rebuild, since the ad-hoc signature changes). The CMake file auto-selects the
newest SDK the installed linker can read; override with `-DCMAKE_OSX_SYSROOT=`.

## Quick start

1. **Add media** (button, ⌘O, drag-and-drop) — videos and images. Click a row to preview.
2. **Describe the short** — audience, tone, what to include, the call to action.
3. **Music** (optional) — pick a track, set level, keep *Sync cuts to beats* on.
4. **Engine** — Claude API (key or `ANTHROPIC_API_KEY`), Ollama (`ollama serve` + model name), OpenAI-compatible, or offline.
5. **Analyze** (⌘A) → the **Edit plan** sheet opens: read the script, check the transcript, edit the publish text.
6. **Approve & Generate** → `~/Movies/ClipMaker/short-<date>.mp4` + `.txt`.

Full details, settings reference, CLI options and troubleshooting: **[docs/MANUAL.md](docs/MANUAL.md)**.

## Headless

```bash
open -W --stdout out.log --stderr out.log build/ClipMaker.app --args --cli \
  --video talk.mp4 --image cover.jpg --idea "best moments about pricing" \
  --music beat.mp3 --provider anthropic --min 25 --max 40 --clips 3 \
  --style karaoke --out short.mp4
```

`--make-sample out.mp4 "narration"` creates a narrated test video with the
system voice so you can try the pipeline without footage. `samples/` contains
such a source, a 118 BPM test track, and finished shorts made from them.

## Layout

```
src/core       C++: model, transcript utils, beat detector, segmenter / planner
src/platform   Objective-C++: media, speech, vision, model clients, renderer
src/app        AppKit UI + CLI entry
docs/          manual, architecture, screenshots, pipeline diagram
samples/       test source, music, demo outputs
```

## Author

**Vladimir Chopine** — [Geekatplay Studio](https://www.geekatplay.com), 3D tutorials and digital art training.

## License

MIT — see [LICENSE](LICENSE).
