#include "platform/Platform.h"
#include "platform/Common.h"
#import <AppKit/AppKit.h>
#import <CoreMedia/CoreMedia.h>
#include <CommonCrypto/CommonDigest.h>

namespace cm {

static bool isImagePath(const std::string& path) {
    NSString* ext = [ns(path).pathExtension lowercaseString];
    return [@[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"tif", @"tiff", @"gif", @"bmp", @"webp"] containsObject:ext];
}

static CGImageRef loadImage(const std::string& path, int maxSide) {   // caller releases
    NSURL* u = fileURL(path);
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)u, nullptr);
    if (!src) return nullptr;
    NSDictionary* opt = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                          (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                          (id)kCGImageSourceThumbnailMaxPixelSize: @(maxSide)};
    CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
    CFRelease(src);
    return img;
}

MediaInfo probeMedia(const std::string& path) {
    MediaInfo m; m.path = path;
    if (isImagePath(path)) {
        @autoreleasepool {
            CGImageRef img = loadImage(path, 4096);
            if (!img) { m.error = "Cannot decode image"; return m; }
            m.width = (int)CGImageGetWidth(img); m.height = (int)CGImageGetHeight(img);
            CGImageRelease(img);
            m.isImage = true; m.hasVideo = true; m.ok = true; m.duration = 0;
        }
        return m;
    }
    @autoreleasepool {
        AVURLAsset* a = loadAsset(path);
        NSError* e = nil;
        if ([a statusOfValueForKey:@"tracks" error:&e] != AVKeyValueStatusLoaded) {
            m.error = e ? str(e.localizedDescription) : "Cannot read file"; return m;
        }
        m.duration = CMTimeGetSeconds(a.duration);
        if (AVAssetTrack* v = firstTrack(a, AVMediaTypeVideo)) {
            CGRect r = CGRectApplyAffineTransform(CGRectMake(0, 0, v.naturalSize.width, v.naturalSize.height), v.preferredTransform);
            m.width = (int)fabs(r.size.width); m.height = (int)fabs(r.size.height);
            m.fps = v.nominalFrameRate > 0 ? v.nominalFrameRate : 30; m.hasVideo = true;
        }
        m.hasAudio = firstTrack(a, AVMediaTypeAudio) != nil;
        m.ok = m.duration > 0 && (m.hasVideo || m.hasAudio);
        if (!m.ok && m.error.empty()) m.error = "No playable tracks";
    }
    return m;
}

std::vector<float> decodeMonoPCM(const std::string& path, int sr, std::string* err) {
    std::vector<float> out;
    @autoreleasepool {
        AVURLAsset* a = loadAsset(path);
        AVAssetTrack* t = firstTrack(a, AVMediaTypeAudio);
        if (!t) { if (err) *err = "No audio track"; return out; }
        NSError* e = nil;
        AVAssetReader* r = [[AVAssetReader alloc] initWithAsset:a error:&e];
        if (!r) { if (err) *err = str(e.localizedDescription); return out; }
        NSDictionary* fmt = @{AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(sr),
                              AVNumberOfChannelsKey: @1, AVLinearPCMBitDepthKey: @32,
                              AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsNonInterleaved: @NO,
                              AVLinearPCMIsBigEndianKey: @NO};
        AVAssetReaderTrackOutput* o = [[AVAssetReaderTrackOutput alloc] initWithTrack:t outputSettings:fmt];
        o.alwaysCopiesSampleData = NO;
        [r addOutput:o];
        if (![r startReading]) { if (err) *err = str(r.error.localizedDescription); return out; }
        out.reserve((size_t)(CMTimeGetSeconds(a.duration) * sr) + sr);
        while (CMSampleBufferRef sb = [o copyNextSampleBuffer]) {
            if (CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb)) {
                size_t n = CMBlockBufferGetDataLength(bb), old = out.size();
                out.resize(old + n / sizeof(float));
                CMBlockBufferCopyDataBytes(bb, 0, n, out.data() + old);
            }
            CFRelease(sb);
        }
        if (r.status == AVAssetReaderStatusFailed && err) *err = str(r.error.localizedDescription);
    }
    return out;
}

// ---------- transcript cache ----------
static std::string cacheKey(const std::string& mediaPath) {
    NSDictionary* attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:ns(mediaPath) error:nil];
    NSString* s = [NSString stringWithFormat:@"%@|%@|%@", ns(mediaPath), attrs[NSFileSize], attrs[NSFileModificationDate]];
    unsigned char d[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(s.UTF8String, (CC_LONG)strlen(s.UTF8String), d);
    char hex[2 * CC_SHA1_DIGEST_LENGTH + 1];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; ++i) snprintf(hex + 2 * i, 3, "%02x", d[i]);
    return hex;
}
static NSString* cacheDir() {
    NSString* d = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0]
                   stringByAppendingPathComponent:@"ClipMaker"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSString* cachePath(const std::string& mediaPath) {
    return [cacheDir() stringByAppendingPathComponent:[ns(cacheKey(mediaPath)) stringByAppendingString:@".json"]];
}

bool loadTranscriptCache(const std::string& mediaPath, Transcript& out) {
    @autoreleasepool {
        NSData* d = [NSData dataWithContentsOfFile:cachePath(mediaPath)];
        if (!d) return false;
        NSDictionary* j = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        if (![j isKindOfClass:NSDictionary.class]) return false;
        out = Transcript{};
        out.duration = [j[@"duration"] doubleValue];
        for (NSDictionary* s in j[@"sentences"]) {
            Sentence st; st.start = [s[@"start"] doubleValue]; st.end = [s[@"end"] doubleValue]; st.text = str(s[@"text"]);
            for (NSDictionary* w in s[@"words"]) st.words.push_back({[w[@"s"] doubleValue], [w[@"e"] doubleValue], str(w[@"t"])});
            out.sentences.push_back(st);
        }
        return true;
    }
}

void saveTranscriptCache(const std::string& mediaPath, const Transcript& t) {
    @autoreleasepool {
        NSMutableArray* sents = [NSMutableArray array];
        for (auto& s : t.sentences) {
            NSMutableArray* words = [NSMutableArray array];
            for (auto& w : s.words) [words addObject:@{@"s": @(w.start), @"e": @(w.end), @"t": ns(w.text)}];
            [sents addObject:@{@"start": @(s.start), @"end": @(s.end), @"text": ns(s.text), @"words": words}];
        }
        NSData* d = [NSJSONSerialization dataWithJSONObject:@{@"duration": @(t.duration), @"sentences": sents} options:0 error:nil];
        [d writeToFile:cachePath(mediaPath) atomically:YES];
    }
}

std::string outputDirectory() {
    NSString* d = [NSSearchPathForDirectoriesInDomains(NSMoviesDirectory, NSUserDomainMask, YES)[0]
                   stringByAppendingPathComponent:@"ClipMaker"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return str(d);
}

std::string imageToVideo(const std::string& imagePath, double seconds, std::string* err) {
    @autoreleasepool {
        NSString* out = [cacheDir() stringByAppendingFormat:@"/img_%s_%d.mp4", cacheKey(imagePath).c_str(), int(seconds)];
        if ([[NSFileManager defaultManager] fileExistsAtPath:out]) return str(out);
        CGImageRef img = loadImage(imagePath, 1920);
        if (!img) { if (err) *err = "Cannot decode " + imagePath; return ""; }
        int W = (int)CGImageGetWidth(img) & ~1, H = (int)CGImageGetHeight(img) & ~1;
        NSError* e = nil;
        AVAssetWriter* w = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:out] fileType:AVFileTypeMPEG4 error:&e];
        if (!w) { CGImageRelease(img); if (err) *err = str(e.localizedDescription); return ""; }
        AVAssetWriterInput* in = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
            outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(W), AVVideoHeightKey: @(H),
                             AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(12000000)}}];
        AVAssetWriterInputPixelBufferAdaptor* ad = [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:in
            sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                          (id)kCVPixelBufferWidthKey: @(W), (id)kCVPixelBufferHeightKey: @(H)}];
        [w addInput:in]; [w startWriting]; [w startSessionAtSourceTime:kCMTimeZero];
        CVPixelBufferRef pb = nullptr;
        CVPixelBufferPoolCreatePixelBuffer(nullptr, ad.pixelBufferPool, &pb);
        if (pb) {
            CVPixelBufferLockBaseAddress(pb, 0);
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGContextRef c = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), W, H, 8, CVPixelBufferGetBytesPerRow(pb), cs,
                                                   (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | (CGBitmapInfo)kCGBitmapByteOrder32Little);
            CGContextDrawImage(c, CGRectMake(0, 0, W, H), img);
            CGContextRelease(c); CGColorSpaceRelease(cs);
            CVPixelBufferUnlockBaseAddress(pb, 0);
            // a few keyframes are enough: 2 fps, identical frames
            int frames = int(seconds * 2) + 2;
            for (int f = 0; f < frames; ++f) {
                while (!in.readyForMoreMediaData) usleep(2000);
                [ad appendPixelBuffer:pb withPresentationTime:CMTimeMake(f, 2)];
            }
            CVPixelBufferRelease(pb);
        }
        CGImageRelease(img);
        [in markAsFinished];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [w finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (w.status != AVAssetWriterStatusCompleted) { if (err) *err = str(w.error.localizedDescription); return ""; }
        return str(out);
    }
}

void saveSidecar(const std::string& videoPath, const Script& script, const std::string& narrative) {
    std::string txt = script.publishText() + "\nEDIT SCRIPT\n" + narrative + "\n";
    NSString* p = [[ns(videoPath) stringByDeletingPathExtension] stringByAppendingString:@".txt"];
    [ns(txt) writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ---------- sample generator (for testing without any footage) ----------
bool makeSampleVideo(const std::string& outPath, const std::string& script, std::string* err) {
    @autoreleasepool {
        NSString* tmp = NSTemporaryDirectory();
        NSString* aiff = [tmp stringByAppendingPathComponent:@"clipmaker_sample.aiff"];
        NSString* mov  = [tmp stringByAppendingPathComponent:@"clipmaker_sample_video.mov"];
        [[NSFileManager defaultManager] removeItemAtPath:aiff error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:mov error:nil];
        NSTask* say = [[NSTask alloc] init];
        say.executableURL = [NSURL fileURLWithPath:@"/usr/bin/say"];
        say.arguments = @[@"-o", aiff, ns(script)];
        NSError* e = nil;
        if (![say launchAndReturnError:&e]) { if (err) *err = str(e.localizedDescription); return false; }
        [say waitUntilExit];
        AVURLAsset* audio = loadAsset(str(aiff));
        double dur = CMTimeGetSeconds(audio.duration) + 0.5;
        if (dur < 1) { if (err) *err = "TTS failed"; return false; }

        const int W = 1280, H = 720, FPS = 30;
        AVAssetWriter* w = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:mov] fileType:AVFileTypeQuickTimeMovie error:&e];
        if (!w) { if (err) *err = str(e.localizedDescription); return false; }
        AVAssetWriterInput* in = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
            outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(W), AVVideoHeightKey: @(H)}];
        AVAssetWriterInputPixelBufferAdaptor* ad = [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:in
            sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                          (id)kCVPixelBufferWidthKey: @(W), (id)kCVPixelBufferHeightKey: @(H)}];
        [w addInput:in];
        [w startWriting]; [w startSessionAtSourceTime:kCMTimeZero];
        int frames = int(dur * FPS);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        for (int f = 0; f < frames; ++f) {
            while (!in.readyForMoreMediaData) usleep(2000);
            CVPixelBufferRef pb = nullptr;
            CVPixelBufferPoolCreatePixelBuffer(nullptr, ad.pixelBufferPool, &pb);
            if (!pb) continue;
            CVPixelBufferLockBaseAddress(pb, 0);
            CGContextRef c = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pb), W, H, 8, CVPixelBufferGetBytesPerRow(pb), cs,
                                                   (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | (CGBitmapInfo)kCGBitmapByteOrder32Little);
            double t = double(f) / FPS;
            CGContextSetRGBFillColor(c, 0.08, 0.09, 0.14, 1); CGContextFillRect(c, CGRectMake(0, 0, W, H));
            // "subject" drifting left-right so smart reframe has something to follow
            double cx = W * (0.5 + 0.3 * sin(t * 0.35));
            CGContextSetRGBFillColor(c, 0.95, 0.75, 0.55, 1);
            CGContextFillEllipseInRect(c, CGRectMake(cx - 110, 250, 220, 260));
            CGContextSetRGBFillColor(c, 0.2, 0.45, 0.9, 1);
            CGContextFillRect(c, CGRectMake(cx - 170, 40, 340, 230));
            // timecode bar
            CGContextSetRGBFillColor(c, 1, 1, 1, 0.9);
            CGContextFillRect(c, CGRectMake(40, H - 60, (W - 80) * (t / dur), 12));
            CGContextRelease(c);
            CVPixelBufferUnlockBaseAddress(pb, 0);
            [ad appendPixelBuffer:pb withPresentationTime:CMTimeMake(f, FPS)];
            CVPixelBufferRelease(pb);
        }
        CGColorSpaceRelease(cs);
        [in markAsFinished];
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [w finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        if (w.status != AVAssetWriterStatusCompleted) { if (err) *err = str(w.error.localizedDescription); return false; }

        // mux narration + video → mp4
        AVMutableComposition* comp = [AVMutableComposition composition];
        AVURLAsset* video = loadAsset(str(mov));
        AVMutableCompositionTrack* vt = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        AVMutableCompositionTrack* at = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        [vt insertTimeRange:CMTimeRangeMake(kCMTimeZero, video.duration) ofTrack:firstTrack(video, AVMediaTypeVideo) atTime:kCMTimeZero error:nil];
        [at insertTimeRange:CMTimeRangeMake(kCMTimeZero, audio.duration) ofTrack:firstTrack(audio, AVMediaTypeAudio) atTime:kCMTimeZero error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:ns(outPath) error:nil];
        AVAssetExportSession* ex = [[AVAssetExportSession alloc] initWithAsset:comp presetName:AVAssetExportPreset1280x720];
        ex.outputURL = fileURL(outPath); ex.outputFileType = AVFileTypeMPEG4;
        dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
        [ex exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sem2); }];
        dispatch_semaphore_wait(sem2, DISPATCH_TIME_FOREVER);
        if (ex.status != AVAssetExportSessionStatusCompleted) { if (err) *err = str(ex.error.localizedDescription); return false; }
        return true;
    }
}

} // namespace cm
