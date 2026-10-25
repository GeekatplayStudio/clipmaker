#include "platform/Platform.h"
#include "platform/Common.h"
#import <Speech/Speech.h>

namespace cm {

static bool ensureSpeechAuth(std::string* err) {
    __block SFSpeechRecognizerAuthorizationStatus st = [SFSpeechRecognizer authorizationStatus];
    if (st == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus s) { st = s; dispatch_semaphore_signal(sem); }];
        // The system prompt may be waiting for the user; give them time but never hang forever.
        if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(180 * NSEC_PER_SEC)))) {
            if (err) *err = "Speech Recognition permission prompt not answered (System Settings → Privacy & Security → Speech Recognition)";
            return false;
        }
    }
    if (st != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        if (err) *err = "Speech recognition not authorized (System Settings → Privacy & Security → Speech Recognition)";
        return false;
    }
    return true;
}

// Export [start, start+len] of the asset's audio to a temporary m4a.
static NSString* exportChunk(AVAsset* asset, double start, double len, int idx, std::string* err) {
    NSString* p = [NSTemporaryDirectory() stringByAppendingFormat:@"clipmaker_chunk_%d_%d.m4a", getpid(), idx];
    [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
    AVAssetExportSession* ex = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    ex.outputURL = [NSURL fileURLWithPath:p];
    ex.outputFileType = AVFileTypeAppleM4A;
    ex.timeRange = CMTimeRangeMake(secs(start), secs(len));
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [ex exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
    if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_SEC)))) {
        [ex cancelExport]; if (err) *err = "Audio chunk export timed out"; return nil;
    }
    if (ex.status != AVAssetExportSessionStatusCompleted) {
        if (err) *err = str(ex.error.localizedDescription ?: @"chunk export failed");
        return nil;
    }
    return p;
}

static void appendWords(Transcript& t, const std::vector<Word>& words) {
    // Sentence grouping: gap > 0.7 s, terminal punctuation, or 14 words.
    Sentence cur;
    auto flush = [&] {
        if (cur.words.empty()) return;
        cur.start = cur.words.front().start; cur.end = cur.words.back().end;
        cur.text.clear();
        for (auto& w : cur.words) { if (!cur.text.empty()) cur.text += ' '; cur.text += w.text; }
        t.sentences.push_back(cur); cur = Sentence{};
    };
    for (auto& w : words) {
        if (!cur.words.empty()) {
            const std::string& prev = cur.words.back().text;
            char last = prev.empty() ? ' ' : prev.back();
            bool punct = last == '.' || last == '?' || last == '!';
            if (w.start - cur.words.back().end > 0.7 || punct || cur.words.size() >= 14) flush();
        }
        cur.words.push_back(w);
    }
    flush();
}

Transcript transcribeFile(const std::string& path, const std::string& locale, const Progress& progress, std::string* err) {
    Transcript t;
    @autoreleasepool {
        if (progress) progress(0, "Checking speech permission…");
        if (!ensureSpeechAuth(err)) return t;
        SFSpeechRecognizer* rec = [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:ns(locale)]];
        if (!rec || !rec.isAvailable) { if (err) *err = "Speech recognizer unavailable for locale " + locale; return t; }
        bool onDevice = rec.supportsOnDeviceRecognition;

        AVURLAsset* asset = loadAsset(path);
        if (!firstTrack(asset, AVMediaTypeAudio)) { if (err) *err = "File has no audio track"; return t; }
        double total = CMTimeGetSeconds(asset.duration);
        t.duration = total;
        const double CH = onDevice ? 120.0 : 55.0;   // server recognition caps at ~1 min
        int n = std::max(1, int(ceil(total / CH)));
        std::vector<Word> all;
        for (int i = 0; i < n; ++i) {
            double start = i * CH, len = std::min(CH, total - start);
            if (len < 0.3) break;
            if (progress) progress(double(i) / n, "Transcribing " + fmtTime(start) + " / " + fmtTime(total) + (onDevice ? " (on-device)" : ""));
            NSString* chunk = exportChunk(asset, start, len, i, err);
            if (!chunk) return t;

            // Try on-device first; fall back to server recognition if it yields nothing.
            SFSpeechRecognitionResult* finalResult = nil; NSError* rerr = nil;
            for (int attempt = 0; attempt < 2 && !finalResult; ++attempt) {
                bool useOnDevice = onDevice && attempt == 0;
                if (!useOnDevice && !onDevice && attempt == 1) break;
                SFSpeechURLRecognitionRequest* req = [[SFSpeechURLRecognitionRequest alloc] initWithURL:[NSURL fileURLWithPath:chunk]];
                req.shouldReportPartialResults = YES;   // on-device may never flag isFinal; we detect idle instead
                req.taskHint = SFSpeechRecognitionTaskHintDictation;
                if (@available(macOS 13.0, *)) req.addsPunctuation = YES;
                req.requiresOnDeviceRecognition = useOnDevice;

                __block SFSpeechRecognitionResult* latest = nil;
                __block NSError* e2 = nil;
                __block bool done = false;
                __block double lastUpdate = CFAbsoluteTimeGetCurrent();
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                SFSpeechRecognitionTask* task = [rec recognitionTaskWithRequest:req resultHandler:^(SFSpeechRecognitionResult* r, NSError* e) {
                    if (r) { latest = r; lastUpdate = CFAbsoluteTimeGetCurrent(); }
                    if (e) e2 = e;
                    if (e || (r && r.isFinal)) { done = true; dispatch_semaphore_signal(sem); }
                }];
                double began = CFAbsoluteTimeGetCurrent(), maxWait = 30 + len * 2;
                while (!done) {
                    if (!dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)))) break;
                    double now = CFAbsoluteTimeGetCurrent();
                    if (latest && now - lastUpdate > 6.0) break;          // results stopped arriving: treat as final
                    if (now - began > maxWait) break;
                }
                [task finish];
                if (e2) fprintf(stderr, "speech[%s]: %s\n", useOnDevice ? "on-device" : "server", e2.localizedDescription.UTF8String);
                if (e2 && !latest && !(e2.code == 1110 || [e2.localizedDescription containsString:@"No speech"])) rerr = e2;
                finalResult = latest;
                if (!finalResult && useOnDevice && progress) progress(double(i) / n, "On-device recogniser silent, retrying via server…");
            }
            [[NSFileManager defaultManager] removeItemAtPath:chunk error:nil];
            if (rerr && !finalResult) {
                if (err) *err = str(rerr.localizedDescription);
                if (all.empty()) return t;
                break;
            }
            if (!finalResult) continue;
            for (SFTranscriptionSegment* s in finalResult.bestTranscription.segments) {
                Word w; w.start = start + s.timestamp; w.end = start + s.timestamp + std::max(0.05, s.duration);
                w.text = str(s.substring);
                if (!w.text.empty()) all.push_back(w);
            }
        }
        appendWords(t, all);
        if (progress) progress(1.0, "Transcribed " + std::to_string(all.size()) + " words");
    }
    return t;
}

} // namespace cm
