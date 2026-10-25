#pragma once
#import <Cocoa/Cocoa.h>

// Geekatplay Studio visual language: deep graphite surfaces, orange accent, steel-blue secondary.
namespace gp {
inline NSColor* hex(unsigned v, CGFloat a = 1) { return [NSColor colorWithSRGBRed:((v >> 16) & 255) / 255.0 green:((v >> 8) & 255) / 255.0 blue:(v & 255) / 255.0 alpha:a]; }
inline NSColor* bg()        { return hex(0x121417); }
inline NSColor* surface()   { return hex(0x181d25); }
inline NSColor* card()      { return hex(0x161a22); }
inline NSColor* subtle()    { return hex(0x10141c); }
inline NSColor* border()    { return [NSColor colorWithWhite:1 alpha:0.08]; }
inline NSColor* text()      { return hex(0xf4f7fb); }
inline NSColor* muted()     { return hex(0xe0e7f0, 0.62); }
inline NSColor* faint()     { return hex(0xe0e7f0, 0.38); }
inline NSColor* accent()    { return hex(0xff7a18); }
inline NSColor* accent2()   { return hex(0xffa040); }
inline NSColor* alt()       { return hex(0x4d7ea8); }
inline NSColor* green()     { return hex(0x3dd68c); }
inline NSColor* red()       { return hex(0xf15a51); }
inline NSFont* heading(CGFloat s) { return [NSFont systemFontOfSize:s weight:NSFontWeightBold]; }
inline NSFont* body(CGFloat s)    { return [NSFont systemFontOfSize:s weight:NSFontWeightRegular]; }
inline NSFont* mono(CGFloat s)    { return [NSFont monospacedSystemFontOfSize:s weight:NSFontWeightMedium]; }
inline NSImage* symbol(NSString* name, CGFloat pt = 13) {
    NSImage* i = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    return [i imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pt weight:NSFontWeightSemibold]];
}
}

// Rounded card with a 1 px border.
@interface GPCard : NSView
@property (nonatomic) CGFloat radius;
@property (nonatomic, strong) NSColor* fill;
@end

// Flat/gradient button. style 0 = primary (orange gradient), 1 = secondary (surface + border), 2 = ghost.
@interface GPButton : NSButton
@property (nonatomic) int style;
+ (instancetype)buttonWithTitle:(NSString*)t symbol:(NSString*)sym style:(int)style target:(id)target action:(SEL)sel;
@end

// Thin accent progress bar.
@interface GPProgress : NSView
@property (nonatomic) double value;
@end

// Small pill (score badge, step indicator).
@interface GPPill : NSView
@property (nonatomic, strong) NSString* label;
@property (nonatomic, strong) NSColor* color;
@property (nonatomic) BOOL filled;
@end
