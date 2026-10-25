# Architecture

*ClipMaker by Geekatplay Studio · Vladimir Chopine*

ClipMaker is a single macOS app bundle with two layers:

```
src/core        pure C++20 — no Apple headers except Accelerate in Beats.cpp
  Model.h       data model: Transcript/Word, MediaInfo, BeatGrid, Candidate, Clip, Project, Settings, Script
  Transcript.cpp word-boundary snapping, text extraction, formatting helpers
  Beats.cpp     onset strength (spectral flux, vDSP FFT) → autocorrelation tempo (60–190 BPM, prior at 120)
                → phase fit → beat grid + onsets
  Segmenter.cpp offline candidate ranking, LLM prompt builders, candidate refinement
                (word snapping, length clamps, overlap removal), heuristic script/publish copy,
                buildProject(): min/max length fitting + beat-snapped timeline

src/platform    Objective-C++ — Apple frameworks behind a C++ interface (Platform.h)
  Media.mm      probe (video/image), PCM decode, transcript cache (~/Library/Caches/ClipMaker),
                image→video slide conversion (cached), publish sidecar, synthetic sample generator
  Speech.mm     SFSpeechRecognizer: on-device when available, chunked, idle-timeout completion,
                server fallback, word timings → sentences
  Vision.mm     face/saliency subject centre, piecewise subject tracking, VNClassifyImage frame labels,
                frame dumper
  AI.mm         NSURLSession JSON clients for the Claude Messages API, Ollama /api/chat, OpenAI chat
                completions; parses the edit plan JSON (clips, overlays, title, description, hashtags)
  Render.mm     AVMutableComposition (video + voice + music), per-clip transform ramps
                (reframe pan, Ken Burns, slide motion), AVMutableAudioMix (gain, fade),
                Core Animation overlay with Core Text–rasterised captions (4 styles), AVAssetExportSession

src/app         AppKit UI
  main.mm       GUI entry + headless CLI (--cli, --make-sample, --frames, --describe)
  MainWindow.mm window, controls, analysis/generate pipelines on a background queue,
                Edit-plan sheet (script / transcript / publish), screenshot tour for docs
  TimelineView.mm clip + beat strip
```

## Data flow

1. `probeMedia` → `MediaInfo` per source (images flagged `isImage`).
2. Videos: `transcribeFile` (or cache) → `Transcript` with word timings.
   Images: `describeFrame(path, -1)` → label string.
3. Music: `decodeMonoPCM` → `detectBeats` → `BeatGrid`.
4. Selection: `aiSelectSegments` (prompt = brief + constraints + sources + transcript) → `Candidate[]` + `Script`;
   on failure `heuristicCandidates` + `heuristicScript`.
5. `refineCandidates` snaps to word boundaries, clamps lengths, drops overlaps; `describeFrame` and
   `trackSubject` annotate each candidate.
6. User approves/edits → `buildProject` picks clips within [min,max], snaps cut points to beats,
   attaches words for captions → `Project`.
7. `renderProject` builds the composition and exports; `saveSidecar` writes the publish text.

## Why these choices

- **AVFoundation instead of ffmpeg**: hardware decode/encode, zero dependencies, 400 KB binary,
  and the compositor handles per-clip transform ramps natively.
- **Captions as bitmaps**: `CATextLayer` does not draw in the offline AVFoundation renderer on
  recent macOS, and Core Text rasterisation gives exact stroke/shadow control anyway.
- **Whole-timeline opacity keyframes**: the offline renderer applies a not-yet-started animation's
  first value, so every visibility animation spans 0…total with explicit 0/1 keyframes.
- **Speech chunking + idle timeout**: on-device recognition never flags `isFinal` reliably; partial
  results plus a 6 s idle window give deterministic completion, with server fallback.
- **TCC attribution**: launching the bare binary from a terminal makes the terminal the responsible
  process; the CLI must go through `open` so the bundle's usage description applies.
