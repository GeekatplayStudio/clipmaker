#pragma once
#import <Cocoa/Cocoa.h>

@interface ClipMakerController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate>
- (void)addSourcePaths:(NSArray<NSString*>*)paths;
@end
