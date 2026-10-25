// ClipMaker — Geekatplay Studio · Vladimir Chopine
#import <Cocoa/Cocoa.h>
#import "app/MainWindow.h"
#include "platform/Platform.h"
#include "core/Segmenter.h"
#include "core/Beats.h"
#include <cstdio>
#include <cstring>

// Headless mode:
//   ClipMaker --cli --video a.mp4 [--video b.mp4] --idea "..." [--music m.mp3] [--out o.mp4]
//             [--provider heuristic|anthropic|ollama|openai] [--model m] [--key k] [--length 30] [--style bold|karaoke|minimal|outline|none]
//   ClipMaker --make-sample out.mp4 "narration text"
static int runCLI(int argc, const char** argv) {
    using namespace cm;
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (!strcmp(argv[1], "--make-sample") && argc >= 4) {
        std::string err;
        bool ok = makeSampleVideo(argv[2], argv[3], &err);
        printf(ok ? "sample written: %s\n" : "failed: %s\n", ok ? argv[2] : err.c_str());
        return ok ? 0 : 1;
    }
    if (!strcmp(argv[1], "--describe") && argc >= 3) {  // debug: Vision labels for an image / video frame
        for (int i = 2; i < argc; ++i) printf("%s: %s\n", argv[i], describeFrame(argv[i], probeMedia(argv[i]).isImage ? -1 : 2.0).c_str());
        return 0;
    }
    if (!strcmp(argv[1], "--frames") && argc >= 4) {   // debug: dump PNG frames of a video
        std::string err; int n = dumpFrames(argv[2], argv[3], &err);
        printf("%d frames written %s\n", n, err.c_str()); return n > 0 ? 0 : 1;
    }
    Settings s; std::vector<std::string> videos; std::string idea, out;
    for (int i = 2; i + 1 < argc; i += 2) {
        std::string k = argv[i], v = argv[i + 1];
        if (k == "--video") videos.push_back(v); else if (k == "--idea") idea = v; else if (k == "--music") s.musicPath = v;
        else if (k == "--out") out = v; else if (k == "--model") s.model = v; else if (k == "--key") s.apiKey = v;
        else if (k == "--length") { s.maxLength = atof(v.c_str()); s.minLength = s.maxLength * 0.6; }
        else if (k == "--min") s.minLength = atof(v.c_str()); else if (k == "--max") s.maxLength = atof(v.c_str());
        else if (k == "--image") videos.push_back(v); else if (k == "--clips") s.maxClips = atoi(v.c_str());
        else if (k == "--provider") s.provider = v == "anthropic" ? Settings::Anthropic : v == "ollama" ? Settings::Ollama : v == "openai" ? Settings::OpenAICompat : Settings::Heuristic;
        else if (k == "--style") s.captionStyle = v == "karaoke" ? CaptionStyle::Karaoke : v == "minimal" ? CaptionStyle::Minimal : v == "outline" ? CaptionStyle::Outline : v == "none" ? CaptionStyle::None : CaptionStyle::BoldPop;
        else { fprintf(stderr, "unknown arg %s\n", k.c_str()); return 2; }
    }
    if (videos.empty()) { fprintf(stderr, "need --video\n"); return 2; }
    if (s.apiKey.empty() && s.provider == Settings::Anthropic) if (const char* k = getenv("ANTHROPIC_API_KEY")) s.apiKey = k;
    if (out.empty()) out = outputDirectory() + "/short-cli.mp4";
    auto prog = [](double f, const std::string& m) { printf("[%3d%%] %s\n", int(f * 100), m.c_str()); fflush(stdout); };

    std::vector<MediaInfo> media; std::vector<Transcript> transcripts;
    for (auto& v : videos) {
        MediaInfo m = probeMedia(v);
        if (!m.ok) { fprintf(stderr, "cannot read %s: %s\n", v.c_str(), m.error.c_str()); return 1; }
        printf("source %s  %.1fs %dx%d%s\n", v.c_str(), m.duration, m.width, m.height, m.isImage ? " (image)" : "");
        Transcript t; std::string err;
        if (m.isImage) { media.push_back(m); transcripts.push_back(t); continue; }
        if (!loadTranscriptCache(v, t)) { t = transcribeFile(v, s.locale, prog, &err); if (!t.empty()) saveTranscriptCache(v, t); }
        if (t.empty()) { fprintf(stderr, "transcription failed: %s\n", err.c_str()); return 1; }
        for (auto& st : t.sentences) printf("  [%s - %s] %s\n", fmtTime(st.start).c_str(), fmtTime(st.end).c_str(), st.text.c_str());
        media.push_back(m); transcripts.push_back(t);
    }
    BeatGrid beats;
    if (!s.musicPath.empty()) {
        std::string err; auto pcm = decodeMonoPCM(s.musicPath, 22050, &err);
        beats = detectBeats(pcm, 22050);
        printf("music: %.1f BPM, %zu beats, %zu onsets %s\n", beats.bpm, beats.beats.size(), beats.onsets.size(), err.c_str());
    }
    std::vector<std::string> visuals(media.size());
    for (size_t i = 0; i < media.size(); ++i) if (media[i].isImage) { visuals[i] = describeFrame(media[i].path, -1); printf("image S%zu shows: %s\n", i, visuals[i].c_str()); }
    std::vector<Candidate> cands; std::string aiErr; Script script;
    if (s.provider != Settings::Heuristic) {
        prog(0, "Building the edit plan…");
        cands = aiSelectSegments(s, transcripts, media, visuals, idea, script, &aiErr);
        if (cands.empty()) printf("Engine failed (%s), falling back to offline ranking\n", aiErr.c_str());
    }
    if (cands.empty()) cands = heuristicCandidates(transcripts, media, idea, s);
    refineCandidates(cands, transcripts, media, s);
    for (auto& c : cands) {
        if (c.isImage) { c.visual = visuals[c.sourceIndex]; continue; }
        c.visual = describeFrame(media[c.sourceIndex].path, c.start + c.duration() / 2);
        if (s.smartReframe) trackSubject(c, media[c.sourceIndex].path);
        printf("cand S%d %s-%s score %.0f crop %.2f hook \"%s\" — %s\n", c.sourceIndex, fmtTime(c.start).c_str(), fmtTime(c.end).c_str(), c.score, c.cropCenterX, c.hook.c_str(), c.reason.c_str());
    }
    if (script.title.empty()) script = heuristicScript(cands, media, idea, s);
    if (script.narrative.empty()) script.narrative = describeScript(cands, media);
    printf("\n=== EDIT SCRIPT ===\n%s\n\n=== PUBLISH ===\n%s\n", describeScript(cands, media).c_str(), script.publishText().c_str());
    Project p = buildProject(cands, transcripts, media, s, beats);
    for (auto& k : p.clips) printf("clip %s-%s (%.2fs) %zu words\n", fmtTime(k.in).c_str(), fmtTime(k.out).c_str(), k.duration(), k.words.size());
    std::string err;
    if (!renderProject(p, out, prog, &err)) { fprintf(stderr, "render failed: %s\n", err.c_str()); return 1; }
    saveSidecar(out, script, describeScript(cands, media));
    printf("wrote %s (%.1fs) + sidecar .txt\n", out.c_str(), p.duration());
    return 0;
}

int main(int argc, const char** argv) {
    if (argc > 1 && (!strcmp(argv[1], "--cli") || !strcmp(argv[1], "--make-sample") || !strcmp(argv[1], "--frames") || !strcmp(argv[1], "--describe"))) {
        // Speech/AVFoundation deliver callbacks through the main run loop, so do the
        // work on a background thread and keep the main loop spinning.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ exit(runCLI(argc, argv)); });
        CFRunLoopRun();
        return 0;
    }
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        ClipMakerController* c = [[ClipMakerController alloc] init];
        app.delegate = c;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        [app run];
    }
    return 0;
}
