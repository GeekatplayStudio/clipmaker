#pragma once
#import <Cocoa/Cocoa.h>

@interface ClipMakerController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
- (void)addSourcePaths:(NSArray<NSString*>*)paths;
@end
