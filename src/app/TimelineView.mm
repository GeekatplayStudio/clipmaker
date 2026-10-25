#import "app/TimelineView.h"

@implementation TimelineView {
    std::vector<double> _durs; std::vector<int> _src; std::vector<double> _beats; double _total;
}
- (void)setClipDurations:(const std::vector<double>&)durs sources:(const std::vector<int>&)src
                   beats:(const std::vector<double>&)beats total:(double)total {
    _durs = durs; _src = src; _beats = beats; _total = total; [self setNeedsDisplay:YES];
}
- (void)setPlayhead:(double)p { _playhead = p; [self setNeedsDisplay:YES]; }
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds;
    [[NSColor colorWithWhite:0.11 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:b xRadius:6 yRadius:6] fill];
    if (_total <= 0) {
        NSDictionary* a = @{NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]};
        NSString* s = @"Timeline — select candidates and press Generate";
        NSSize sz = [s sizeWithAttributes:a];
        [s drawAtPoint:NSMakePoint(NSMidX(b) - sz.width / 2, NSMidY(b) - sz.height / 2) withAttributes:a];
        return;
    }
    static NSColor* palette[] = {nil};
    NSArray* colors = @[[NSColor systemBlueColor], [NSColor systemPurpleColor], [NSColor systemTealColor], [NSColor systemOrangeColor], [NSColor systemPinkColor]];
    double x = 8, w = b.size.width - 16, t = 0;
    for (size_t i = 0; i < _durs.size(); ++i) {
        double cw = _durs[i] / _total * w;
        NSRect cr = NSMakeRect(x + t / _total * w + 1, 10, cw - 2, b.size.height - 30);
        [[colors[_src[i] % colors.count] colorWithAlphaComponent:0.85] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:cr xRadius:4 yRadius:4] fill];
        NSString* lbl = [NSString stringWithFormat:@"%.1fs", _durs[i]];
        [lbl drawAtPoint:NSMakePoint(cr.origin.x + 6, cr.origin.y + 4) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:10], NSForegroundColorAttributeName: NSColor.whiteColor}];
        t += _durs[i];
    }
    [[NSColor colorWithWhite:1 alpha:0.5] setStroke];
    for (double bt : _beats) {
        if (bt > _total) break;
        double bx = x + bt / _total * w;
        NSBezierPath* p = [NSBezierPath bezierPath]; [p moveToPoint:NSMakePoint(bx, b.size.height - 16)]; [p lineToPoint:NSMakePoint(bx, b.size.height - 8)]; [p stroke];
    }
    if (_playhead >= 0 && _playhead <= _total) {
        [[NSColor systemYellowColor] setFill];
        NSRectFill(NSMakeRect(x + _playhead / _total * w - 1, 4, 2, b.size.height - 8));
    }
    (void)palette;
}
@end
