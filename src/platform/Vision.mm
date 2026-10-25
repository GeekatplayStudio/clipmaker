#include "platform/Platform.h"
#include "platform/Common.h"
#import <Vision/Vision.h>
#import <AppKit/AppKit.h>
#include <algorithm>
#include <cmath>

namespace cm {

double detectSubjectCenterX(const std::string& path, double t) {
    @autoreleasepool {
        AVURLAsset* a = loadAsset(path);
        AVAssetImageGenerator* gen = [[AVAssetImageGenerator alloc] initWithAsset:a];
        gen.appliesPreferredTrackTransform = YES;
        gen.maximumSize = CGSizeMake(720, 720);
        gen.requestedTimeToleranceBefore = secs(0.5);
        gen.requestedTimeToleranceAfter = secs(0.5);
        NSError* e = nil;
        CGImageRef img = [gen copyCGImageAtTime:secs(t) actualTime:nullptr error:&e];
        if (!img) return -1;
        double result = -1;
        VNDetectFaceRectanglesRequest* faces = [[VNDetectFaceRectanglesRequest alloc] init];
        VNGenerateObjectnessBasedSaliencyImageRequest* obj = [[VNGenerateObjectnessBasedSaliencyImageRequest alloc] init];
        VNGenerateAttentionBasedSaliencyImageRequest* sal = [[VNGenerateAttentionBasedSaliencyImageRequest alloc] init];
        VNImageRequestHandler* h = [[VNImageRequestHandler alloc] initWithCGImage:img options:@{}];
        if ([h performRequests:@[faces, obj, sal] error:&e]) {
            // Largest face wins; weighted centre of all faces when several are similar.
            double sumW = 0, sumX = 0, maxA = 0;
            for (VNFaceObservation* f in faces.results) {
                double area = f.boundingBox.size.width * f.boundingBox.size.height;
                maxA = std::max(maxA, area);
            }
            for (VNFaceObservation* f in faces.results) {
                double area = f.boundingBox.size.width * f.boundingBox.size.height;
                if (area < maxA * 0.4) continue;
                sumW += area; sumX += area * CGRectGetMidX(f.boundingBox);
            }
            if (sumW > 0) result = sumX / sumW;
            else {
                // Salient objects: prefer objectness (foreground things), then attention. Ignore boxes
                // that span most of the frame (they carry no horizontal information).
                for (VNSaliencyImageObservation* o in @[obj.results.firstObject ?: (id)NSNull.null, sal.results.firstObject ?: (id)NSNull.null]) {
                    if (![o isKindOfClass:VNSaliencyImageObservation.class]) continue;
                    double bw = 0, bx = 0.5;
                    for (VNRectangleObservation* r in o.salientObjects) {
                        if (r.boundingBox.size.width > 0.85) continue;
                        double area = r.boundingBox.size.width * r.boundingBox.size.height;
                        if (area > bw) { bw = area; bx = CGRectGetMidX(r.boundingBox); }
                    }
                    if (bw > 0) { result = bx; break; }
                }
            }
        }
        CGImageRelease(img);
        return result;
    }
}


static CGImageRef frameAt(const std::string& path, double t) {
    if (t < 0) {
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL(path), nullptr);
        if (!src) return nullptr;
        NSDictionary* opt = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                              (id)kCGImageSourceThumbnailMaxPixelSize: @720};
        CGImageRef img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
        CFRelease(src); return img;
    }
    AVAssetImageGenerator* gen = [[AVAssetImageGenerator alloc] initWithAsset:loadAsset(path)];
    gen.appliesPreferredTrackTransform = YES; gen.maximumSize = CGSizeMake(720, 720);
    gen.requestedTimeToleranceBefore = secs(0.5); gen.requestedTimeToleranceAfter = secs(0.5);
    return [gen copyCGImageAtTime:secs(t) actualTime:nullptr error:nil];
}

std::string describeFrame(const std::string& path, double t) {
    @autoreleasepool {
        CGImageRef img = frameAt(path, t);
        if (!img) return "";
        VNClassifyImageRequest* req = [[VNClassifyImageRequest alloc] init];
        VNDetectFaceRectanglesRequest* faces = [[VNDetectFaceRectanglesRequest alloc] init];
        VNImageRequestHandler* h = [[VNImageRequestHandler alloc] initWithCGImage:img options:@{}];
        std::string out;
        if ([h performRequests:@[req, faces] error:nil]) {
            NSUInteger nf = faces.results.count;
            if (nf == 1) out = "one person"; else if (nf > 1) out = std::to_string(nf) + " people";
            int n = 0;
            for (VNClassificationObservation* o in req.results) {
                if (o.confidence < 0.3 || n >= 6) break;
                std::string id = str(o.identifier);
                for (auto& ch : id) if (ch == '_') ch = ' ';
                if (!out.empty()) out += ", ";
                out += id; ++n;
            }
        }
        CGImageRelease(img);
        return out;
    }
}

void trackSubject(Candidate& c, const std::string& path) {
    // Sample the subject position every ~1.5 s, smooth it, and keep it as pan keyframes.
    int n = std::clamp(int(c.duration() / 1.5) + 2, 3, 9);
    std::vector<std::pair<double,double>> pts;
    for (int i = 0; i < n; ++i) {
        double f = (i + 0.5) / n;
        double x = detectSubjectCenterX(path, c.start + f * c.duration());
        if (x >= 0) pts.push_back({f, x});
    }
    c.track.clear();
    if (pts.empty()) { c.cropCenterX = c.cropEndX = 0.5; return; }
    // 3-tap smoothing to kill detector jitter
    std::vector<std::pair<double,double>> sm = pts;
    for (size_t i = 0; i < pts.size(); ++i) {
        double a = pts[i > 0 ? i - 1 : i].second, b = pts[i].second, d = pts[i + 1 < pts.size() ? i + 1 : i].second;
        sm[i].second = (a + 2 * b + d) / 4;
    }
    double lo = 1, hi = 0; for (auto& q : sm) { lo = std::min(lo, q.second); hi = std::max(hi, q.second); }
    if (hi - lo < 0.04) { double m = 0; for (auto& q : sm) m += q.second; m /= sm.size(); c.cropCenterX = c.cropEndX = m; return; }
    // extend to the clip edges and store
    c.track.push_back({0.0, sm.front().second});
    for (auto& q : sm) c.track.push_back(q);
    c.track.push_back({1.0, sm.back().second});
    c.cropCenterX = sm.front().second; c.cropEndX = sm.back().second;
    if (getenv("CLIPMAKER_DEBUG")) {
        fprintf(stderr, "track %.1f-%.1f:", c.start, c.end);
        for (auto& q : c.track) fprintf(stderr, " %.2f@%.2f", q.second, q.first);
        fprintf(stderr, "\n");
    }
}

int dumpFrames(const std::string& path, const std::string& outDir, std::string* err) {
    @autoreleasepool {
        MediaInfo m = probeMedia(path);
        if (!m.ok) { if (err) *err = m.error; return 0; }
        [[NSFileManager defaultManager] createDirectoryAtPath:ns(outDir) withIntermediateDirectories:YES attributes:nil error:nil];
        AVAssetImageGenerator* gen = [[AVAssetImageGenerator alloc] initWithAsset:loadAsset(path)];
        gen.appliesPreferredTrackTransform = YES;
        gen.requestedTimeToleranceBefore = kCMTimeZero; gen.requestedTimeToleranceAfter = kCMTimeZero;
        int n = 0;
        for (double f = 0.04; f < 1.0; f += 0.12) {
            NSError* e = nil;
            CGImageRef img = [gen copyCGImageAtTime:secs(f * m.duration) actualTime:nullptr error:&e];
            if (!img) continue;
            NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
            NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:[ns(outDir) stringByAppendingFormat:@"/frame_%02d_%.1fs.png", n, f * m.duration] atomically:YES];
            CGImageRelease(img); ++n;
        }
        if (err) *err = std::to_string(m.width) + "x" + std::to_string(m.height) + " " + std::to_string(m.duration) + "s";
        return n;
    }
}
} // namespace cm
