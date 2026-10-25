#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <string>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

namespace cm {
inline NSString* ns(const std::string& s) {
    NSString* r = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    if (!r) r = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSISOLatin1StringEncoding];
    return r ?: @"";
}
inline std::string str(NSString* s) { return s ? std::string([s UTF8String]) : std::string(); }
inline NSURL* fileURL(const std::string& p) { return [NSURL fileURLWithPath:ns(p)]; }
inline CMTime secs(double s) { return CMTimeMakeWithSeconds(s, 600); }

inline AVURLAsset* loadAsset(const std::string& path) {
    AVURLAsset* a = [AVURLAsset URLAssetWithURL:fileURL(path)
                                        options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [a loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{ dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return a;
}
inline AVAssetTrack* firstTrack(AVAsset* a, AVMediaType t) { return [[a tracksWithMediaType:t] firstObject]; }
}
