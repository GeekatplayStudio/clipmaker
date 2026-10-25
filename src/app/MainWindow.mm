// ClipMaker — Geekatplay Studio · Vladimir Chopine
#import "app/MainWindow.h"
#import "app/TimelineView.h"
#import "app/Theme.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "platform/Platform.h"
#include "platform/Common.h"
#include "core/Segmenter.h"
#include "core/Beats.h"
#include <vector>
#include <string>
#include <sstream>

using namespace cm;

static NSString* S(const std::string& s) { return ns(s); }
static std::string U(NSString* s) { return s ? [s UTF8String] : ""; }

// ------------------------------------------------------------------ small view helpers
static NSTextField* label(NSString* t, NSRect f, NSFont* font, NSColor* color, NSView* parent) {
    NSTextField* l = [NSTextField labelWithString:t];
    l.frame = f; l.font = font; l.textColor = color; l.autoresizingMask = NSViewMinYMargin;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    [parent addSubview:l]; return l;
}
static NSTextField* section(NSString* t, CGFloat y, CGFloat w, NSView* parent) {
    NSTextField* l = label([t uppercaseString], NSMakeRect(18, y, w - 36, 14), [NSFont systemFontOfSize:10.5 weight:NSFontWeightBold], gp::accent(), parent);
    NSMutableAttributedString* a = [[NSMutableAttributedString alloc] initWithString:[t uppercaseString] attributes:@{NSKernAttributeName: @1.4, NSFontAttributeName: l.font, NSForegroundColorAttributeName: gp::accent()}];
    l.attributedStringValue = a;
    return l;
}
static NSButton* check(NSString* t, NSRect f, BOOL on, NSView* parent) {
    NSButton* b = [NSButton checkboxWithTitle:t target:nil action:nil];
    b.frame = f; b.state = on ? NSControlStateValueOn : NSControlStateValueOff; b.autoresizingMask = NSViewMinYMargin;
    b.font = gp::body(11.5);
    b.attributedTitle = [[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: gp::body(11.5), NSForegroundColorAttributeName: gp::text()}];
    [parent addSubview:b]; return b;
}
static NSPopUpButton* popup(NSArray* items, NSRect f, NSView* parent) {
    NSPopUpButton* p = [[NSPopUpButton alloc] initWithFrame:f pullsDown:NO];
    [p addItemsWithTitles:items]; p.autoresizingMask = NSViewMinYMargin; p.font = gp::body(11.5);
    p.controlSize = NSControlSizeSmall; p.bezelStyle = NSBezelStyleRounded;
    [parent addSubview:p]; return p;
}
static NSTextField* field(NSString* placeholder, NSRect f, NSView* parent, BOOL secure) {
    NSTextField* t = secure ? [[NSSecureTextField alloc] initWithFrame:f] : [[NSTextField alloc] initWithFrame:f];
    t.placeholderString = placeholder; t.font = gp::body(11.5); t.autoresizingMask = NSViewMinYMargin;
    t.controlSize = NSControlSizeSmall; t.bezelStyle = NSTextFieldRoundedBezel; t.textColor = gp::text();
    t.backgroundColor = gp::subtle(); t.drawsBackground = YES; t.wantsLayer = YES;
    [parent addSubview:t]; return t;
}
static GPButton* gpbutton(NSString* t, NSString* sym, int style, NSRect f, id target, SEL sel, NSView* parent) {
    GPButton* b = [GPButton buttonWithTitle:t symbol:sym style:style target:target action:sel];
    b.frame = f; b.autoresizingMask = NSViewMinYMargin; [parent addSubview:b]; return b;
}
static NSScrollView* darkScroll(NSRect f) {
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:f];
    sv.hasVerticalScroller = YES; sv.borderType = NSNoBorder; sv.drawsBackground = YES; sv.backgroundColor = gp::subtle();
    sv.wantsLayer = YES; sv.layer.cornerRadius = 9; sv.layer.borderWidth = 1; sv.layer.borderColor = gp::border().CGColor;
    sv.scrollerStyle = NSScrollerStyleOverlay; sv.autoresizingMask = NSViewMinYMargin;
    return sv;
}

// Row selection drawn as a soft accent band.
@interface GPRowView : NSTableRowView @end
@implementation GPRowView
- (void)drawSelectionInRect:(NSRect)r {
    NSBezierPath* p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 4, 2) xRadius:8 yRadius:8];
    [[gp::accent() colorWithAlphaComponent:0.16] setFill]; [p fill];
}
- (void)drawBackgroundInRect:(NSRect)r {}
@end

// One candidate moment: [✓] [score] [icon] time   Hook title (editable)
@interface PlanRow : NSTableCellView
@property (nonatomic, strong) NSButton* on; @property (nonatomic, strong) GPPill* score; @property (nonatomic, strong) NSImageView* icon;
@property (nonatomic, strong) NSTextField* time; @property (nonatomic, strong) NSTextField* hook; @property (nonatomic, strong) NSTextField* sub;
@end
@implementation PlanRow
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        _on = [NSButton checkboxWithTitle:@"" target:nil action:nil]; _on.frame = NSMakeRect(10, 15, 18, 18); [self addSubview:_on];
        _score = [[GPPill alloc] initWithFrame:NSMakeRect(34, 15, 36, 18)]; [self addSubview:_score];
        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(78, 16, 16, 16)]; _icon.contentTintColor = gp::muted(); [self addSubview:_icon];
        _time = [NSTextField labelWithString:@""]; _time.frame = NSMakeRect(98, 26, 230, 15); _time.font = gp::mono(10.5); _time.textColor = gp::muted(); [self addSubview:_time];
        _hook = [[NSTextField alloc] initWithFrame:NSMakeRect(95, 5, f.size.width - 105, 20)];
        _hook.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold]; _hook.textColor = gp::text(); _hook.bordered = NO; _hook.drawsBackground = NO;
        _hook.focusRingType = NSFocusRingTypeNone; _hook.editable = YES; _hook.autoresizingMask = NSViewWidthSizable; _hook.lineBreakMode = NSLineBreakByTruncatingTail;
        _hook.placeholderString = @"Hook title…"; [self addSubview:_hook];
    }
    return self;
}
@end

// Source row: icon + name + meta
@interface SourceRow : NSTableCellView
@property (nonatomic, strong) NSImageView* icon; @property (nonatomic, strong) NSTextField* name; @property (nonatomic, strong) NSTextField* meta;
@end
@implementation SourceRow
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 8, 16, 16)]; _icon.contentTintColor = gp::accent(); [self addSubview:_icon];
        _name = [NSTextField labelWithString:@""]; _name.frame = NSMakeRect(32, 7, f.size.width - 150, 17); _name.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]; _name.textColor = gp::text(); _name.lineBreakMode = NSLineBreakByTruncatingMiddle; _name.autoresizingMask = NSViewWidthSizable; [self addSubview:_name];
        _meta = [NSTextField labelWithString:@""]; _meta.frame = NSMakeRect(f.size.width - 118, 8, 108, 15); _meta.font = gp::mono(10); _meta.textColor = gp::faint(); _meta.alignment = NSTextAlignmentRight; _meta.autoresizingMask = NSViewMinXMargin; [self addSubview:_meta];
    }
    return self;
}
@end

@implementation ClipMakerController {
    NSWindow* _win;
    NSTextField* _stepHint; NSArray<GPPill*>* _steps;
    // left
    NSTableView* _sources; NSTextView* _idea; NSTextField* _musicLabel; NSSlider* _gain;
    NSButton* _syncBeats; NSButton* _keepVoice; NSPopUpButton* _provider; NSSecureTextField* _key;
    NSTextField* _model; NSTextField* _baseURL; NSTextField* _minLen; NSTextField* _maxLen; NSPopUpButton* _clips; NSPopUpButton* _slideDur;
    NSPopUpButton* _style; NSPopUpButton* _fontSize; NSPopUpButton* _font; NSPopUpButton* _capPos; NSPopUpButton* _hookPos;
    NSButton* _reframe; NSButton* _kenBurns; NSButton* _hook;
    GPButton* _analyzeBtn; GPButton* _generateBtn; GPButton* _revealBtn; GPButton* _analysisBtn;
    // center
    AVPlayerView* _playerView; NSImageView* _imagePreview; TimelineView* _timeline; NSTextField* _status; GPProgress* _progress; NSTextField* _beatInfo;
    // right
    NSTableView* _cands; NSTextField* _planSub;
    // analysis sheet
    NSWindow* _sheet; NSTextView* _scriptView; NSTextView* _transcriptView; NSTextView* _publishView; NSArray<GPButton*>* _tabBtns; NSTabView* _tabs;
    // state
    std::vector<MediaInfo> _media; std::vector<Transcript> _transcripts; std::vector<Candidate> _candidates;
    std::vector<std::string> _visuals; Script _script; std::string _ideaText;
    BeatGrid _beats; std::string _lastOutput; Project _project;
    bool _busy; id _boundaryObserver; id _timeObserver;
}

// ------------------------------------------------------------------ window
- (void)applicationDidFinishLaunching:(NSNotification*)n {
    [self buildMenu];
    const CGFloat W = 1320, H = 960, L = 334, R = 400, M = 14, HEAD = 58;
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView
            backing:NSBackingStoreBuffered defer:NO];
    _win.title = @"ClipMaker"; _win.delegate = self; _win.restorable = NO;
    _win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _win.minSize = NSMakeSize(1120, 900);
    _win.titlebarAppearsTransparent = YES; _win.titleVisibility = NSWindowTitleHidden;
    _win.backgroundColor = gp::bg();
    [_win center];
    NSView* root = _win.contentView;
    root.wantsLayer = YES; root.layer.backgroundColor = gp::bg().CGColor;

    // ---------------- header: brand + steps
    NSView* head = [[NSView alloc] initWithFrame:NSMakeRect(0, H - HEAD, W, HEAD)];
    head.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin; [root addSubview:head];
    NSTextField* brand = label(@"", NSMakeRect(84, 19, 330, 22), gp::heading(15), gp::text(), head);
    NSMutableAttributedString* bs = [[NSMutableAttributedString alloc] init];
    [bs appendAttributedString:[[NSAttributedString alloc] initWithString:@"GEEKATPLAY" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightHeavy], NSForegroundColorAttributeName: gp::accent(), NSKernAttributeName: @2.2}]];
    [bs appendAttributedString:[[NSAttributedString alloc] initWithString:@" STUDIO" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightLight], NSForegroundColorAttributeName: gp::muted(), NSKernAttributeName: @2.2}]];
    [bs appendAttributedString:[[NSAttributedString alloc] initWithString:@"   ClipMaker" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: gp::text()}]];
    brand.attributedStringValue = bs;
    NSMutableArray* steps = [NSMutableArray array]; NSArray* names = @[@"1  Media & brief", @"2  Edit plan", @"3  Render"];
    CGFloat sx = W / 2 - 230;
    for (NSUInteger i = 0; i < 3; ++i) {
        GPPill* p = [[GPPill alloc] initWithFrame:NSMakeRect(sx + i * 158, 19, 148, 22)];
        p.label = names[i]; p.color = i == 0 ? gp::accent() : gp::faint(); p.filled = i == 0; p.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
        [head addSubview:p]; [steps addObject:p];
    }
    _steps = steps;
    NSTextField* by = label(@"Vladimir Chopine · geekatplay.com", NSMakeRect(W - 262, 21, 246, 16), gp::body(11), gp::faint(), head);
    by.alignment = NSTextAlignmentRight; by.autoresizingMask = NSViewMinXMargin;

    CGFloat colH = H - HEAD - M;   // columns span from bottom margin to header
    // ---------------- left card
    GPCard* left = [[GPCard alloc] initWithFrame:NSMakeRect(M, M, L, colH - M)];
    left.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin; [root addSubview:left];
    CGFloat y = left.frame.size.height - 30, w = L;

    section(@"Sources", y, w, left); y -= 100;
    NSScrollView* sv = darkScroll(NSMakeRect(16, y, w - 32, 90));
    _sources = [[NSTableView alloc] initWithFrame:sv.bounds];
    NSTableColumn* sc = [[NSTableColumn alloc] initWithIdentifier:@"src"]; sc.width = w - 40; [_sources addTableColumn:sc];
    _sources.headerView = nil; _sources.dataSource = self; _sources.delegate = self; _sources.rowHeight = 32;
    _sources.backgroundColor = NSColor.clearColor; _sources.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _sources.intercellSpacing = NSMakeSize(0, 0); _sources.style = NSTableViewStylePlain;
    [_sources registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    sv.documentView = _sources; [left addSubview:sv];
    y -= 34;
    gpbutton(@"Add media", @"plus", 1, NSMakeRect(16, y, 118, 28), self, @selector(addSources:), left);
    gpbutton(@"Remove", @"minus", 2, NSMakeRect(140, y, 90, 28), self, @selector(removeSource:), left);
    label(@"or drop files", NSMakeRect(236, y + 6, 90, 16), gp::body(11), gp::faint(), left);

    y -= 34; section(@"Idea · brief", y, w, left); y -= 78;
    NSScrollView* isv = darkScroll(NSMakeRect(16, y, w - 32, 70));
    _idea = [[NSTextView alloc] initWithFrame:isv.bounds];
    _idea.font = gp::body(12.5); _idea.richText = NO; _idea.autoresizingMask = NSViewWidthSizable; _idea.textColor = gp::text();
    _idea.backgroundColor = NSColor.clearColor; _idea.drawsBackground = NO; _idea.insertionPointColor = gp::accent();
    _idea.textContainerInset = NSMakeSize(8, 8);
    _idea.string = [[NSUserDefaults standardUserDefaults] stringForKey:@"idea"] ?: @"";
    isv.documentView = _idea; [left addSubview:isv];

    y -= 34; section(@"Music · rhythm", y, w, left); y -= 28;
    _musicLabel = label(@"No music — optional", NSMakeRect(18, y + 4, w - 140, 18), gp::body(12), gp::muted(), left); _musicLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    gpbutton(@"Choose", @"music.note", 1, NSMakeRect(w - 112, y, 96, 28), self, @selector(chooseMusic:), left);
    y -= 28;
    label(@"Level", NSMakeRect(18, y + 2, 44, 16), gp::body(11.5), gp::muted(), left);
    _gain = [[NSSlider alloc] initWithFrame:NSMakeRect(62, y, w - 80, 20)];
    _gain.minValue = 0; _gain.maxValue = 1; _gain.doubleValue = 0.2; _gain.autoresizingMask = NSViewMinYMargin; _gain.controlSize = NSControlSizeSmall;
    [left addSubview:_gain];
    y -= 26;
    _syncBeats = check(@"Sync cuts to beats", NSMakeRect(16, y, 150, 18), YES, left);
    _keepVoice = check(@"Keep original voice", NSMakeRect(172, y, 150, 18), YES, left);

    y -= 34; section(@"Engine", y, w, left); y -= 30;
    _provider = popup(@[@"Offline ranking (no network)", @"Claude API", @"Ollama (local model)", @"OpenAI-compatible server"], NSMakeRect(14, y, w - 28, 26), left);
    _provider.target = self; _provider.action = @selector(providerChanged:);
    y -= 28;
    _key = (NSSecureTextField*)field(@"API key (or ANTHROPIC_API_KEY env)", NSMakeRect(16, y, w - 32, 24), left, YES);
    y -= 28;
    _model = field(@"Model (blank = default)", NSMakeRect(16, y, 150, 24), left, NO);
    _baseURL = field(@"Base URL (optional)", NSMakeRect(172, y, w - 188, 24), left, NO);

    y -= 36; section(@"Output", y, w, left); y -= 30;
    label(@"Length", NSMakeRect(18, y + 4, 48, 16), gp::body(11.5), gp::muted(), left);
    _minLen = field(@"min", NSMakeRect(66, y, 48, 24), left, NO); _minLen.stringValue = @"20"; _minLen.alignment = NSTextAlignmentCenter;
    label(@"–", NSMakeRect(118, y + 4, 10, 16), gp::body(11.5), gp::muted(), left);
    _maxLen = field(@"max", NSMakeRect(130, y, 48, 24), left, NO); _maxLen.stringValue = @"40"; _maxLen.alignment = NSTextAlignmentCenter;
    label(@"s", NSMakeRect(182, y + 4, 12, 16), gp::body(11.5), gp::muted(), left);
    label(@"Clips", NSMakeRect(206, y + 4, 40, 16), gp::body(11.5), gp::muted(), left);
    _clips = popup(@[@"1", @"2", @"3", @"4", @"5", @"6", @"8"], NSMakeRect(244, y - 1, 70, 26), left); [_clips selectItemAtIndex:3];
    y -= 28;
    label(@"Image slide", NSMakeRect(18, y + 4, 76, 16), gp::body(11.5), gp::muted(), left);
    _slideDur = popup(@[@"2 s", @"3 s", @"4 s", @"5 s", @"6 s", @"8 s"], NSMakeRect(92, y - 1, 72, 26), left); [_slideDur selectItemAtIndex:2];
    label(@"slow pan + zoom", NSMakeRect(172, y + 4, 140, 16), gp::body(11), gp::faint(), left);
    y -= 28;
    label(@"Captions", NSMakeRect(18, y + 4, 56, 16), gp::body(11.5), gp::muted(), left);
    _style = popup(@[@"Bold pop", @"Karaoke highlight", @"Minimal pill", @"Outline", @"None"], NSMakeRect(76, y - 1, 148, 26), left);
    _fontSize = popup(@[@"48", @"56", @"64", @"72", @"84"], NSMakeRect(230, y - 1, 84, 26), left); [_fontSize selectItemAtIndex:2];
    y -= 28;
    label(@"Position", NSMakeRect(18, y + 4, 56, 16), gp::body(11.5), gp::muted(), left);
    _capPos = popup(@[@"Top", @"Upper", @"Center", @"Lower", @"Bottom"], NSMakeRect(76, y - 1, 96, 26), left); [_capPos selectItemAtIndex:3];
    label(@"Hook", NSMakeRect(180, y + 4, 36, 16), gp::body(11.5), gp::muted(), left);
    _hookPos = popup(@[@"Top", @"Upper", @"Center", @"Lower", @"Bottom"], NSMakeRect(218, y - 1, 96, 26), left); [_hookPos selectItemAtIndex:0];
    y -= 28;
    label(@"Font", NSMakeRect(18, y + 4, 40, 16), gp::body(11.5), gp::muted(), left);
    _font = popup(@[@"Helvetica-Bold", @"AvenirNext-Heavy", @"Futura-CondensedExtraBold", @"Impact", @"ArialRoundedMTBold", @"Menlo-Bold"], NSMakeRect(76, y - 1, 238, 26), left);
    y -= 28;
    _reframe = check(@"Smart 9:16 reframe", NSMakeRect(16, y, 150, 18), YES, left);
    _kenBurns = check(@"Subtle zoom", NSMakeRect(172, y, 120, 18), YES, left);
    y -= 24;
    _hook = check(@"Show hook title", NSMakeRect(16, y, 150, 18), YES, left);

    _analyzeBtn = gpbutton(@"Analyze footage", @"waveform.and.magnifyingglass", 1, NSMakeRect(16, 58, w - 32, 36), self, @selector(analyze:), left);
    _analyzeBtn.autoresizingMask = NSViewMaxYMargin; _analyzeBtn.keyEquivalent = @"a"; _analyzeBtn.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _generateBtn = gpbutton(@"Generate short", @"bolt.fill", 0, NSMakeRect(16, 16, w - 32, 36), self, @selector(generate:), left);
    _generateBtn.autoresizingMask = NSViewMaxYMargin; _generateBtn.keyEquivalent = @"\r"; _generateBtn.enabled = NO;

    // ---------------- center
    NSView* center = [[NSView alloc] initWithFrame:NSMakeRect(M + L + M, M, W - L - R - 4 * M, colH - M)];
    center.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; [root addSubview:center];
    CGFloat cw = center.frame.size.width, ch = center.frame.size.height;
    GPCard* previewCard = [[GPCard alloc] initWithFrame:NSMakeRect(0, 150, cw, ch - 150)];
    previewCard.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; previewCard.fill = gp::subtle(); [center addSubview:previewCard];
    _playerView = [[AVPlayerView alloc] initWithFrame:NSInsetRect(previewCard.bounds, 12, 12)];
    _playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _playerView.controlsStyle = AVPlayerViewControlsStyleInline; _playerView.showsFullScreenToggleButton = YES;
    _playerView.wantsLayer = YES; _playerView.layer.backgroundColor = NSColor.blackColor.CGColor; _playerView.layer.cornerRadius = 10; _playerView.layer.masksToBounds = YES;
    [previewCard addSubview:_playerView];
    _imagePreview = [[NSImageView alloc] initWithFrame:_playerView.frame];
    _imagePreview.autoresizingMask = _playerView.autoresizingMask; _imagePreview.imageScaling = NSImageScaleProportionallyUpOrDown;
    _imagePreview.wantsLayer = YES; _imagePreview.layer.backgroundColor = NSColor.blackColor.CGColor; _imagePreview.layer.cornerRadius = 10; _imagePreview.layer.masksToBounds = YES;
    _imagePreview.hidden = YES; [previewCard addSubview:_imagePreview];

    _timeline = [[TimelineView alloc] initWithFrame:NSMakeRect(0, 78, cw, 60)];
    _timeline.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin; _timeline.playhead = -1; [center addSubview:_timeline];

    GPCard* statusCard = [[GPCard alloc] initWithFrame:NSMakeRect(0, 0, cw, 66)];
    statusCard.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin; [center addSubview:statusCard];
    _status = label(@"Add videos or images, describe the short you want, then Analyze.", NSMakeRect(16, 38, cw - 290, 18), gp::body(12), gp::text(), statusCard);
    _status.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _beatInfo = label(@"", NSMakeRect(16, 20, cw - 290, 15), gp::body(10.5), gp::faint(), statusCard);
    _beatInfo.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _progress = [[GPProgress alloc] initWithFrame:NSMakeRect(16, 6, cw - 290, 10)];
    _progress.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin; [statusCard addSubview:_progress];
    _analysisBtn = gpbutton(@"Edit plan", @"doc.text.magnifyingglass", 1, NSMakeRect(cw - 262, 19, 118, 28), self, @selector(showAnalysis:), statusCard);
    _analysisBtn.autoresizingMask = NSViewMinXMargin; _analysisBtn.enabled = NO;
    _revealBtn = gpbutton(@"Finder", @"folder", 2, NSMakeRect(cw - 138, 19, 122, 28), self, @selector(reveal:), statusCard);
    _revealBtn.autoresizingMask = NSViewMinXMargin; _revealBtn.enabled = NO;

    // ---------------- right card: edit plan
    GPCard* right = [[GPCard alloc] initWithFrame:NSMakeRect(W - R - M, M, R, colH - M)];
    right.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin; [root addSubview:right];
    CGFloat rh = right.frame.size.height;
    label(@"Edit plan", NSMakeRect(18, rh - 34, 200, 20), gp::heading(15), gp::text(), right);
    _planSub = label(@"Moments appear here after Analyze", NSMakeRect(18, rh - 52, R - 36, 15), gp::body(11), gp::faint(), right);
    label(@"tick to include · double-click to preview · click the title to rename", NSMakeRect(18, rh - 70, R - 36, 14), gp::body(10.5), gp::faint(), right);
    NSScrollView* csv = darkScroll(NSMakeRect(12, 12, R - 24, rh - 92));
    csv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _cands = [[NSTableView alloc] initWithFrame:csv.bounds];
    NSTableColumn* cc = [[NSTableColumn alloc] initWithIdentifier:@"plan"]; cc.width = R - 40; [_cands addTableColumn:cc];
    _cands.headerView = nil; _cands.dataSource = self; _cands.delegate = self; _cands.rowHeight = 46;
    _cands.backgroundColor = NSColor.clearColor; _cands.intercellSpacing = NSMakeSize(0, 2); _cands.style = NSTableViewStylePlain;
    _cands.doubleAction = @selector(previewCandidate:); _cands.target = self;
    csv.documentView = _cands; [right addSubview:csv];

    [self loadDefaults];
    [self providerChanged:nil];
    [self setStep:0];
    [_win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (getenv("CLIPMAKER_SHOT_DIR")) [self performSelector:@selector(runScreenshotTour) withObject:nil afterDelay:0.5];
}

- (void)setStep:(int)s {
    for (NSUInteger i = 0; i < _steps.count; ++i) { _steps[i].filled = (int)i == s; _steps[i].color = (int)i <= s ? gp::accent() : gp::faint(); }
}

- (void)buildMenu {
    NSMenu* bar = [[NSMenu alloc] init];
    NSMenuItem* appItem = [[NSMenuItem alloc] init]; [bar addItem:appItem];
    NSMenu* app = [[NSMenu alloc] init];
    [app addItemWithTitle:@"About ClipMaker" action:@selector(showAbout:) keyEquivalent:@""];
    [app addItemWithTitle:@"Geekatplay Studio website" action:@selector(openSite:) keyEquivalent:@""];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Quit ClipMaker" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = app;
    NSMenuItem* fileItem = [[NSMenuItem alloc] init]; [bar addItem:fileItem];
    NSMenu* file = [[NSMenu alloc] initWithTitle:@"File"];
    [file addItemWithTitle:@"Add Media…" action:@selector(addSources:) keyEquivalent:@"o"];
    [file addItemWithTitle:@"Choose Music…" action:@selector(chooseMusic:) keyEquivalent:@"m"];
    [file addItem:[NSMenuItem separatorItem]];
    [file addItemWithTitle:@"Open Output Folder" action:@selector(openOutputFolder:) keyEquivalent:@"O"];
    fileItem.submenu = file;
    NSMenuItem* editItem = [[NSMenuItem alloc] init]; [bar addItem:editItem];
    NSMenu* edit = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;
    NSApp.mainMenu = bar;
}
- (void)showAbout:(id)sender {
    NSMutableAttributedString* credits = [[NSMutableAttributedString alloc] initWithString:@"Vertical shorts from your footage — transcript-driven editing, beat-synced cuts, smart reframe, captions.\n\nDesign & development: Vladimir Chopine\nGeekatplay Studio · geekatplay.com"
        attributes:@{NSFontAttributeName: gp::body(11), NSForegroundColorAttributeName: NSColor.labelColor}];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{NSAboutPanelOptionCredits: credits, NSAboutPanelOptionApplicationName: @"ClipMaker",
        NSAboutPanelOptionVersion: @"0.2", NSAboutPanelOptionApplicationVersion: @"Geekatplay Studio"}];
}
- (void)openSite:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.geekatplay.com"]]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)a { return YES; }
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication*)a { return YES; }
- (void)applicationWillTerminate:(NSNotification*)n { [self saveDefaults]; }
- (void)application:(NSApplication*)app openURLs:(NSArray<NSURL*>*)urls {
    NSMutableArray* p = [NSMutableArray array]; for (NSURL* u in urls) [p addObject:u.path]; [self addSourcePaths:p];
}

// ------------------------------------------------------------------ defaults
- (void)loadDefaults {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    [_provider selectItemAtIndex:[d integerForKey:@"provider"]];
    _key.stringValue = [d stringForKey:@"apiKey"] ?: @"";
    _model.stringValue = [d stringForKey:@"model"] ?: @"";
    _baseURL.stringValue = [d stringForKey:@"baseURL"] ?: @"";
    if ([d objectForKey:@"minLen"]) _minLen.stringValue = [d stringForKey:@"minLen"];
    if ([d objectForKey:@"maxLen"]) _maxLen.stringValue = [d stringForKey:@"maxLen"];
    if ([d objectForKey:@"slideDur"]) [_slideDur selectItemAtIndex:[d integerForKey:@"slideDur"]];
    if ([d objectForKey:@"capPos"]) [_capPos selectItemAtIndex:[d integerForKey:@"capPos"]];
    if ([d objectForKey:@"hookPos"]) [_hookPos selectItemAtIndex:[d integerForKey:@"hookPos"]];
    if ([d objectForKey:@"clips"]) [_clips selectItemAtIndex:[d integerForKey:@"clips"]];
    if ([d objectForKey:@"style"]) [_style selectItemAtIndex:[d integerForKey:@"style"]];
    if ([d objectForKey:@"fontSize"]) [_fontSize selectItemAtIndex:[d integerForKey:@"fontSize"]];
    if ([d objectForKey:@"font"]) [_font selectItemAtIndex:[d integerForKey:@"font"]];
    if ([d objectForKey:@"gain"]) _gain.doubleValue = [d doubleForKey:@"gain"];
    if (NSString* m = [d stringForKey:@"music"]) if (m.length && [[NSFileManager defaultManager] fileExistsAtPath:m]) [self setMusic:m];
    for (NSString* p in [d arrayForKey:@"sources"] ?: @[]) if ([[NSFileManager defaultManager] fileExistsAtPath:p]) [self addSourcePaths:@[p]];
}
- (void)saveDefaults {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    [d setInteger:_provider.indexOfSelectedItem forKey:@"provider"];
    [d setObject:_key.stringValue forKey:@"apiKey"];
    [d setObject:_model.stringValue forKey:@"model"];
    [d setObject:_baseURL.stringValue forKey:@"baseURL"];
    [d setObject:_minLen.stringValue forKey:@"minLen"]; [d setObject:_maxLen.stringValue forKey:@"maxLen"];
    [d setInteger:_slideDur.indexOfSelectedItem forKey:@"slideDur"];
    [d setInteger:_capPos.indexOfSelectedItem forKey:@"capPos"]; [d setInteger:_hookPos.indexOfSelectedItem forKey:@"hookPos"];
    [d setInteger:_clips.indexOfSelectedItem forKey:@"clips"];
    [d setInteger:_style.indexOfSelectedItem forKey:@"style"];
    [d setInteger:_fontSize.indexOfSelectedItem forKey:@"fontSize"];
    [d setInteger:_font.indexOfSelectedItem forKey:@"font"];
    [d setDouble:_gain.doubleValue forKey:@"gain"];
    [d setObject:_idea.string forKey:@"idea"];
    [d setObject:S([self settings].musicPath) forKey:@"music"];
    NSMutableArray* src = [NSMutableArray array]; for (auto& m : _media) [src addObject:S(m.path)];
    [d setObject:src forKey:@"sources"];
}

- (Settings)settings {
    Settings s;
    s.provider = (Settings::Provider)_provider.indexOfSelectedItem;
    s.apiKey = U(_key.stringValue); s.model = U(_model.stringValue); s.baseURL = U(_baseURL.stringValue);
    if (s.apiKey.empty() && s.provider == Settings::Anthropic) if (const char* k = getenv("ANTHROPIC_API_KEY")) s.apiKey = k;
    s.minLength = std::max(3.0, _minLen.doubleValue); s.maxLength = std::max(s.minLength + 2, _maxLen.doubleValue);
    s.maxClips = _clips.titleOfSelectedItem.intValue;
    s.maxClip = std::min(20.0, std::max(5.0, s.maxLength / std::max(1, s.maxClips) * 1.6));
    s.slideDuration = _slideDur.titleOfSelectedItem.doubleValue;
    s.captionPos = (ScreenPos)_capPos.indexOfSelectedItem; s.hookPos = (ScreenPos)_hookPos.indexOfSelectedItem;
    s.musicPath = U(_musicLabel.toolTip);
    s.musicGain = _gain.doubleValue;
    s.keepVoice = _keepVoice.state == NSControlStateValueOn;
    s.syncToBeats = _syncBeats.state == NSControlStateValueOn;
    s.captionStyle = (CaptionStyle)_style.indexOfSelectedItem;
    s.fontSize = _fontSize.titleOfSelectedItem.doubleValue;
    s.fontName = U(_font.titleOfSelectedItem);
    s.smartReframe = _reframe.state == NSControlStateValueOn;
    s.kenBurns = _kenBurns.state == NSControlStateValueOn;
    s.showHook = _hook.state == NSControlStateValueOn;
    return s;
}

// ------------------------------------------------------------------ actions
- (void)providerChanged:(id)sender {
    NSInteger p = _provider.indexOfSelectedItem;
    _key.enabled = p == 1 || p == 3; _model.enabled = p != 0; _baseURL.enabled = p != 0;
    _model.placeholderString = p == 1 ? @"claude-sonnet-5-5" : p == 2 ? @"llama3.1" : p == 3 ? @"gpt-4o-mini" : @"—";
    _baseURL.placeholderString = p == 2 ? @"http://localhost:11434" : p == 3 ? @"https://api.openai.com/v1" : @"Base URL (optional)";
}
- (void)addSources:(id)sender {
    NSOpenPanel* p = [NSOpenPanel openPanel];
    p.allowsMultipleSelection = YES; p.canChooseDirectories = NO;
    p.allowedContentTypes = @[UTTypeMovie, UTTypeVideo, UTTypeMPEG4Movie, UTTypeQuickTimeMovie, UTTypeImage];
    [p beginSheetModalForWindow:_win completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK) return;
        NSMutableArray* paths = [NSMutableArray array]; for (NSURL* u in p.URLs) [paths addObject:u.path];
        [self addSourcePaths:paths];
    }];
}
- (void)addSourcePaths:(NSArray<NSString*>*)paths {
    for (NSString* p in paths) {
        bool dup = false; for (auto& m : _media) if (m.path == U(p)) dup = true;
        if (dup) continue;
        MediaInfo m = probeMedia(U(p));
        if (!m.ok) { [self setStatus:[NSString stringWithFormat:@"Cannot read %@: %@", p.lastPathComponent, S(m.error)]]; continue; }
        _media.push_back(m); _transcripts.push_back({});
    }
    [_sources reloadData];
    _candidates.clear(); [_cands reloadData]; _generateBtn.enabled = NO; _analysisBtn.enabled = NO;
    if (!_media.empty()) {
        [self setStatus:[NSString stringWithFormat:@"%zu source%@ loaded. Click one to check it, describe your idea, then Analyze.", _media.size(), _media.size() == 1 ? @"" : @"s"]];
        [_sources selectRowIndexes:[NSIndexSet indexSetWithIndex:_media.size() - 1] byExtendingSelection:NO];
        [self previewSource:(NSInteger)_media.size() - 1];
    }
}
- (void)removeSource:(id)sender {
    NSInteger r = _sources.selectedRow;
    if (r < 0 || r >= (NSInteger)_media.size()) return;
    _media.erase(_media.begin() + r); _transcripts.erase(_transcripts.begin() + r);
    _candidates.clear(); [_sources reloadData]; [_cands reloadData]; _generateBtn.enabled = NO; _analysisBtn.enabled = NO;
}
- (void)previewSource:(NSInteger)r {
    if (r < 0 || r >= (NSInteger)_media.size()) return;
    auto& m = _media[r];
    if (m.isImage) {
        [_playerView.player pause];
        _imagePreview.image = [[NSImage alloc] initWithContentsOfFile:S(m.path)];
        _imagePreview.hidden = NO; _playerView.hidden = YES;
        [self setStatus:[NSString stringWithFormat:@"Image %@  %dx%d — plays as a %@ slide with pan and zoom", S(m.path).lastPathComponent, m.width, m.height, _slideDur.titleOfSelectedItem]];
    } else {
        [self playFile:S(m.path) from:0 to:-1];
        [self setStatus:[NSString stringWithFormat:@"Source %@  %@  %dx%d  %@", S(m.path).lastPathComponent, S(fmtTime(m.duration)), m.width, m.height, m.hasAudio ? @"" : @"(no audio track!)"]];
    }
}
- (void)tableViewSelectionDidChange:(NSNotification*)n {
    if (n.object == _sources) [self previewSource:_sources.selectedRow];
}
- (void)chooseMusic:(id)sender {
    NSOpenPanel* p = [NSOpenPanel openPanel];
    p.allowedContentTypes = @[UTTypeAudio, UTTypeMP3, UTTypeWAV, UTTypeMPEG4Audio, UTTypeAIFF];
    [p beginSheetModalForWindow:_win completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK) { [self setMusic:p.URL.path]; _beats = BeatGrid{}; }
    }];
}
- (void)setMusic:(NSString*)path { _musicLabel.stringValue = path.lastPathComponent; _musicLabel.textColor = gp::text(); _musicLabel.toolTip = path; }
- (void)openOutputFolder:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:S(outputDirectory())]]; }
- (void)reveal:(id)sender {
    if (!_lastOutput.empty()) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:S(_lastOutput)]]];
}
- (void)setStatus:(NSString*)s { _status.stringValue = s; }
- (void)progress:(double)f message:(const std::string&)m {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_progress.value = f; self->_status.stringValue = S(m); });
}
- (void)setBusy:(bool)b {
    _busy = b; _analyzeBtn.enabled = !b; _generateBtn.enabled = !b && !_candidates.empty();
    if (b) _progress.value = 0;
}
- (void)alert:(NSString*)title detail:(const std::string&)d {
    NSAlert* a = [[NSAlert alloc] init]; a.messageText = title; a.informativeText = S(d); a.alertStyle = NSAlertStyleWarning;
    [a beginSheetModalForWindow:_win completionHandler:nil];
}

// ------------------------------------------------------------------ analyze
- (void)analyze:(id)sender {
    if (_busy) return;
    if (_media.empty()) { [self alert:@"No sources" detail:"Add at least one video or image first."]; return; }
    bool anyVideo = false; for (auto& m : _media) anyVideo |= !m.isImage;
    if (!anyVideo) { [self alert:@"No video" detail:"Add at least one video with speech; images are added as slides between the moments."]; return; }
    [self saveDefaults];
    Settings s = [self settings];
    std::string idea = U(_idea.string); _ideaText = idea;
    [self setBusy:true];
    std::vector<MediaInfo> media = _media;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        auto prog = [self](double f, const std::string& m) { [self progress:f message:m]; };
        std::vector<Transcript> transcripts; std::string err;
        std::vector<std::string> visuals(media.size());
        for (size_t i = 0; i < media.size(); ++i) {
            Transcript t;
            if (media[i].isImage) {
                prog(double(i) / media.size() * 0.6, "Looking at " + media[i].path.substr(media[i].path.find_last_of('/') + 1));
                visuals[i] = describeFrame(media[i].path, -1);
                transcripts.push_back(t); continue;
            }
            if (!loadTranscriptCache(media[i].path, t)) {
                t = transcribeFile(media[i].path, s.locale, [&](double f, const std::string& m) {
                    prog((i + f * 0.8) / media.size() * 0.6, m); }, &err);
                if (!t.empty()) saveTranscriptCache(media[i].path, t);
            }
            if (t.empty()) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self setBusy:false]; [self alert:@"Transcription failed" detail:err.empty() ? "No speech found" : err]; });
                return;
            }
            transcripts.push_back(t);
        }
        BeatGrid beats;
        if (!s.musicPath.empty()) {
            prog(0.62, "Analysing music rhythm…");
            std::string e; auto pcm = decodeMonoPCM(s.musicPath, 22050, &e);
            beats = detectBeats(pcm, 22050);
        }
        std::vector<Candidate> cands; std::string aiErr, note; Script script;
        if (s.provider != Settings::Heuristic) {
            prog(0.68, "Building the edit plan, title and hashtags…");
            cands = aiSelectSegments(s, transcripts, media, visuals, idea, script, &aiErr);
            if (cands.empty()) note = "Engine unavailable (" + aiErr + ") — used offline ranking. ";
        }
        if (cands.empty()) cands = heuristicCandidates(transcripts, media, idea, s);
        refineCandidates(cands, transcripts, media, s);
        for (size_t i = 0; i < cands.size(); ++i) {
            auto& c = cands[i];
            prog(0.78 + 0.22 * i / cands.size(), "Describing & tracking moment " + std::to_string(i + 1) + "/" + std::to_string(cands.size()));
            if (c.isImage) { c.visual = visuals[c.sourceIndex]; continue; }
            c.visual = describeFrame(media[c.sourceIndex].path, c.start + c.duration() / 2);
            if (s.smartReframe) trackSubject(c, media[c.sourceIndex].path);
        }
        if (script.title.empty()) { Script h = heuristicScript(cands, media, idea, s); if (script.description.empty()) script.description = h.description; script.title = h.title; if (script.hashtags.empty()) script.hashtags = h.hashtags; }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_transcripts = transcripts; self->_beats = beats; self->_candidates = cands; self->_visuals = visuals; self->_script = script;
            [self->_cands reloadData];
            self->_beatInfo.stringValue = beats.empty() ? @"" : [NSString stringWithFormat:@"Music: %.0f BPM · %zu beats detected", beats.bpm, beats.beats.size()];
            [self setBusy:false];
            self->_analysisBtn.enabled = YES;
            self->_progress.value = 1;
            self->_planSub.stringValue = [NSString stringWithFormat:@"%zu moments proposed · target %@–%@ s", cands.size(), self->_minLen.stringValue, self->_maxLen.stringValue];
            [self setStatus:S(note + std::to_string(cands.size()) + " moments proposed. Review the plan, then Generate.")];
            [self setStep:1];
            [self showAnalysis:nil];
        });
    });
}

// ------------------------------------------------------------------ analysis sheet
static NSTextView* textTab(NSTabView* tabs, NSString* title, BOOL editable) {
    NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:title]; item.label = title;
    NSScrollView* sv = darkScroll(NSMakeRect(0, 0, 100, 100));
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTextView* tv = [[NSTextView alloc] initWithFrame:sv.bounds];
    tv.editable = editable; tv.richText = NO; tv.font = gp::mono(12); tv.textColor = gp::text();
    tv.backgroundColor = NSColor.clearColor; tv.drawsBackground = NO; tv.insertionPointColor = gp::accent();
    tv.textContainerInset = NSMakeSize(14, 14); tv.autoresizingMask = NSViewWidthSizable;
    tv.minSize = NSMakeSize(0, 0); tv.maxSize = NSMakeSize(1e7, 1e7); tv.verticallyResizable = YES; tv.horizontallyResizable = NO;
    tv.textContainer.widthTracksTextView = YES;
    sv.documentView = tv; item.view = sv; [tabs addTabViewItem:item];
    return tv;
}
- (NSString*)transcriptText {
    NSMutableString* t = [NSMutableString string];
    for (size_t i = 0; i < _media.size(); ++i) {
        [t appendFormat:@"═══ S%zu  %@%@\n", i + 1, S(_media[i].path).lastPathComponent, _media[i].isImage ? @"  (image)" : @""];
        if (_media[i].isImage) { [t appendFormat:@"    shows: %@\n\n", S(i < _visuals.size() ? _visuals[i] : std::string())]; continue; }
        for (auto& st : _transcripts[i].sentences) [t appendFormat:@"[%@ – %@]  %@\n", S(fmtTime(st.start)), S(fmtTime(st.end)), S(st.text)];
        [t appendString:@"\n"];
    }
    [t appendString:@"═══ SEGMENT DESCRIPTIONS (what the frames show)\n"];
    for (auto& c : _candidates)
        [t appendFormat:@"S%d %@–%@  score %.0f  ·  %@\n", c.sourceIndex + 1, S(fmtTime(c.start)), S(fmtTime(c.end)), c.score, S(c.visual.empty() ? "—" : c.visual)];
    return t;
}
- (void)showAnalysis:(id)sender {
    if (_candidates.empty()) return;
    if (!_sheet) {
        const CGFloat SW = 860, SH = 640;
        _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, SW, SH)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        _sheet.title = @"Edit plan"; _sheet.restorable = NO;
        _sheet.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSView* v = _sheet.contentView;
        v.wantsLayer = YES; v.layer.backgroundColor = gp::bg().CGColor;
        label(@"Edit plan", NSMakeRect(20, SH - 40, 300, 24), gp::heading(18), gp::text(), v).autoresizingMask = NSViewMinYMargin;
        label(@"Review what will be cut, read the transcript, polish the publish text — then approve.", NSMakeRect(20, SH - 60, SW - 40, 16), gp::body(11.5), gp::muted(), v).autoresizingMask = NSViewMinYMargin;
        _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(16, 60, SW - 32, SH - 170)];
        _tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; _tabs.tabViewType = NSNoTabsNoBorder;
        NSArray* names = @[@"Editing script", @"Transcript & frames", @"Title · description · hashtags"];
        NSArray* syms = @[@"list.number", @"text.quote", @"square.and.arrow.up"];
        NSMutableArray* tb = [NSMutableArray array];
        for (NSUInteger i = 0; i < names.count; ++i) {
            GPButton* b = gpbutton(names[i], syms[i], i == 0 ? 0 : 2, NSMakeRect(16 + i * 214, SH - 104, 206, 30), self, @selector(selectTab:), v);
            b.tag = i; b.autoresizingMask = NSViewMinYMargin; [tb addObject:b];
        }
        _tabBtns = tb;
        _scriptView = textTab(_tabs, names[0], YES);
        _transcriptView = textTab(_tabs, names[1], NO);
        _publishView = textTab(_tabs, names[2], YES);
        [v addSubview:_tabs];
        GPButton* ok = gpbutton(@"Approve & Generate", @"bolt.fill", 0, NSMakeRect(SW - 206, 14, 190, 34), self, @selector(approveAndGenerate:), v);
        ok.keyEquivalent = @"\r"; ok.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        GPButton* close = gpbutton(@"Close", nil, 1, NSMakeRect(SW - 300, 14, 86, 34), self, @selector(closeAnalysis:), v);
        close.keyEquivalent = @"\033"; close.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        gpbutton(@"Copy publish text", @"doc.on.doc", 1, NSMakeRect(16, 14, 170, 34), self, @selector(copyPublish:), v).autoresizingMask = NSViewMaxYMargin;
        gpbutton(@"Re-run analysis", @"arrow.clockwise", 2, NSMakeRect(192, 14, 150, 34), self, @selector(rerunAnalysis:), v).autoresizingMask = NSViewMaxYMargin;
    }
    NSString* intro = _script.narrative.empty() ? @"" : [NSString stringWithFormat:@"RATIONALE\n%@\n\n", S(_script.narrative)];
    _scriptView.string = [NSString stringWithFormat:@"%@PLAN (what will be cut, in order — tick/untick and rename moments in the main window)\n%@\n\nFinal length target: %@–%@ s.  Edit the publish tab freely; approve to render.",
                          intro, S(describeScript(_candidates, _media)), _minLen.stringValue, _maxLen.stringValue];
    _transcriptView.string = [self transcriptText];
    _publishView.string = S(_script.publishText());
    [self selectTab:_tabBtns[0]];
    [_win beginSheet:_sheet completionHandler:nil];
    if (getenv("CLIPMAKER_SHOT_DIR")) [self performSelector:@selector(shotSheet) withObject:nil afterDelay:0.8];
}
- (void)selectTab:(NSButton*)sender {
    [_tabs selectTabViewItemAtIndex:sender.tag];
    for (GPButton* b in _tabBtns) { b.style = b.tag == sender.tag ? 0 : 2; [b setNeedsDisplay:YES]; }
}
- (void)syncPublishFromView {
    NSArray* lines = [_publishView.string componentsSeparatedByString:@"\n"];
    std::string mode, title, desc, tags;
    for (NSString* l in lines) {
        std::string x = U(l);
        if (x == "TITLE" || x == "DESCRIPTION" || x == "HASHTAGS") { mode = x; continue; }
        if (mode == "TITLE" && !trim(x).empty()) title += (title.empty() ? "" : " ") + trim(x);
        else if (mode == "DESCRIPTION") desc += x + "\n";
        else if (mode == "HASHTAGS") tags += x + " ";
    }
    _script.title = title; _script.description = trim(desc); _script.hashtags.clear();
    std::istringstream is(tags); std::string w; while (is >> w) _script.hashtags.push_back(w);
}
- (void)copyPublish:(id)sender {
    [self syncPublishFromView];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:S(_script.publishText()) forType:NSPasteboardTypeString];
    [self setStatus:@"Title, description and hashtags copied to the clipboard."];
}
- (void)closeAnalysis:(id)sender { [self syncPublishFromView]; [_win endSheet:_sheet]; _generateBtn.enabled = !_candidates.empty(); }
- (void)approveAndGenerate:(id)sender { [self closeAnalysis:sender]; [self generate:sender]; }
- (void)rerunAnalysis:(id)sender { [self closeAnalysis:sender]; [self analyze:sender]; }

// ------------------------------------------------------------------ generate
- (void)generate:(id)sender {
    if (_busy || _candidates.empty()) return;
    [self saveDefaults];
    Settings s = [self settings];
    Project p = buildProject(_candidates, _transcripts, _media, s, _beats);
    if (p.clips.empty()) { [self alert:@"Nothing selected" detail:"Tick at least one moment."]; return; }
    _project = p;
    std::vector<double> d; std::vector<int> src;
    for (auto& k : p.clips) { d.push_back(k.duration()); int si = 0; for (size_t i = 0; i < _media.size(); ++i) if (_media[i].path == k.sourcePath) si = (int)i; src.push_back(si); }
    std::vector<double> rel; for (double b : p.musicBeats.beats) rel.push_back(b - p.musicOffset);
    [_timeline setClipDurations:d sources:src beats:rel total:p.duration()];
    NSDateFormatter* f = [[NSDateFormatter alloc] init]; f.dateFormat = @"yyyyMMdd-HHmmss";
    std::string out = outputDirectory() + "/short-" + U([f stringFromDate:[NSDate date]]) + ".mp4";
    [self setBusy:true]; [self setStep:2];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        std::string err;
        bool ok = renderProject(p, out, [self](double f, const std::string& m) { [self progress:f message:m]; }, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:false];
            if (!ok) { [self alert:@"Render failed" detail:err]; return; }
            self->_lastOutput = out; self->_revealBtn.enabled = YES;
            saveSidecar(out, self->_script, describeScript(self->_candidates, self->_media));
            [self setStatus:[NSString stringWithFormat:@"Saved %@  (%.1f s) · publish text saved next to it", S(out).lastPathComponent, p.duration()]];
            [self playFile:S(out) from:0 to:-1];
            if (getenv("CLIPMAKER_SHOT_DIR")) [self performSelector:@selector(shotDone) withObject:nil afterDelay:1.5];
        });
    });
}

// ------------------------------------------------------------------ preview
- (void)playFile:(NSString*)path from:(double)a to:(double)b {
    _imagePreview.hidden = YES; _playerView.hidden = NO;
    AVPlayer* old = _playerView.player;
    if (old) { if (_boundaryObserver) [old removeTimeObserver:_boundaryObserver]; if (_timeObserver) [old removeTimeObserver:_timeObserver]; }
    _boundaryObserver = nil; _timeObserver = nil;
    AVPlayer* pl = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    _playerView.player = pl;
    __weak ClipMakerController* weak = self;
    __weak AVPlayer* weakPl = pl;
    if (b > a) {
        [pl seekToTime:CMTimeMakeWithSeconds(a, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        _boundaryObserver = [pl addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:CMTimeMakeWithSeconds(b, 600)]] queue:dispatch_get_main_queue() usingBlock:^{ [weakPl pause]; }];
    } else {
        _timeObserver = [pl addPeriodicTimeObserverForInterval:CMTimeMake(1, 20) queue:dispatch_get_main_queue() usingBlock:^(CMTime t) {
            ClipMakerController* s = weak; if (s) s->_timeline.playhead = CMTimeGetSeconds(t);
        }];
    }
    [pl play];
}
- (void)previewCandidate:(id)sender { [self previewRow:_cands.clickedRow]; }
- (void)previewRow:(NSInteger)r {
    if (r < 0 || r >= (NSInteger)_candidates.size()) return;
    auto& c = _candidates[r];
    if (c.isImage) { [self previewSource:c.sourceIndex]; return; }
    [self playFile:S(_media[c.sourceIndex].path) from:c.start to:c.end];
    [self setStatus:[NSString stringWithFormat:@"Preview %@–%@  ·  %@", S(fmtTime(c.start)), S(fmtTime(c.end)), S(c.reason)]];
}

// ------------------------------------------------------------------ tables (view-based)
- (NSInteger)numberOfRowsInTableView:(NSTableView*)t { return t == _sources ? _media.size() : _candidates.size(); }
- (NSTableRowView*)tableView:(NSTableView*)t rowViewForRow:(NSInteger)r { return [[GPRowView alloc] init]; }
- (NSView*)tableView:(NSTableView*)t viewForTableColumn:(NSTableColumn*)c row:(NSInteger)r {
    if (t == _sources) {
        SourceRow* v = [t makeViewWithIdentifier:@"src" owner:self];
        if (!v) { v = [[SourceRow alloc] initWithFrame:NSMakeRect(0, 0, c.width, 32)]; v.identifier = @"src"; }
        auto& m = _media[r];
        v.icon.image = gp::symbol(m.isImage ? @"photo" : @"film", 13);
        v.name.stringValue = S(m.path).lastPathComponent;
        v.meta.stringValue = m.isImage ? [NSString stringWithFormat:@"%dx%d", m.width, m.height] : [NSString stringWithFormat:@"%@ · %dp", S(fmtTime(m.duration)), m.height];
        return v;
    }
    PlanRow* v = [t makeViewWithIdentifier:@"plan" owner:self];
    if (!v) { v = [[PlanRow alloc] initWithFrame:NSMakeRect(0, 0, c.width, 46)]; v.identifier = @"plan"; v.on.target = self; v.on.action = @selector(toggleRow:); v.hook.delegate = self; }
    auto& k = _candidates[r];
    v.on.tag = r; v.hook.tag = r;
    v.on.state = k.selected ? NSControlStateValueOn : NSControlStateValueOff;
    v.score.label = [NSString stringWithFormat:@"%.0f", k.score];
    v.score.color = k.isImage ? gp::alt() : k.score >= 70 ? gp::green() : k.score >= 40 ? gp::accent() : gp::faint();
    v.score.filled = k.score >= 70 && !k.isImage;
    v.icon.image = gp::symbol(k.isImage ? @"photo" : @"film", 12);
    v.time.stringValue = k.isImage ? [NSString stringWithFormat:@"S%d · slide %.0f s", k.sourceIndex + 1, k.duration()]
                                   : [NSString stringWithFormat:@"S%d · %@ – %@ · %.1f s", k.sourceIndex + 1, S(fmtTime(k.start)), S(fmtTime(k.end)), k.duration()];
    v.hook.stringValue = S(k.hook);
    v.toolTip = [NSString stringWithFormat:@"%@\nShows: %@\n\n“%@”", S(k.reason), S(k.visual), S(k.text)];
    v.alphaValue = k.selected ? 1.0 : 0.45;
    return v;
}
- (void)toggleRow:(NSButton*)b {
    if (b.tag < 0 || b.tag >= (NSInteger)_candidates.size()) return;
    _candidates[b.tag].selected = b.state == NSControlStateValueOn;
    NSView* row = [_cands rowViewAtRow:b.tag makeIfNecessary:NO]; row.subviews.firstObject.alphaValue = _candidates[b.tag].selected ? 1.0 : 0.45;
}
- (void)controlTextDidEndEditing:(NSNotification*)n {
    NSTextField* f = n.object;
    if ([f isKindOfClass:NSTextField.class] && f.tag >= 0 && f.tag < (NSInteger)_candidates.size() && f.superview && [f.superview isKindOfClass:PlanRow.class])
        _candidates[f.tag].hook = U(f.stringValue);
}
- (NSDragOperation)tableView:(NSTableView*)t validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)r proposedDropOperation:(NSTableViewDropOperation)op {
    return t == _sources ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)tableView:(NSTableView*)t acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)r dropOperation:(NSTableViewDropOperation)op {
    NSArray* urls = [info.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSMutableArray* paths = [NSMutableArray array]; for (NSURL* u in urls) [paths addObject:u.path];
    [self addSourcePaths:paths];
    return paths.count > 0;
}

// ------------------------------------------------------------------ documentation screenshots
// CLIPMAKER_SHOT_DIR=dir CLIPMAKER_SHOT_SRC="a.mp4;b.png" [CLIPMAKER_SHOT_MUSIC=m.wav] → loads, analyses, renders, captures, quits.
- (void)capture:(NSWindow*)w name:(NSString*)name {
    NSView* v = w.contentView;
    [v displayIfNeeded];
    NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
    NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[@(getenv("CLIPMAKER_SHOT_DIR")) stringByAppendingPathComponent:name] atomically:YES];
}
- (void)runScreenshotTour {
    _media.clear(); _transcripts.clear(); _candidates.clear(); [_sources reloadData]; [_cands reloadData];
    NSArray* src = [@(getenv("CLIPMAKER_SHOT_SRC") ?: "") componentsSeparatedByString:@";"];
    _idea.string = @"The one lighting mistake beginners make — punchy, for photographers, end with the comment CTA";
    if (const char* m = getenv("CLIPMAKER_SHOT_MUSIC")) [self setMusic:@(m)];
    [self capture:_win name:@"01-empty.png"];
    [self addSourcePaths:src];
    for (NSInteger i = 0; i < (NSInteger)_media.size(); ++i) if (_media[i].isImage) { [_sources selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; [self previewSource:i]; break; }
    [self performSelector:@selector(shotStep2) withObject:nil afterDelay:0.6];
}
- (void)shotStep2 { [self capture:_win name:@"02-sources-preview.png"]; [self analyze:nil]; }
- (void)shotSheet {
    [self selectTab:_tabBtns[0]]; [self capture:_sheet name:@"03-edit-plan-script.png"];
    [self selectTab:_tabBtns[1]]; [self capture:_sheet name:@"04-transcript-frames.png"];
    [self selectTab:_tabBtns[2]]; [self capture:_sheet name:@"05-publish-text.png"];
    [self selectTab:_tabBtns[0]];
    [self closeAnalysis:nil];
    [self capture:_win name:@"06-candidates.png"];
    [self generate:nil];
}
- (void)shotDone {
    AVAssetImageGenerator* gen = [[AVAssetImageGenerator alloc] initWithAsset:[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:S(_lastOutput)] options:nil]];
    gen.appliesPreferredTrackTransform = YES;
    CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(1.2, 600) actualTime:nullptr error:nil];
    if (img) { _imagePreview.image = [[NSImage alloc] initWithCGImage:img size:NSZeroSize]; CGImageRelease(img); _imagePreview.hidden = NO; _playerView.hidden = YES; }
    _timeline.playhead = 1.2;
    [self capture:_win name:@"07-generated.png"];
    [NSApp terminate:nil];
}
@end
