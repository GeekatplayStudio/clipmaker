#import "app/Theme.h"

@implementation GPCard
- (instancetype)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _radius = 12; _fill = gp::card(); } return self; }
- (void)drawRect:(NSRect)r {
    NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:_radius yRadius:_radius];
    [_fill setFill]; [p fill];
    [gp::border() setStroke]; p.lineWidth = 1; [p stroke];
}
@end

@implementation GPButton {
    BOOL _hover; NSTrackingArea* _ta;
}
+ (instancetype)buttonWithTitle:(NSString*)t symbol:(NSString*)sym style:(int)style target:(id)target action:(SEL)sel {
    GPButton* b = [[GPButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 32)];
    b.title = t; b.target = target; b.action = sel; b.style = style; b.bordered = NO;
    b.imagePosition = NSNoImage; b.wantsLayer = YES;
    if (sym) { b.image = gp::symbol(sym, style == 0 ? 14 : 12); b.imagePosition = NSImageLeading; b.imageHugsTitle = YES; }
    [b setButtonType:NSButtonTypeMomentaryChange];
    return b;
}
- (void)updateTrackingAreas {
    if (_ta) [self removeTrackingArea:_ta];
    _ta = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow owner:self userInfo:nil];
    [self addTrackingArea:_ta]; [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent*)e { _hover = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent*)e { _hover = NO; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)r {
    NSRect b = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:b xRadius:9 yRadius:9];
    CGFloat alpha = self.enabled ? 1.0 : 0.38;
    NSColor* fg = gp::text();
    if (_style == 0) {
        NSGradient* g = [[NSGradient alloc] initWithStartingColor:[gp::accent2() colorWithAlphaComponent:alpha] endingColor:[gp::accent() colorWithAlphaComponent:alpha]];
        [g drawInBezierPath:p angle:-90];
        if (_hover && self.enabled) { [[NSColor colorWithWhite:1 alpha:0.10] setFill]; [p fill]; }
        fg = [NSColor colorWithWhite:0.08 alpha:1];
    } else if (_style == 1) {
        [(_hover && self.enabled ? gp::hex(0x222835) : gp::surface()) setFill]; [p fill];
        [gp::border() setStroke]; [p stroke];
        fg = [gp::text() colorWithAlphaComponent:alpha];
    } else {
        if (_hover && self.enabled) { [[NSColor colorWithWhite:1 alpha:0.06] setFill]; [p fill]; }
        fg = [gp::muted() colorWithAlphaComponent:alpha];
    }
    if (self.highlighted) { [[NSColor colorWithWhite:0 alpha:0.18] setFill]; [p fill]; }
    NSFont* font = [NSFont systemFontOfSize:_style == 0 ? 13 : 12 weight:_style == 0 ? NSFontWeightBold : NSFontWeightSemibold];
    NSDictionary* a = @{NSFontAttributeName: font, NSForegroundColorAttributeName: fg};
    NSSize ts = [self.title sizeWithAttributes:a];
    CGFloat iw = self.image ? self.image.size.width + 6 : 0;
    CGFloat x = NSMidX(b) - (ts.width + iw) / 2, y = NSMidY(b) - ts.height / 2 - 0.5;
    if (self.image) {
        NSImage* im = [self.image copy]; [im setTemplate:YES];
        NSImage* tinted = [NSImage imageWithSize:im.size flipped:NO drawingHandler:^BOOL(NSRect d) {
            [im drawInRect:d]; [fg set]; NSRectFillUsingOperation(d, NSCompositingOperationSourceAtop); return YES; }];
        [tinted drawInRect:NSMakeRect(x, NSMidY(b) - im.size.height / 2, im.size.width, im.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        x += iw;
    }
    [self.title drawAtPoint:NSMakePoint(x, y) withAttributes:a];
}
@end

@implementation GPProgress
- (void)setValue:(double)v { _value = v; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds; CGFloat h = 4, y = NSMidY(b) - h / 2;
    [[NSColor colorWithWhite:1 alpha:0.07] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, y, b.size.width, h) xRadius:2 yRadius:2] fill];
    if (_value > 0) {
        NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, y, b.size.width * MIN(1.0, _value), h) xRadius:2 yRadius:2];
        [[[NSGradient alloc] initWithStartingColor:gp::accent() endingColor:gp::accent2()] drawInBezierPath:p angle:0];
    }
}
@end

@implementation GPPill
- (void)setLabel:(NSString*)l { _label = l; [self setNeedsDisplay:YES]; }
- (void)setColor:(NSColor*)c { _color = c; [self setNeedsDisplay:YES]; }
- (void)setFilled:(BOOL)f { _filled = f; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)r {
    NSColor* c = _color ?: gp::alt();
    NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:NSHeight(self.bounds) / 2 yRadius:NSHeight(self.bounds) / 2];
    [(_filled ? c : [c colorWithAlphaComponent:0.16]) setFill]; [p fill];
    if (!_filled) { [[c colorWithAlphaComponent:0.5] setStroke]; [p stroke]; }
    NSDictionary* a = @{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
                        NSForegroundColorAttributeName: _filled ? [NSColor colorWithWhite:0.08 alpha:1] : c};
    NSSize s = [(_label ?: @"") sizeWithAttributes:a];
    [(_label ?: @"") drawAtPoint:NSMakePoint(NSMidX(self.bounds) - s.width / 2, NSMidY(self.bounds) - s.height / 2) withAttributes:a];
}
@end
