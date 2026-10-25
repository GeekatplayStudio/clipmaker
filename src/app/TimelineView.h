#pragma once
#import <Cocoa/Cocoa.h>
#include <vector>

// Compact strip: clip blocks (colored by source) + beat ticks + playhead.
@interface TimelineView : NSView
- (void)setClipDurations:(const std::vector<double>&)durs sources:(const std::vector<int>&)src
                   beats:(const std::vector<double>&)beats total:(double)total;
@property (nonatomic) double playhead;
@end
