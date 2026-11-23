#import "Patches/LittleDia/Route.m"
#import "Patches/LittleDia/Stack.m"
#import "Patches/LittleDia/Extension.m"

DPPatch DPLittleDia, DPLittleDiaFollowRules, DPLittleDiaRemember;

static NSRect gSavedFrame;
static NSMutableArray<NSDictionary *> *gExpected;
static NSMutableArray<NSAppleEventDescriptor *> *gOriginalEvents;
static NSMutableArray<NSArray<NSURL *> *> *gOriginalOpenURLs;
static id gCommandBrowser;
static NSMapTable<NSWindow *, id> *gBrowserByWindow;
static NSHashTable<NSWindow *> *gLittleWindows;

NSSize DPLittleDiaSize(void) { return NSMakeSize(1000, 700); }
NSRect DPLittleDiaSavedFrame(void) { return gSavedFrame; }
BOOL DPTabsAtTop(NSWindow *window) { return NO; }
void DPPutLittleDiaOver(NSWindow *little, NSWindow *window) {}
void DPEditLittleDiaAddress(NSWindow *window) {}
BOOL DPIsLittleDiaWindow(NSWindow *window) { return [gLittleWindows containsObject:window]; }
void DPLoadExtension(NSString *folder) {}
void DPDropExtension(NSString *folder) {}
NSString *DPAppSupport(NSString *path) { return [@"/nonexistent" stringByAppendingPathComponent:path]; }
id DPCommandBrowser(void) { return gCommandBrowser; }
id DPBrowserOfWindow(NSWindow *window) { return [gBrowserByWindow objectForKey:window]; }

void DPExpectLittleDiaWindow(NSRect frame, NSDictionary *noted, void (^missed)(void), void (^claimed)(NSWindow *window)) {
    [gExpected addObject:@{@"frame" : [NSValue valueWithRect:frame], @"missed" : [missed copy]}];
}

@interface FakeExtInfo : NSObject
@property BOOL enabled;
@end
@implementation FakeExtInfo
@end

@interface FakeExtensions : NSObject
@property BOOL extensionSystemReady;
@property (nonatomic, strong) FakeExtInfo *info;
@end
@implementation FakeExtensions
- (BOOL)isExtensionSystemReady { return self.extensionSystemReady; }
- (id)getExtensionInfo:(NSString *)extID { return self.info; }
@end

@interface FakeContext : NSObject
@property (nonatomic, strong) FakeExtensions *extensions;
@end
@implementation FakeContext
@end

@interface FakeBrowser : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, strong) FakeContext *context;
@property (nonatomic, strong) NSMutableArray<NSString *> *sentPayloads;
@end
@implementation FakeBrowser
- (instancetype)initWithLabel:(NSString *)label ready:(BOOL)ready enabled:(BOOL)enabled {
    if (!(self = [super init])) return nil;
    _label = [label copy];
    _sentPayloads = [NSMutableArray array];
    FakeExtInfo *info = [FakeExtInfo new];
    info.enabled = enabled;
    FakeExtensions *exts = [FakeExtensions new];
    exts.extensionSystemReady = ready;
    exts.info = info;
    FakeContext *ctx = [FakeContext new];
    ctx.extensions = exts;
    _context = ctx;
    return self;
}
- (void)triggerExtensionOmniboxInput:(NSString *)extID inputText:(NSString *)text disposition:(long)disposition {
    [self.sentPayloads addObject:text];
}
@end

@interface _TtC13OpenURLClient19OpenURLEventManager : NSObject
- (void)handleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
@end
@implementation _TtC13OpenURLClient19OpenURLEventManager
- (void)handleEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    [gOriginalEvents addObject:event];
}
@end

@interface _TtC15BoostBrowserMac11AppDelegate : NSObject
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls;
@end
@implementation _TtC15BoostBrowserMac11AppDelegate
- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    [gOriginalOpenURLs addObject:urls];
}
@end

static int failures;

static void expect(BOOL ok, NSString *what) {
    if (ok) return;
    failures++;
    printf("FAIL: %s\n", what.UTF8String);
}

@interface FakeEvent : NSObject <NSCopying>
@property (nonatomic, strong) NSAppleEventDescriptor *inner;
@property (nonatomic, strong) NSNumber *senderPID;
@end
@implementation FakeEvent
- (AEEventClass)eventClass { return self.inner.eventClass; }
- (AEEventID)eventID { return self.inner.eventID; }
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword { return [self.inner paramDescriptorForKeyword:keyword]; }
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword {
    if (keyword == keySenderPIDAttr && self.senderPID) return [NSAppleEventDescriptor descriptorWithInt32:self.senderPID.intValue];
    return [self.inner attributeDescriptorForKeyword:keyword];
}
- (id)copyWithZone:(NSZone *)zone {
    FakeEvent *copy = [FakeEvent new];
    copy.inner = [self.inner copy];
    copy.senderPID = self.senderPID;
    return copy;
}
@end

static NSAppleEventDescriptor *makeEvent(AEEventClass cls, AEEventID eid, NSAppleEventDescriptor *direct, pid_t senderPID, BOOL setSenderPID, NSAppleEventDescriptor *address) {
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:cls eventID:eid
                                                                    targetDescriptor:address ?: NSAppleEventDescriptor.nullDescriptor
                                                                            returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    if (direct) [event setParamDescriptor:direct forKeyword:keyDirectObject];
    FakeEvent *wrapped = [FakeEvent new];
    wrapped.inner = event;
    if (setSenderPID) wrapped.senderPID = @(senderPID);
    return (NSAppleEventDescriptor *)wrapped;
}

static NSAppleEventDescriptor *makeGetURL(NSString *url, pid_t senderPID, BOOL setSenderPID) {
    return makeEvent(kInternetEventClass, kAEGetURL, url ? [NSAppleEventDescriptor descriptorWithString:url] : nil, senderPID, setSenderPID, nil);
}

static NSDictionary *parseJSON(NSString *text) {
    return [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

static NSWindow *invisibleWindow(void) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 100, 100)
                                              styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    w.alphaValue = 0;
    w.ignoresMouseEvents = YES;
    return w;
}

static void reset(FakeBrowser *browser) {
    [gExpected removeAllObjects];
    [gOriginalEvents removeAllObjects];
    [gOriginalOpenURLs removeAllObjects];
    [browser.sentPayloads removeAllObjects];
    [gBrowserByWindow removeAllObjects];
    [DPPutAway removeAllObjects];
    [DPVeiled removeAllObjects];
    gCommandBrowser = browser;
    gSavedFrame = NSZeroRect;
    DPLittleDia.on = YES;
    DPLittleDiaFollowRules.on = NO;
    DPLittleDiaRemember.on = NO;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gExpected = [NSMutableArray array];
        gOriginalEvents = [NSMutableArray array];
        gOriginalOpenURLs = [NSMutableArray array];
        gBrowserByWindow = [NSMapTable weakToStrongObjectsMapTable];
        gLittleWindows = [NSHashTable weakObjectsHashTable];
        DPPutAway = [NSMutableArray array];
        DPVeiled = [NSMapTable weakToStrongObjectsMapTable];
        gExtensionID = @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        gLaunchedAt = NSProcessInfo.processInfo.systemUptime - 60;

        DPInstallLittleDiaRoute();
        _TtC13OpenURLClient19OpenURLEventManager *manager = [_TtC13OpenURLClient19OpenURLEventManager new];
        _TtC15BoostBrowserMac11AppDelegate *delegate = [_TtC15BoostBrowserMac11AppDelegate new];
        FakeBrowser *browser = [[FakeBrowser alloc] initWithLabel:@"main" ready:YES enabled:YES];
        NSAppleEventDescriptor *nullReply = [NSAppleEventDescriptor nullDescriptor];

        reset(browser);
        [manager handleEvent:makeGetURL(@"https://docs.ankiweb.net/intro.html", getpid() + 1, YES) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 1 && gOriginalEvents.count == 0, @"external https GURL routes to Little Dia");
        expect([parseJSON(browser.sentPayloads[0])[@"url"] isEqual:@"https://docs.ankiweb.net/intro.html"], @"URL preserved");

        reset(browser);
        [manager handleEvent:makeGetURL(@"  HTTPS://jisho.org/search/食べる [1] \n", getpid() + 1, YES) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 1 && gOriginalEvents.count == 0, @"trimmed Unicode/spaced URL routes to Little Dia");
        NSString *encoded = parseJSON(browser.sentPayloads[0])[@"url"];
        expect([encoded hasPrefix:@"HTTPS://jisho.org/search/"] && [encoded containsString:@"%20"], @"invalid characters percent-encoded");

        reset(browser);
        NSAppleEventDescriptor *list1 = [NSAppleEventDescriptor listDescriptor];
        [list1 insertDescriptor:[NSAppleEventDescriptor descriptorWithString:@"https://example.com/one"] atIndex:1];
        [manager handleEvent:makeEvent(kInternetEventClass, kAEGetURL, list1, getpid() + 1, YES, nil) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 1 && gOriginalEvents.count == 0, @"1-item typeAEList routes to Little Dia");

        reset(browser);
        NSAppleEventDescriptor *list2 = [NSAppleEventDescriptor listDescriptor];
        [list2 insertDescriptor:[NSAppleEventDescriptor descriptorWithString:@"https://example.com/a"] atIndex:1];
        [list2 insertDescriptor:[NSAppleEventDescriptor descriptorWithString:@"https://example.com/b"] atIndex:2];
        [manager handleEvent:makeEvent(kInternetEventClass, kAEGetURL, list2, getpid() + 1, YES, nil) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 2 && gOriginalEvents.count == 0, @"2-item typeAEList routes both URLs to Little Dia");

        reset(browser);
        [manager handleEvent:makeGetURL(@"file:///tmp/notes.html", getpid() + 1, YES) withReplyEvent:nullReply];
        [manager handleEvent:makeGetURL(@"mailto:test@example.com", getpid() + 1, YES) withReplyEvent:nullReply];
        [manager handleEvent:makeEvent(kCoreEventClass, kAEOpenDocuments, [NSAppleEventDescriptor descriptorWithString:@"https://example.com"], getpid() + 1, YES, nil) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 0 && gOriginalEvents.count == 3, @"non-web schemes and non-GURL pass straight through");

        reset(browser);
        [manager handleEvent:makeGetURL(@"https://example.com/self-spid", getpid(), YES) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 0 && gOriginalEvents.count == 1, @"self-sent GURL via keySenderPIDAttr stays a tab");

        reset(browser);
        pid_t me = getpid();
        NSAppleEventDescriptor *targetSelf = [NSAppleEventDescriptor descriptorWithDescriptorType:typeKernelProcessID bytes:&me length:sizeof(me)];
        [manager handleEvent:makeEvent(kInternetEventClass, kAEGetURL, [NSAppleEventDescriptor descriptorWithString:@"https://example.com/target-self"], 0, NO, targetSelf) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 1 && gOriginalEvents.count == 0, @"incoming GURL targeted at self without spid still routes to Little Dia");

        reset(browser);
        NSAppleEventDescriptor *bundleAddr = [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID data:[@"net.ankiweb.dtop" dataUsingEncoding:NSUTF8StringEncoding]];
        [manager handleEvent:makeEvent(kInternetEventClass, kAEGetURL, [NSAppleEventDescriptor descriptorWithString:@"https://example.com/bundle-addr"], 0, NO, bundleAddr) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 1 && gOriginalEvents.count == 0, @"external GURL with bundle-ID addr and no spid routes to Little Dia");

        reset(browser);
        DPLittleDia.on = NO;
        [manager handleEvent:makeGetURL(@"https://example.com/off", getpid() + 1, YES) withReplyEvent:nullReply];
        [delegate application:NSApp openURLs:@[ [NSURL URLWithString:@"https://example.com/off-delegate"] ]];
        expect(browser.sentPayloads.count == 0 && gOriginalEvents.count == 1 && gOriginalOpenURLs.count == 1, @"off-tweak passes both GURL and openURLs untouched");

        reset(browser);
        DPLittleDiaFollowRules.on = YES;
        [manager handleEvent:makeGetURL(@"https://example.com/rules", getpid() + 1, YES) withReplyEvent:nullReply];
        [delegate application:NSApp openURLs:@[ [NSURL URLWithString:@"https://example.com/rules-delegate"] ]];
        expect(browser.sentPayloads.count == 0 && gOriginalEvents.count == 1 && gOriginalOpenURLs.count == 1, @"Follow Rules passes both GURL and openURLs untouched");

        reset(browser);
        [delegate application:NSApp openURLs:@[ [NSURL URLWithString:@"https://example.com/direct"] ]];
        expect(browser.sentPayloads.count == 1 && gOriginalOpenURLs.count == 0, @"application:openURLs: routes external https URL to Little Dia");

        reset(browser);
        NSURL *localFile = [NSURL URLWithString:@"file:///tmp/card.pdf"];
        NSURL *webLink = [NSURL URLWithString:@"https://example.com/card"];
        [delegate application:NSApp openURLs:@[ localFile, webLink ]];
        expect(browser.sentPayloads.count == 1 && gOriginalOpenURLs.count == 1 && [gOriginalOpenURLs[0] isEqual:@[ localFile ]],
               @"application:openURLs: splits web URL to Little Dia and forwards file URL to original");

        reset(browser);
        browser.context.extensions.info.enabled = NO;
        [delegate application:NSApp openURLs:@[ webLink ]];
        expect(browser.sentPayloads.count == 0 && gOriginalOpenURLs.count == 1 && [gOriginalOpenURLs[0] isEqual:@[ webLink ]],
               @"application:openURLs: falls back to original when Little Dia is unavailable");
        browser.context.extensions.info.enabled = YES;

        reset(browser);
        DPLittleDiaRemember.on = YES;
        NSRect screenFrame = NSScreen.screens.firstObject ? NSScreen.screens.firstObject.frame : NSMakeRect(0, 0, 1440, 900);
        gSavedFrame = NSMakeRect(NSMinX(screenFrame) + 100.5, NSMinY(screenFrame) + 50.5, 800.5, 600.5);
        [manager handleEvent:makeGetURL(@"https://example.com/fractional", getpid() + 1, YES) withReplyEvent:nullReply];
        expect(browser.sentPayloads.count == 1, @"fractional saved frame sends request");
        if (browser.sentPayloads.count == 1) {
            NSString *raw = browser.sentPayloads[0];
            expect(![raw containsString:@".5"], @"serialized JSON coordinates have no fractional decimals");
            NSDictionary *req = parseJSON(raw);
            expect([req[@"width"] integerValue] == 801 && [req[@"height"] integerValue] == 601, @"fractional dimensions rounded to integers");
        }

        reset(browser);
        NSWindow *backWin = invisibleWindow(), *frontWin = invisibleWindow();
        FakeBrowser *frontBrowser = [[FakeBrowser alloc] initWithLabel:@"front" ready:YES enabled:YES];
        FakeBrowser *backBrowser = [[FakeBrowser alloc] initWithLabel:@"back" ready:YES enabled:YES];
        [gBrowserByWindow setObject:frontBrowser forKey:frontWin];
        [gBrowserByWindow setObject:backBrowser forKey:backWin];
        [backWin orderFront:nil];
        [frontWin orderFront:nil];
        [DPVeiled setObject:@1.0 forKey:backWin];
        [DPVeiled setObject:@1.0 forKey:frontWin];
        // Simulate DPCommandBrowser() returning nil once windows are ordered out with >= 2 browsers.
        gCommandBrowser = nil;
        [manager handleEvent:makeGetURL(@"https://example.com/hidden-multi", getpid() + 1, YES) withReplyEvent:nullReply];
        expect(frontBrowser.sentPayloads.count == 1 && backBrowser.sentPayloads.count == 0 && gOriginalEvents.count == 0,
               @"hidden multi-profile Dia routes via front put-away window browser");
        expect(!frontWin.visible && !backWin.visible && DPPutAwayWindows().count == 2, @"hidden windows stay put away");
        [frontWin orderOut:nil];
        [backWin orderOut:nil];

        reset(browser);
        FakeBrowser *privateBrowser = [[FakeBrowser alloc] initWithLabel:@"private" ready:YES enabled:NO];
        NSWindow *normalWin = invisibleWindow();
        FakeBrowser *normalBrowser = [[FakeBrowser alloc] initWithLabel:@"normal" ready:YES enabled:YES];
        [gBrowserByWindow setObject:normalBrowser forKey:normalWin];
        [normalWin orderFront:nil];
        gCommandBrowser = privateBrowser;
        [manager handleEvent:makeGetURL(@"https://example.com/over-private", getpid() + 1, YES) withReplyEvent:nullReply];
        expect(normalBrowser.sentPayloads.count == 1 && privateBrowser.sentPayloads.count == 0 && gOriginalEvents.count == 0,
               @"front browser without extension falls back to ready normal browser");
        [normalWin orderOut:nil];

        reset(browser);
        FakeBrowser *disabledBrowser = [[FakeBrowser alloc] initWithLabel:@"disabled" ready:YES enabled:NO];
        NSWindow *veiledWin = invisibleWindow();
        [gBrowserByWindow setObject:disabledBrowser forKey:veiledWin];
        [veiledWin orderFront:nil];
        [DPVeiled setObject:@1.0 forKey:veiledWin];
        gCommandBrowser = nil;
        [manager handleEvent:makeGetURL(@"https://example.com/disabled-ext", getpid() + 1, YES) withReplyEvent:nullReply];
        expect(disabledBrowser.sentPayloads.count == 0 && gOriginalEvents.count == 1 && DPPutAwayWindows().count == 0,
               @"disabled extension everywhere falls back cleanly without sending omnibox input");
        [veiledWin orderOut:nil];
    }
    if (failures) return 1;
    puts("PASS: Little Dia routes GURL, AE lists, Unicode URLs, openURLs, and hidden multi-profile windows");
    return 0;
}
