#import "app/TimelineView.h"
#import "app/Theme.h"

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
    NSBezierPath* bgp = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 0.5, 0.5) xRadius:10 yRadius:10];
    [gp::subtle() setFill]; [bgp fill]; [gp::border() setStroke]; [bgp stroke];
    if (_total <= 0) {
        NSDictionary* a = @{NSFontAttributeName: gp::body(11), NSForegroundColorAttributeName: gp::faint()};
        NSString* s = @"Timeline · appears after Generate";
        NSSize sz = [s sizeWithAttributes:a];
        [s drawAtPoint:NSMakePoint(NSMidX(b) - sz.width / 2, NSMidY(b) - sz.height / 2) withAttributes:a];
        return;
    }
    NSArray* colors = @[gp::accent(), gp::alt(), gp::hex(0xb46bff), gp::green(), gp::hex(0x3fb6ff)];
    double x = 10, w = b.size.width - 20, t = 0;
    for (size_t i = 0; i < _durs.size(); ++i) {
        double cw = _durs[i] / _total * w;
        NSRect cr = NSMakeRect(x + t / _total * w + 1.5, 10, cw - 3, b.size.height - 32);
        NSColor* c = colors[_src[i] % colors.count];
        NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:cr xRadius:6 yRadius:6];
        [[[NSGradient alloc] initWithStartingColor:[c colorWithAlphaComponent:0.95] endingColor:[c colorWithAlphaComponent:0.65]] drawInBezierPath:p angle:-90];
        NSString* lbl = [NSString stringWithFormat:@"%.1fs", _durs[i]];
        [lbl drawAtPoint:NSMakePoint(cr.origin.x + 7, cr.origin.y + 5) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightBold], NSForegroundColorAttributeName: [NSColor colorWithWhite:0.06 alpha:0.9]}];
        t += _durs[i];
    }
    [[NSColor colorWithWhite:1 alpha:0.35] setStroke];
    for (double bt : _beats) {
        if (bt > _total) break;
        double bx = x + bt / _total * w;
        NSBezierPath* p = [NSBezierPath bezierPath]; [p moveToPoint:NSMakePoint(bx, b.size.height - 17)]; [p lineToPoint:NSMakePoint(bx, b.size.height - 9)]; [p stroke];
    }
    if (_playhead >= 0 && _playhead <= _total) {
        [gp::accent() setFill];
        NSRectFill(NSMakeRect(x + _playhead / _total * w - 1, 5, 2, b.size.height - 10));
    }
}
@end
