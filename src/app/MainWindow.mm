#import "app/MainWindow.h"
#import "app/TimelineView.h"
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

@implementation ClipMakerController {
    NSWindow* _win;
    // left
    NSTableView* _sources; NSTextView* _idea; NSTextField* _musicLabel; NSSlider* _gain;
    NSButton* _syncBeats; NSButton* _keepVoice; NSPopUpButton* _provider; NSSecureTextField* _key;
    NSTextField* _model; NSTextField* _baseURL; NSTextField* _minLen; NSTextField* _maxLen; NSPopUpButton* _clips; NSPopUpButton* _slideDur;
    NSPopUpButton* _style; NSPopUpButton* _fontSize; NSPopUpButton* _font; NSPopUpButton* _capPos; NSPopUpButton* _hookPos;
    NSButton* _reframe; NSButton* _kenBurns; NSButton* _hook;
    NSButton* _analyzeBtn; NSButton* _generateBtn; NSButton* _revealBtn; NSButton* _analysisBtn;
    // center
    AVPlayerView* _playerView; NSImageView* _imagePreview; TimelineView* _timeline; NSTextField* _status; NSProgressIndicator* _progress; NSTextField* _beatInfo;
    // right
    NSTableView* _cands;
    // analysis sheet
    NSWindow* _sheet; NSTextView* _scriptView; NSTextView* _transcriptView; NSTextView* _publishView;
    // state
    std::vector<MediaInfo> _media; std::vector<Transcript> _transcripts; std::vector<Candidate> _candidates;
    std::vector<std::string> _visuals; Script _script; std::string _ideaText;
    BeatGrid _beats; std::string _lastOutput; Project _project;
    bool _busy; id _boundaryObserver; id _timeObserver;
}

// ------------------------------------------------------------------ UI builders
static NSTextField* label(NSString* t, NSRect f, CGFloat size, BOOL bold, NSView* parent) {
    NSTextField* l = [NSTextField labelWithString:t];
    l.frame = f; l.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    l.textColor = bold ? [NSColor secondaryLabelColor] : [NSColor labelColor];
    l.autoresizingMask = NSViewMinYMargin;
    [parent addSubview:l]; return l;
}
static NSTextField* section(NSString* t, CGFloat y, NSView* parent) {
    NSTextField* l = label([t uppercaseString], NSMakeRect(14, y, 260, 16), 10, YES, parent);
    l.textColor = [NSColor tertiaryLabelColor];
    return l;
}
static NSButton* button(NSString* t, NSRect f, id target, SEL sel, NSView* parent) {
    NSButton* b = [NSButton buttonWithTitle:t target:target action:sel];
    b.frame = f; b.bezelStyle = NSBezelStyleRounded; b.autoresizingMask = NSViewMinYMargin;
    [parent addSubview:b]; return b;
}
static NSButton* check(NSString* t, NSRect f, BOOL on, NSView* parent) {
    NSButton* b = [NSButton checkboxWithTitle:t target:nil action:nil];
    b.frame = f; b.state = on ? NSControlStateValueOn : NSControlStateValueOff; b.autoresizingMask = NSViewMinYMargin;
    b.font = [NSFont systemFontOfSize:11];
    [parent addSubview:b]; return b;
}
static NSPopUpButton* popup(NSArray* items, NSRect f, NSView* parent) {
    NSPopUpButton* p = [[NSPopUpButton alloc] initWithFrame:f pullsDown:NO];
    [p addItemsWithTitles:items]; p.autoresizingMask = NSViewMinYMargin; p.font = [NSFont systemFontOfSize:11];
    p.controlSize = NSControlSizeSmall;
    [parent addSubview:p]; return p;
}
static NSTextField* field(NSString* placeholder, NSRect f, NSView* parent, BOOL secure) {
    NSTextField* t = secure ? [[NSSecureTextField alloc] initWithFrame:f] : [[NSTextField alloc] initWithFrame:f];
    t.placeholderString = placeholder; t.font = [NSFont systemFontOfSize:11]; t.autoresizingMask = NSViewMinYMargin;
    t.controlSize = NSControlSizeSmall;
    [parent addSubview:t]; return t;
}
static NSTableColumn* column(NSString* id_, NSString* title, CGFloat w) {
    NSTableColumn* c = [[NSTableColumn alloc] initWithIdentifier:id_];
    c.title = title; c.width = w; c.minWidth = 20; return c;
}

- (void)applicationDidFinishLaunching:(NSNotification*)n {
    [self buildMenu];
    const CGFloat W = 1240, H = 840, L = 300, R = 360;
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, W, H)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
            backing:NSBackingStoreBuffered defer:NO];
    _win.title = @"ClipMaker"; _win.delegate = self; _win.restorable = NO;
    _win.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _win.minSize = NSMakeSize(1000, 760);
    _win.titlebarAppearsTransparent = YES;
    _win.backgroundColor = [NSColor colorWithWhite:0.13 alpha:1];
    [_win center];
    NSView* root = _win.contentView;
    root.wantsLayer = YES; root.layer.backgroundColor = [NSColor colorWithWhite:0.13 alpha:1].CGColor;

    // ---------------- left panel
    NSView* left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, L, H)];
    left.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    left.wantsLayer = YES; left.layer.backgroundColor = [NSColor colorWithWhite:0.16 alpha:1].CGColor;
    [root addSubview:left];
    CGFloat y = H - 36;

    section(@"Sources", y, left); y -= 108;
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, y, L - 28, 100)];
    sv.autoresizingMask = NSViewMinYMargin; sv.hasVerticalScroller = YES; sv.borderType = NSBezelBorder;
    _sources = [[NSTableView alloc] initWithFrame:sv.bounds];
    [_sources addTableColumn:column(@"name", @"File", L - 60)];
    _sources.headerView = nil; _sources.dataSource = self; _sources.delegate = self; _sources.rowHeight = 20;
    _sources.font = [NSFont systemFontOfSize:11];
    [_sources registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    sv.documentView = _sources; [left addSubview:sv];
    y -= 26;
    button(@"＋ Add media…", NSMakeRect(10, y, 130, 24), self, @selector(addSources:), left);
    button(@"Remove", NSMakeRect(L - 94, y, 84, 24), self, @selector(removeSource:), left);

    y -= 30; section(@"Idea / brief", y, left); y -= 74;
    NSScrollView* isv = [[NSScrollView alloc] initWithFrame:NSMakeRect(14, y, L - 28, 68)];
    isv.autoresizingMask = NSViewMinYMargin; isv.borderType = NSBezelBorder; isv.hasVerticalScroller = YES;
    _idea = [[NSTextView alloc] initWithFrame:isv.bounds];
    _idea.font = [NSFont systemFontOfSize:12]; _idea.richText = NO; _idea.autoresizingMask = NSViewWidthSizable;
    _idea.textContainerInset = NSMakeSize(4, 4);
    _idea.string = [[NSUserDefaults standardUserDefaults] stringForKey:@"idea"] ?: @"";
    isv.documentView = _idea; [left addSubview:isv];

    y -= 30; section(@"Music & rhythm", y, left); y -= 24;
    _musicLabel = label(@"No music", NSMakeRect(14, y, L - 110, 18), 11, NO, left); _musicLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    button(@"Choose…", NSMakeRect(L - 94, y - 3, 84, 24), self, @selector(chooseMusic:), left);
    y -= 26;
    label(@"Music level", NSMakeRect(14, y, 80, 16), 11, NO, left);
    _gain = [[NSSlider alloc] initWithFrame:NSMakeRect(96, y - 2, L - 112, 20)];
    _gain.minValue = 0; _gain.maxValue = 1; _gain.doubleValue = 0.2; _gain.autoresizingMask = NSViewMinYMargin; _gain.controlSize = NSControlSizeSmall;
    [left addSubview:_gain];
    y -= 24;
    _syncBeats = check(@"Sync cuts to beats", NSMakeRect(14, y, 140, 18), YES, left);
    _keepVoice = check(@"Keep original voice", NSMakeRect(156, y, 140, 18), YES, left);

    y -= 30; section(@"AI engine", y, left); y -= 26;
    _provider = popup(@[@"Offline heuristic (no AI)", @"Anthropic Claude (API)", @"Ollama (local)", @"OpenAI-compatible"], NSMakeRect(12, y, L - 24, 24), left);
    _provider.target = self; _provider.action = @selector(providerChanged:);
    y -= 26;
    _key = (NSSecureTextField*)field(@"API key (or ANTHROPIC_API_KEY env)", NSMakeRect(14, y, L - 28, 22), left, YES);
    y -= 26;
    _model = field(@"Model (blank = default)", NSMakeRect(14, y, 136, 22), left, NO);
    _baseURL = field(@"Base URL (optional)", NSMakeRect(156, y, L - 170, 22), left, NO);

    y -= 32; section(@"Output", y, left); y -= 26;
    label(@"Length", NSMakeRect(14, y + 3, 50, 16), 11, NO, left);
    _minLen = field(@"min", NSMakeRect(60, y, 44, 22), left, NO); _minLen.stringValue = @"20"; _minLen.alignment = NSTextAlignmentCenter;
    label(@"–", NSMakeRect(106, y + 3, 10, 16), 11, NO, left);
    _maxLen = field(@"max", NSMakeRect(118, y, 44, 22), left, NO); _maxLen.stringValue = @"40"; _maxLen.alignment = NSTextAlignmentCenter;
    label(@"s", NSMakeRect(164, y + 3, 12, 16), 11, NO, left);
    label(@"Clips", NSMakeRect(186, y + 3, 36, 16), 11, NO, left);
    _clips = popup(@[@"1", @"2", @"3", @"4", @"5", @"6", @"8"], NSMakeRect(222, y, 62, 24), left); [_clips selectItemAtIndex:3];
    y -= 26;
    label(@"Image slide", NSMakeRect(14, y + 3, 70, 16), 11, NO, left);
    _slideDur = popup(@[@"2 s", @"3 s", @"4 s", @"5 s", @"6 s", @"8 s"], NSMakeRect(86, y, 66, 24), left); [_slideDur selectItemAtIndex:2];
    label(@"pan + zoom", NSMakeRect(156, y + 3, 100, 16), 11, NO, left).textColor = [NSColor tertiaryLabelColor];
    y -= 26;
    label(@"Captions", NSMakeRect(14, y + 3, 56, 16), 11, NO, left);
    _style = popup(@[@"Bold pop", @"Karaoke highlight", @"Minimal pill", @"Outline", @"None"], NSMakeRect(70, y, 120, 24), left);
    _fontSize = popup(@[@"48", @"56", @"64", @"72", @"84"], NSMakeRect(196, y, 60, 24), left); [_fontSize selectItemAtIndex:2];
    y -= 26;
    label(@"Position", NSMakeRect(14, y + 3, 56, 16), 11, NO, left);
    _capPos = popup(@[@"Top", @"Upper", @"Center", @"Lower", @"Bottom"], NSMakeRect(70, y, 90, 24), left); [_capPos selectItemAtIndex:3];
    label(@"Hook", NSMakeRect(166, y + 3, 36, 16), 11, NO, left);
    _hookPos = popup(@[@"Top", @"Upper", @"Center", @"Lower", @"Bottom"], NSMakeRect(200, y, 86, 24), left); [_hookPos selectItemAtIndex:0];
    y -= 26;
    label(@"Font", NSMakeRect(14, y + 3, 40, 16), 11, NO, left);
    _font = popup(@[@"Helvetica-Bold", @"AvenirNext-Heavy", @"Futura-CondensedExtraBold", @"Impact", @"ArialRoundedMTBold", @"Menlo-Bold"], NSMakeRect(60, y, 196, 24), left);
    y -= 26;
    _reframe = check(@"Smart 9:16 reframe", NSMakeRect(14, y, 140, 18), YES, left);
    _kenBurns = check(@"Subtle zoom", NSMakeRect(156, y, 100, 18), YES, left);
    y -= 22;
    _hook = check(@"Show hook title", NSMakeRect(14, y, 140, 18), YES, left);

    _analyzeBtn = button(@"1 · Analyze", NSMakeRect(12, 50, L - 24, 32), self, @selector(analyze:), left);
    _analyzeBtn.autoresizingMask = NSViewMaxYMargin; _analyzeBtn.keyEquivalent = @"a"; _analyzeBtn.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _generateBtn = button(@"2 · Generate short", NSMakeRect(12, 14, L - 24, 32), self, @selector(generate:), left);
    _generateBtn.autoresizingMask = NSViewMaxYMargin; _generateBtn.keyEquivalent = @"\r"; _generateBtn.enabled = NO;

    // ---------------- center
    NSView* center = [[NSView alloc] initWithFrame:NSMakeRect(L, 0, W - L - R, H)];
    center.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:center];
    CGFloat cw = center.frame.size.width;
    _playerView = [[AVPlayerView alloc] initWithFrame:NSMakeRect(12, 130, cw - 24, H - 170)];
    _playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _playerView.controlsStyle = AVPlayerViewControlsStyleInline; _playerView.showsFullScreenToggleButton = YES;
    _playerView.wantsLayer = YES; _playerView.layer.backgroundColor = NSColor.blackColor.CGColor; _playerView.layer.cornerRadius = 8;
    [center addSubview:_playerView];
    _imagePreview = [[NSImageView alloc] initWithFrame:_playerView.frame];
    _imagePreview.autoresizingMask = _playerView.autoresizingMask; _imagePreview.imageScaling = NSImageScaleProportionallyUpOrDown;
    _imagePreview.wantsLayer = YES; _imagePreview.layer.backgroundColor = NSColor.blackColor.CGColor; _imagePreview.layer.cornerRadius = 8;
    _imagePreview.hidden = YES;
    [center addSubview:_imagePreview];
    _timeline = [[TimelineView alloc] initWithFrame:NSMakeRect(12, 62, cw - 24, 60)];
    _timeline.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin; _timeline.playhead = -1;
    [center addSubview:_timeline];
    _beatInfo = label(@"", NSMakeRect(12, 42, cw - 24, 16), 10, NO, center); _beatInfo.textColor = [NSColor tertiaryLabelColor];
    _beatInfo.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _status = label(@"Add videos or images, describe the short you want, then Analyze.", NSMakeRect(12, 20, cw - 290, 18), 11, NO, center);
    _status.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin; _status.lineBreakMode = NSLineBreakByTruncatingTail;
    _progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(12, 6, cw - 290, 10)];
    _progress.style = NSProgressIndicatorStyleBar; _progress.minValue = 0; _progress.maxValue = 1; _progress.indeterminate = NO;
    _progress.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin; _progress.controlSize = NSControlSizeSmall;
    [center addSubview:_progress];
    _revealBtn = button(@"Show in Finder", NSMakeRect(cw - 122, 10, 110, 24), self, @selector(reveal:), center);
    _revealBtn.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; _revealBtn.enabled = NO;
    _analysisBtn = button(@"Script & transcript…", NSMakeRect(cw - 272, 10, 146, 24), self, @selector(showAnalysis:), center);
    _analysisBtn.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin; _analysisBtn.enabled = NO;

    // ---------------- right panel
    NSView* right = [[NSView alloc] initWithFrame:NSMakeRect(W - R, 0, R, H)];
    right.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    right.wantsLayer = YES; right.layer.backgroundColor = [NSColor colorWithWhite:0.16 alpha:1].CGColor;
    [root addSubview:right];
    NSTextField* t = section(@"Edit plan  (tick to include · double-click to preview · edit title inline)", H - 36, right); t.frame = NSMakeRect(14, H - 36, R - 28, 16);
    NSScrollView* csv = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 12, R - 24, H - 56)];
    csv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; csv.hasVerticalScroller = YES; csv.borderType = NSBezelBorder;
    _cands = [[NSTableView alloc] initWithFrame:csv.bounds];
    NSTableColumn* on = column(@"on", @"", 22); NSButtonCell* cb = [[NSButtonCell alloc] init]; [cb setButtonType:NSButtonTypeSwitch]; cb.title = @""; on.dataCell = cb;
    [_cands addTableColumn:on];
    [_cands addTableColumn:column(@"score", @"Score", 42)];
    [_cands addTableColumn:column(@"time", @"Time", 92)];
    NSTableColumn* hook = column(@"hook", @"Hook / title", R - 200); hook.editable = YES;
    [_cands addTableColumn:hook];
    _cands.dataSource = self; _cands.delegate = self; _cands.rowHeight = 22; _cands.font = [NSFont systemFontOfSize:11];
    _cands.doubleAction = @selector(previewCandidate:); _cands.target = self;
    _cands.usesAlternatingRowBackgroundColors = YES;
    csv.documentView = _cands; [right addSubview:csv];

    [self loadDefaults];
    [self providerChanged:nil];
    [_win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (getenv("CLIPMAKER_SHOT_DIR")) [self performSelector:@selector(runScreenshotTour) withObject:nil afterDelay:0.5];
}

// ------------------------------------------------------------------ documentation screenshots
// CLIPMAKER_SHOT_DIR=dir CLIPMAKER_SHOT_SRC="a.mp4;b.png" → loads them, analyses, captures windows, quits.
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
    NSMutableArray* tabBtns = [NSMutableArray array];
    for (NSView* sv in _sheet.contentView.subviews) if ([sv isKindOfClass:NSButton.class] && [(NSButton*)sv action] == @selector(selectTab:)) [tabBtns addObject:sv];
    [tabBtns sortUsingComparator:^NSComparisonResult(NSView* a, NSView* b) { return a.tag < b.tag ? NSOrderedAscending : NSOrderedDescending; }];
    [self selectTab:tabBtns[0]]; [self capture:_sheet name:@"03-edit-plan-script.png"];
    [self selectTab:tabBtns[1]]; [self capture:_sheet name:@"04-transcript-frames.png"];
    [self selectTab:tabBtns[2]]; [self capture:_sheet name:@"05-publish-text.png"];
    [self selectTab:tabBtns[0]];
    [self closeAnalysis:nil];
    [self capture:_win name:@"06-candidates.png"];
    [self generate:nil];
}
- (void)shotDone {
    // the AVPlayerView does not draw into an offscreen cache, so show a poster frame of the result instead
    AVAssetImageGenerator* gen = [[AVAssetImageGenerator alloc] initWithAsset:[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:S(_lastOutput)] options:nil]];
    gen.appliesPreferredTrackTransform = YES;
    CGImageRef img = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(1.2, 600) actualTime:nullptr error:nil];
    if (img) { _imagePreview.image = [[NSImage alloc] initWithCGImage:img size:NSZeroSize]; CGImageRelease(img); _imagePreview.hidden = NO; _playerView.hidden = YES; }
    _timeline.playhead = 1.2;
    [self capture:_win name:@"07-generated.png"];
    [NSApp terminate:nil];
}

- (void)buildMenu {
    NSMenu* bar = [[NSMenu alloc] init];
    NSMenuItem* appItem = [[NSMenuItem alloc] init]; [bar addItem:appItem];
    NSMenu* app = [[NSMenu alloc] init];
    [app addItemWithTitle:@"About ClipMaker" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [app addItem:[NSMenuItem separatorItem]];
    [app addItemWithTitle:@"Quit ClipMaker" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = app;
    NSMenuItem* fileItem = [[NSMenuItem alloc] init]; [bar addItem:fileItem];
    NSMenu* file = [[NSMenu alloc] initWithTitle:@"File"];
    [file addItemWithTitle:@"Add Videos…" action:@selector(addSources:) keyEquivalent:@"o"];
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
    if (NSString* m = [d stringForKey:@"music"]) if ([[NSFileManager defaultManager] fileExistsAtPath:m]) [self setMusic:m];
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
        [self setStatus:[NSString stringWithFormat:@"%zu source(s). Click one to check it, describe your idea, then Analyze.", _media.size()]];
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
        [self setStatus:[NSString stringWithFormat:@"Image %@  %dx%d — will play as a %@ slide with pan/zoom", S(m.path).lastPathComponent, m.width, m.height, _slideDur.titleOfSelectedItem]];
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
- (void)setMusic:(NSString*)path {
    _musicLabel.stringValue = path.lastPathComponent; _musicLabel.toolTip = path;
}
- (void)openOutputFolder:(id)sender { [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:S(outputDirectory())]]; }
- (void)reveal:(id)sender {
    if (!_lastOutput.empty()) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:S(_lastOutput)]]];
}

- (void)setStatus:(NSString*)s { _status.stringValue = s; }
- (void)progress:(double)f message:(const std::string&)m {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_progress.doubleValue = f; self->_status.stringValue = S(m); });
}
- (void)setBusy:(bool)b {
    _busy = b; _analyzeBtn.enabled = !b; _generateBtn.enabled = !b && !_candidates.empty();
    if (b) _progress.doubleValue = 0;
}
- (void)alert:(NSString*)title detail:(const std::string&)d {
    NSAlert* a = [[NSAlert alloc] init]; a.messageText = title; a.informativeText = S(d); a.alertStyle = NSAlertStyleWarning;
    [a beginSheetModalForWindow:_win completionHandler:nil];
}

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
            prog(0.68, "Asking AI for an edit plan, title and hashtags…");
            cands = aiSelectSegments(s, transcripts, media, visuals, idea, script, &aiErr);
            if (cands.empty()) note = "AI unavailable (" + aiErr + ") — used offline ranking. ";
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
            self->_progress.doubleValue = 1;
            [self setStatus:S(note + std::to_string(cands.size()) + " moments proposed. Review the script, then Generate.")];
            [self showAnalysis:nil];
        });
    });
}

// ------------------------------------------------------------------ analysis sheet
static NSTextView* textTab(NSTabView* tabs, NSString* title, BOOL editable) {
    NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:title]; item.label = title;
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    sv.hasVerticalScroller = YES; sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTextView* tv = [[NSTextView alloc] initWithFrame:sv.bounds];
    tv.editable = editable; tv.richText = NO; tv.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    tv.textContainerInset = NSMakeSize(10, 10); tv.autoresizingMask = NSViewWidthSizable;
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
        _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 600)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        _sheet.title = @"Edit plan"; _sheet.restorable = NO;
        _sheet.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        NSView* v = _sheet.contentView;
        v.wantsLayer = YES; v.layer.backgroundColor = [NSColor colorWithWhite:0.16 alpha:1].CGColor;
        NSTabView* tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(12, 52, 796, 500)];
        tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; tabs.tabViewType = NSNoTabsNoBorder;
        NSArray* names = @[@"Editing script", @"Transcript & frames", @"Title · description · hashtags"];
        for (NSUInteger i = 0; i < names.count; ++i) {
            NSButton* b = button(names[i], NSMakeRect(12 + i * 200, 562, 196, 28), self, @selector(selectTab:), v);
            b.tag = i; b.autoresizingMask = NSViewMinYMargin; b.bezelStyle = NSBezelStyleRounded;
            if (i == 0) { b.bezelColor = [NSColor controlAccentColor]; b.contentTintColor = NSColor.whiteColor; }
        }
        _scriptView = textTab(tabs, @"Editing script", YES);
        _transcriptView = textTab(tabs, @"Transcript & frames", NO);
        _publishView = textTab(tabs, @"Title · description · hashtags", YES);
        [v addSubview:tabs];
        NSButton* ok = button(@"Approve & Generate", NSMakeRect(640, 12, 168, 30), self, @selector(approveAndGenerate:), v);
        ok.keyEquivalent = @"\r"; ok.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        NSButton* close = button(@"Close", NSMakeRect(552, 12, 84, 30), self, @selector(closeAnalysis:), v);
        close.keyEquivalent = @"\033"; close.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        NSButton* copy = button(@"Copy publish text", NSMakeRect(12, 12, 150, 30), self, @selector(copyPublish:), v);
        copy.autoresizingMask = NSViewMaxYMargin;
        NSButton* redo = button(@"Re-run analysis", NSMakeRect(168, 12, 130, 30), self, @selector(rerunAnalysis:), v);
        redo.autoresizingMask = NSViewMaxYMargin;
    }
    NSString* intro = _script.narrative.empty() ? @"" : [NSString stringWithFormat:@"AI RATIONALE\n%@\n\n", S(_script.narrative)];
    _scriptView.string = [NSString stringWithFormat:@"%@PLAN (what will be cut, in order — tick/untick and rename moments in the main window)\n%@\n\nFinal length target: %@–%@ s.  Edit the publish tab freely; approve to render.",
                          intro, S(describeScript(_candidates, _media)), _minLen.stringValue, _maxLen.stringValue];
    _transcriptView.string = [self transcriptText];
    _publishView.string = S(_script.publishText());
    for (NSView* sv in _sheet.contentView.subviews) if ([sv isKindOfClass:NSButton.class] && sv.tag == 0 && [(NSButton*)sv action] == @selector(selectTab:)) [self selectTab:(NSButton*)sv];
    [_win beginSheet:_sheet completionHandler:nil];
    if (getenv("CLIPMAKER_SHOT_DIR")) [self performSelector:@selector(shotSheet) withObject:nil afterDelay:0.8];
}
- (void)selectTab:(NSButton*)sender {
    NSTabView* tabs = nil;
    for (NSView* sv in _sheet.contentView.subviews) if ([sv isKindOfClass:NSTabView.class]) tabs = (NSTabView*)sv;
    [tabs selectTabViewItemAtIndex:sender.tag];
    for (NSView* sv in _sheet.contentView.subviews)
        if ([sv isKindOfClass:NSButton.class] && [(NSButton*)sv action] == @selector(selectTab:)) {
            BOOL on = sv.tag == sender.tag;
            ((NSButton*)sv).bezelColor = on ? [NSColor controlAccentColor] : nil;
            ((NSButton*)sv).contentTintColor = on ? NSColor.whiteColor : nil;
        }
}
- (void)syncPublishFromView {
    // parse the editable publish text back (TITLE / DESCRIPTION / HASHTAGS blocks)
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

- (void)generate:(id)sender {
    if (_busy || _candidates.empty()) return;
    [self saveDefaults];
    Settings s = [self settings];
    Project p = buildProject(_candidates, _transcripts, _media, s, _beats);
    if (p.clips.empty()) { [self alert:@"Nothing selected" detail:"Tick at least one candidate."]; return; }
    _project = p;
    std::vector<double> d; std::vector<int> src;
    for (auto& k : p.clips) { d.push_back(k.duration()); int si = 0; for (size_t i = 0; i < _media.size(); ++i) if (_media[i].path == k.sourcePath) si = (int)i; src.push_back(si); }
    std::vector<double> rel; for (double b : p.musicBeats.beats) rel.push_back(b - p.musicOffset);
    [_timeline setClipDurations:d sources:src beats:rel total:p.duration()];
    NSDateFormatter* f = [[NSDateFormatter alloc] init]; f.dateFormat = @"yyyyMMdd-HHmmss";
    std::string out = outputDirectory() + "/short-" + U([f stringFromDate:[NSDate date]]) + ".mp4";
    [self setBusy:true];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        std::string err;
        bool ok = renderProject(p, out, [self](double f, const std::string& m) { [self progress:f message:m]; }, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:false];
            if (!ok) { [self alert:@"Render failed" detail:err]; return; }
            self->_lastOutput = out; self->_revealBtn.enabled = YES;
            saveSidecar(out, self->_script, describeScript(self->_candidates, self->_media));
            [self setStatus:[NSString stringWithFormat:@"Saved %@  (%.1f s) + publish text (.txt next to it)", S(out).lastPathComponent, p.duration()]];
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

// ------------------------------------------------------------------ tables
- (NSInteger)numberOfRowsInTableView:(NSTableView*)t { return t == _sources ? _media.size() : _candidates.size(); }
- (id)tableView:(NSTableView*)t objectValueForTableColumn:(NSTableColumn*)c row:(NSInteger)r {
    if (t == _sources) {
        auto& m = _media[r];
        return [NSString stringWithFormat:@"%@  (%@, %dx%d)", S(m.path).lastPathComponent, S(fmtTime(m.duration)), m.width, m.height];
    }
    auto& k = _candidates[r];
    NSString* id_ = c.identifier;
    if ([id_ isEqualToString:@"on"]) return @(k.selected);
    if ([id_ isEqualToString:@"score"]) return [NSString stringWithFormat:@"%.0f", k.score];
    if ([id_ isEqualToString:@"time"]) {
        if (k.isImage) return [NSString stringWithFormat:@"S%d IMG %.0fs", k.sourceIndex + 1, k.duration()];
        return [NSString stringWithFormat:@"%@%@–%@", _media.size() > 1 ? [NSString stringWithFormat:@"S%d ", k.sourceIndex + 1] : @"", S(fmtTime(k.start)), S(fmtTime(k.end))];
    }
    return S(k.hook);
}
- (void)tableView:(NSTableView*)t setObjectValue:(id)v forTableColumn:(NSTableColumn*)c row:(NSInteger)r {
    if (t != _cands || r >= (NSInteger)_candidates.size()) return;
    if ([c.identifier isEqualToString:@"on"]) _candidates[r].selected = [v boolValue];
    else if ([c.identifier isEqualToString:@"hook"]) _candidates[r].hook = U([v description]);
}
- (NSString*)tableView:(NSTableView*)t toolTipForCell:(NSCell*)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn*)c row:(NSInteger)r mouseLocation:(NSPoint)p {
    if (t == _cands && r < (NSInteger)_candidates.size()) return [NSString stringWithFormat:@"%@\nShows: %@\n\n“%@”", S(_candidates[r].reason), S(_candidates[r].visual), S(_candidates[r].text)];
    return nil;
}
- (BOOL)tableView:(NSTableView*)t shouldEditTableColumn:(NSTableColumn*)c row:(NSInteger)r {
    return t == _cands && ([c.identifier isEqualToString:@"hook"] || [c.identifier isEqualToString:@"on"]);
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
@end
