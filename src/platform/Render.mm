#include "platform/Platform.h"
#include "platform/Common.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <algorithm>
#include <cmath>

namespace cm {

// ---------------------------------------------------------------- transforms
struct Geometry { double sw, sh; CGAffineTransform norm; };

static Geometry geometryFor(AVAssetTrack* v) {
    CGAffineTransform pt = v.preferredTransform;
    CGRect r = CGRectApplyAffineTransform(CGRectMake(0, 0, v.naturalSize.width, v.naturalSize.height), pt);
    Geometry g; g.sw = fabs(r.size.width); g.sh = fabs(r.size.height);
    g.norm = CGAffineTransformConcat(pt, CGAffineTransformMakeTranslation(-r.origin.x, -r.origin.y));
    return g;
}

static CGAffineTransform cropTransform(const Geometry& g, double W, double H, double cx, double zoom) {
    double scale = std::max(W / g.sw, H / g.sh) * zoom;
    double tx = W / 2 - cx * g.sw * scale, ty = (H - g.sh * scale) / 2;
    tx = std::clamp(tx, std::min(0.0, W - g.sw * scale), 0.0);
    ty = std::clamp(ty, std::min(0.0, H - g.sh * scale), 0.0);
    return CGAffineTransformConcat(g.norm, CGAffineTransformConcat(CGAffineTransformMakeScale(scale, scale),
                                                                    CGAffineTransformMakeTranslation(tx, ty)));
}

// ---------------------------------------------------------------- captions
// Text is rasterised with Core Text into bitmaps (CATextLayer does not draw in
// the offline AVFoundation renderer on recent macOS), which also gives us real
// stroke + shadow control.
struct Phrase { double start, end; std::vector<Word> words; };   // composition seconds

static std::vector<Phrase> groupPhrases(const Clip& c, double clipStart) {
    std::vector<Phrase> out; Phrase cur{0, 0, {}};
    double clipEnd = clipStart + c.duration();
    auto flush = [&] { if (!cur.words.empty()) { cur.end = std::max(cur.end, cur.start + 0.4); out.push_back(cur); cur = {0, 0, {}}; } };
    for (auto w : c.words) {
        w.start = std::clamp(clipStart + (w.start - c.in), clipStart, clipEnd);
        w.end = std::clamp(clipStart + (w.end - c.in), clipStart, clipEnd);
        if (!cur.words.empty()) {
            bool gap = w.start - cur.words.back().end > 0.6;
            bool full = cur.words.size() >= 4 || w.end - cur.start > 2.0;
            char last = cur.words.back().text.empty() ? ' ' : cur.words.back().text.back();
            if (gap || full || last == '.' || last == '?' || last == '!' || last == ',') flush();
        }
        if (cur.words.empty()) cur.start = w.start;
        cur.words.push_back(w); cur.end = w.end;
    }
    flush();
    for (size_t i = 0; i + 1 < out.size(); ++i) out[i].end = std::min(out[i + 1].start, out[i].end + 1.0);
    if (!out.empty()) out.back().end = std::min(clipEnd, out.back().end + 0.8);
    return out;
}

static CGColorRef rgba(double r, double g, double b, double a) { return CGColorCreateGenericRGB(r, g, b, a); }

static NSAttributedString* attr(NSString* text, CTFontRef font, CGColorRef color, double strokeW) {
    CTTextAlignment al = kCTTextAlignmentCenter;
    CTParagraphStyleSetting ps[] = {{kCTParagraphStyleSpecifierAlignment, sizeof(al), &al}};
    CTParagraphStyleRef para = CTParagraphStyleCreate(ps, 1);
    NSMutableDictionary* d = [@{(id)kCTFontAttributeName: (__bridge id)font,
                                (id)kCTForegroundColorAttributeName: (__bridge id)color,
                                (id)kCTParagraphStyleAttributeName: (__bridge id)para} mutableCopy];
    if (strokeW > 0) {
        d[(id)kCTStrokeColorAttributeName] = (__bridge id)CGColorGetConstantColor(kCGColorBlack);
        d[(id)kCTStrokeWidthAttributeName] = @(-strokeW);
    }
    CFRelease(para);
    return [[NSAttributedString alloc] initWithString:text attributes:d];
}

static CGSize measure(NSAttributedString* s, double maxW) {
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)s);
    CGSize sz = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), nullptr, CGSizeMake(maxW, 1e5), nullptr);
    CFRelease(fs);
    return CGSizeMake(ceil(sz.width) + 2, ceil(sz.height) + 2);
}

// Rasterise text (optionally with a drop shadow) into an image sized to the text + padding.
static CGImageRef rasterText(NSAttributedString* a, double maxW, bool shadow, CGSize* outSize) {
    CGSize sz = measure(a, maxW);
    const double pad = 28;
    int w = int(sz.width + 2 * pad), h = int(sz.height + 2 * pad);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(nullptr, w, h, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (shadow) {
        CGColorRef sc = rgba(0, 0, 0, 0.85);
        CGContextSetShadowWithColor(c, CGSizeMake(0, -4), 8, sc);
        CGColorRelease(sc);
    }
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)a);
    CGPathRef path = CGPathCreateWithRect(CGRectMake(pad, pad, sz.width, sz.height), nullptr);
    CTFrameRef fr = CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, nullptr);
    CTFrameDraw(fr, c);
    CFRelease(fr); CGPathRelease(path); CFRelease(fs);
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    if (outSize) *outSize = CGSizeMake(w, h);
    return img;
}

static CALayer* imageLayer(CGImageRef img, CGSize sz, CGPoint center) {
    CALayer* l = [CALayer layer];
    l.contents = (__bridge id)img; l.contentsScale = 1; l.contentsGravity = kCAGravityCenter;
    l.bounds = CGRectMake(0, 0, sz.width, sz.height); l.position = center;
    return l;
}

static double beginTime(double t) { return t <= 0 ? AVCoreAnimationBeginTimeAtZero : t; }

static double g_total = 0;   // composition length; visibility keyframes span the whole timeline so the
                             // offline renderer never sees a "not started yet" animation.
static void addVisibility(CALayer* l, double start, double end, double fade = 0.0) {
    double T = std::max(g_total, end + 0.1), e = 0.001;
    l.opacity = 0;
    CAKeyframeAnimation* a = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    NSMutableArray* v = [NSMutableArray array]; NSMutableArray* k = [NSMutableArray array];
    auto key = [&](double t, double val) { [k addObject:@(std::clamp(t / T, 0.0, 1.0))]; [v addObject:@(val)]; };
    key(0, 0);
    if (start > e) key(start - e, 0);
    key(start, fade > 0 ? 0 : 1);
    if (fade > 0) { key(start + fade, 1); key(end - fade, 1); }
    key(end, fade > 0 ? 0 : 1);
    key(end + e, 0); key(T, 0);
    a.values = v; a.keyTimes = k; a.beginTime = AVCoreAnimationBeginTimeAtZero; a.duration = T;
    a.removedOnCompletion = NO; a.fillMode = kCAFillModeBoth; a.calculationMode = kCAAnimationLinear;
    [l addAnimation:a forKey:@"vis"];
}

static void addPop(CALayer* l, double start, double amount = 1.0) {
    CAKeyframeAnimation* a = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    a.values = @[@(1.0 - 0.35 * amount), @(1.0 + 0.08 * amount), @1.0];
    a.keyTimes = @[@0, @0.6, @1]; a.duration = 0.18;
    a.beginTime = beginTime(start); a.removedOnCompletion = NO; a.fillMode = kCAFillModeBoth;
    [l addAnimation:a forKey:@"pop"];
}

static void buildCaptions(CALayer* overlay, const Project& p, const std::vector<double>& clipStarts) {
    const Settings& s = p.settings;
    const double W = s.width, H = s.height, maxW = W * 0.86;
    CTFontRef font = CTFontCreateWithName((CFStringRef)ns(s.fontName), s.fontSize, nullptr);
    CGColorRef white = rgba(1, 1, 1, 1), yellow = rgba(1, 0.86, 0.1, 1);
    NSMutableArray* keepAlive = [NSMutableArray array];   // images stay referenced through layer.contents

    for (size_t ci = 0; ci < p.clips.size(); ++ci) {
        const Clip& c = p.clips[ci];
        double clipStart = clipStarts[ci];

        double hookY = H * screenPosY(s.hookPos), capY = H * screenPosY(s.captionPos);
        if (s.showHook && !c.hook.empty() && ci == 0) {
            CTFontRef hf = CTFontCreateWithName((CFStringRef)ns(s.fontName), s.fontSize * 1.1, nullptr);
            CGSize sz; CGImageRef img = rasterText(attr([ns(c.hook) uppercaseString], hf, yellow, 7), maxW, true, &sz);
            CALayer* l = imageLayer(img, sz, CGPointMake(W / 2, hookY + sz.height / 2 - 28));
            addVisibility(l, clipStart, clipStart + std::min(3.0, c.duration())); addPop(l, clipStart);
            [overlay addSublayer:l]; [keepAlive addObject:(__bridge id)img]; CGImageRelease(img); CFRelease(hf);
        }
        // Overlay text (AI-suggested, or the slide's caption): shown for the clip, styled like captions.
        if (!c.overlay.empty() || (c.isImage && !c.hook.empty() && ci != 0)) {
            NSString* txt = ns(c.overlay.empty() ? c.hook : c.overlay);
            CTFontRef of = CTFontCreateWithName((CFStringRef)ns(s.fontName), s.fontSize * 0.95, nullptr);
            CGSize sz; CGImageRef img = rasterText(attr([txt uppercaseString], of, white, 6), maxW, true, &sz);
            double oy = c.words.empty() ? capY : (s.captionPos == ScreenPos::Top || s.captionPos == ScreenPos::Upper ? H * 0.30 : H * 0.66);
            CALayer* l = imageLayer(img, sz, CGPointMake(W / 2, oy + sz.height / 2 - 28));
            addVisibility(l, clipStart + 0.1, clipStart + c.duration() - 0.1, 0.2);
            [overlay addSublayer:l]; [keepAlive addObject:(__bridge id)img]; CGImageRelease(img); CFRelease(of);
        }
        if (s.captionStyle == CaptionStyle::None) continue;

        for (auto& ph : groupPhrases(c, clipStart)) {
            NSMutableString* text = [NSMutableString string];
            for (auto& w : ph.words) { if (text.length) [text appendString:@" "]; [text appendString:ns(w.text)]; }
            double y = capY;

            if (s.captionStyle == CaptionStyle::Karaoke) {
                // per-word bitmaps (white + highlighted), laid out in centred lines
                struct WImg { CGImageRef base, hi; CGSize sz; };
                std::vector<WImg> imgs; double space = -s.fontSize * 0.55;   // images carry padding; overlap it
                for (auto& w : ph.words) {
                    WImg wi; NSString* t = [ns(w.text) uppercaseString];
                    wi.base = rasterText(attr(t, font, white, 6), 1e5, true, &wi.sz);
                    wi.hi = rasterText(attr(t, font, yellow, 6), 1e5, true, nullptr);
                    imgs.push_back(wi);
                }
                std::vector<std::vector<int>> lines(1); double lw = 0;
                for (int i = 0; i < (int)imgs.size(); ++i) {
                    if (lw > 0 && lw + space + imgs[i].sz.width > maxW + 56) { lines.push_back({}); lw = 0; }
                    lines.back().push_back(i); lw += (lw > 0 ? space : 0) + imgs[i].sz.width;
                }
                double lineH = s.fontSize * 1.25;
                CALayer* group = [CALayer layer]; group.frame = CGRectMake(0, 0, W, H);
                for (size_t li = 0; li < lines.size(); ++li) {
                    double width = 0; for (int i : lines[li]) width += imgs[i].sz.width; width += space * (lines[li].size() - 1);
                    double x = (W - width) / 2, ly = y + (lines.size() - 1 - li) * lineH;
                    for (int i : lines[li]) {
                        CGPoint ctr = CGPointMake(x + imgs[i].sz.width / 2, ly + lineH / 2);
                        CALayer* base = imageLayer(imgs[i].base, imgs[i].sz, ctr);
                        CALayer* hi = imageLayer(imgs[i].hi, imgs[i].sz, ctr);
                        addVisibility(hi, ph.words[i].start, ph.end + 0.01);
                        [group addSublayer:base]; [group addSublayer:hi];
                        [keepAlive addObject:(__bridge id)imgs[i].base]; [keepAlive addObject:(__bridge id)imgs[i].hi];
                        CGImageRelease(imgs[i].base); CGImageRelease(imgs[i].hi);
                        x += imgs[i].sz.width + space;
                    }
                }
                addVisibility(group, ph.start, ph.end);
                [overlay addSublayer:group];
                continue;
            }

            bool minimal = s.captionStyle == CaptionStyle::Minimal;
            double stroke = s.captionStyle == CaptionStyle::Outline ? 9 : s.captionStyle == CaptionStyle::BoldPop ? 5 : 0;
            NSAttributedString* a = attr(minimal ? text : [text uppercaseString], font, white, stroke);
            CGSize sz; CGImageRef img = rasterText(a, maxW, !minimal, &sz);
            CALayer* holder = [CALayer layer];
            CGSize textSz = measure(a, maxW);
            holder.bounds = CGRectMake(0, 0, textSz.width + 56, textSz.height + 28);
            holder.position = CGPointMake(W / 2, y + holder.bounds.size.height / 2);
            if (minimal) { holder.backgroundColor = rgba(0, 0, 0, 0.62); holder.cornerRadius = 20; }
            CALayer* t = imageLayer(img, sz, CGPointMake(holder.bounds.size.width / 2, holder.bounds.size.height / 2));
            [holder addSublayer:t];
            addVisibility(holder, ph.start, ph.end, minimal ? 0.12 : 0.0);
            if (s.captionStyle == CaptionStyle::BoldPop) addPop(holder, ph.start);
            [overlay addSublayer:holder];
            [keepAlive addObject:(__bridge id)img]; CGImageRelease(img);
        }
    }
    CFRelease(font); CGColorRelease(white); CGColorRelease(yellow);
    overlay.name = @"captions"; objc_setAssociatedObject(overlay, "imgs", keepAlive, OBJC_ASSOCIATION_RETAIN);
}

// ---------------------------------------------------------------- render
bool renderProject(const Project& p, const std::string& outPath, const Progress& progress, std::string* err) {
    @autoreleasepool {
        if (p.clips.empty()) { if (err) *err = "No clips selected"; return false; }
        const Settings& s = p.settings;
        const double W = s.width, H = s.height;

        AVMutableComposition* comp = [AVMutableComposition composition];
        AVMutableCompositionTrack* vTrack = [comp addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
        AVMutableCompositionTrack* aTrack = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        NSMutableArray* instructions = [NSMutableArray array];
        std::vector<double> clipStarts;
        CMTime cursor = kCMTimeZero;
        bool anyVoice = false;

        for (size_t i = 0; i < p.clips.size(); ++i) {
            const Clip& c = p.clips[i];
            if (progress) progress(0.05 * i / p.clips.size(), "Assembling clip " + std::to_string(i + 1));
            std::string srcPath = c.sourcePath;
            if (c.isImage) { srcPath = imageToVideo(c.sourcePath, c.duration() + 1, err); if (srcPath.empty()) return false; }
            AVURLAsset* asset = loadAsset(srcPath);
            AVAssetTrack* sv = firstTrack(asset, AVMediaTypeVideo);
            AVAssetTrack* sa = firstTrack(asset, AVMediaTypeAudio);
            if (!sv) { if (err) *err = "No video track in " + c.sourcePath; return false; }
            double srcDur = CMTimeGetSeconds(asset.duration);
            double in = std::clamp(c.in, 0.0, srcDur), out = std::clamp(c.out, in + 0.1, srcDur);
            CMTimeRange range = CMTimeRangeMake(secs(in), secs(out - in));
            NSError* e = nil;
            if (![vTrack insertTimeRange:range ofTrack:sv atTime:cursor error:&e]) { if (err) *err = str(e.localizedDescription); return false; }
            if (sa && s.keepVoice && !c.isImage) { [aTrack insertTimeRange:range ofTrack:sa atTime:cursor error:nil]; anyVoice = true; }
            else [aTrack insertEmptyTimeRange:CMTimeRangeMake(cursor, range.duration)];

            Geometry g = geometryFor(sv);
            double cx = s.smartReframe ? c.cropCenterX : 0.5;
            AVMutableVideoCompositionInstruction* ins = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
            ins.timeRange = CMTimeRangeMake(cursor, range.duration);
            AVMutableVideoCompositionLayerInstruction* li = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:vTrack];
            bool zoomOut = (i % 2) == 1;
            double z0 = s.kenBurns ? (zoomOut ? 1.06 : 1.0) : 1.0, z1 = s.kenBurns ? (zoomOut ? 1.0 : 1.06) : 1.0;
            double dur = out - in;
            if (c.isImage) {
                // Slideshow motion: a slow pan across the picture with a gentle zoom (direction alternates).
                bool landscape = g.sw / g.sh > W / H * 1.05;
                double ax = landscape ? (zoomOut ? 0.62 : 0.38) : 0.5, bx = landscape ? (zoomOut ? 0.38 : 0.62) : 0.5;
                double za = zoomOut ? 1.14 : 1.0, zb = zoomOut ? 1.0 : 1.14;
                if (!landscape) { za = zoomOut ? 1.18 : 1.0; zb = zoomOut ? 1.0 : 1.18; }
                [li setTransformRampFromStartTransform:cropTransform(g, W, H, ax, za) toEndTransform:cropTransform(g, W, H, bx, zb) timeRange:ins.timeRange];
            } else if (s.smartReframe && c.track.size() >= 2) {
                // piecewise-linear pan through the tracked positions (+ the slow zoom)
                for (size_t k = 0; k + 1 < c.track.size(); ++k) {
                    double fa = c.track[k].first, fb = c.track[k + 1].first;
                    if (fb <= fa) continue;
                    CGAffineTransform ta = cropTransform(g, W, H, c.track[k].second, z0 + (z1 - z0) * fa);
                    CGAffineTransform tb = cropTransform(g, W, H, c.track[k + 1].second, z0 + (z1 - z0) * fb);
                    CMTimeRange tr = CMTimeRangeMake(CMTimeAdd(cursor, secs(fa * dur)), secs((fb - fa) * dur));
                    [li setTransformRampFromStartTransform:ta toEndTransform:tb timeRange:tr];
                }
            } else {
                double cx1 = s.smartReframe ? c.cropEndX : 0.5;
                CGAffineTransform t0 = cropTransform(g, W, H, cx, z0), t1 = cropTransform(g, W, H, cx1, z1);
                if (s.kenBurns || fabs(cx1 - cx) > 1e-3)
                    [li setTransformRampFromStartTransform:t0 toEndTransform:t1 timeRange:ins.timeRange];
                else
                    [li setTransform:t0 atTime:cursor];
            }
            ins.layerInstructions = @[li];
            [instructions addObject:ins];
            clipStarts.push_back(CMTimeGetSeconds(cursor));
            cursor = CMTimeAdd(cursor, range.duration);
        }
        double total = CMTimeGetSeconds(cursor);
        if (!anyVoice) [comp removeTrack:aTrack];

        // music
        AVMutableAudioMix* mix = nil;
        NSMutableArray* params = [NSMutableArray array];
        if (!s.musicPath.empty()) {
            AVURLAsset* m = loadAsset(s.musicPath);
            if (AVAssetTrack* mt = firstTrack(m, AVMediaTypeAudio)) {
                AVMutableCompositionTrack* mTrack = [comp addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
                double mdur = CMTimeGetSeconds(m.duration);
                double off = std::clamp(p.musicOffset, 0.0, std::max(0.0, mdur - 1));
                double len = std::min(total, mdur - off);
                [mTrack insertTimeRange:CMTimeRangeMake(secs(off), secs(len)) ofTrack:mt atTime:kCMTimeZero error:nil];
                AVMutableAudioMixInputParameters* mp = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:mTrack];
                float gain = anyVoice ? (float)s.musicGain : (float)std::max(s.musicGain, 0.9);
                [mp setVolume:gain atTime:kCMTimeZero];
                double fade = std::min(1.5, len * 0.3);
                [mp setVolumeRampFromStartVolume:gain toEndVolume:0 timeRange:CMTimeRangeMake(secs(len - fade), secs(fade))];
                [params addObject:mp];
            }
        }
        if (anyVoice) {
            AVMutableAudioMixInputParameters* vp = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:aTrack];
            [vp setVolume:1.0 atTime:kCMTimeZero];
            [params addObject:vp];
        }
        if (params.count) { mix = [AVMutableAudioMix audioMix]; mix.inputParameters = params; }

        AVMutableVideoComposition* vc = [AVMutableVideoComposition videoComposition];
        vc.renderSize = CGSizeMake(W, H);
        vc.frameDuration = CMTimeMake(1, (int)std::round(s.fps));
        vc.instructions = instructions;

        CALayer* parent = [CALayer layer]; parent.frame = CGRectMake(0, 0, W, H);
        CALayer* videoLayer = [CALayer layer]; videoLayer.frame = parent.frame;
        CALayer* overlay = [CALayer layer]; overlay.frame = parent.frame;
        [parent addSublayer:videoLayer]; [parent addSublayer:overlay];
        g_total = total;
        buildCaptions(overlay, p, clipStarts);
        vc.animationTool = [AVVideoCompositionCoreAnimationTool videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer inLayer:parent];

        [[NSFileManager defaultManager] removeItemAtPath:ns(outPath) error:nil];
        AVAssetExportSession* ex = [[AVAssetExportSession alloc] initWithAsset:comp presetName:AVAssetExportPresetHighestQuality];
        ex.outputURL = fileURL(outPath); ex.outputFileType = AVFileTypeMPEG4;
        ex.videoComposition = vc; ex.audioMix = mix; ex.shouldOptimizeForNetworkUse = YES;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [ex exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
        while (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)))) {
            if (progress) progress(0.05 + 0.95 * ex.progress, "Rendering " + std::to_string(int(ex.progress * 100)) + "%");
        }
        if (ex.status != AVAssetExportSessionStatusCompleted) {
            if (err) *err = str(ex.error.localizedDescription ?: @"Export failed");
            return false;
        }
        if (progress) progress(1.0, "Done: " + outPath);
        return true;
    }
}

} // namespace cm
