#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <libkern/OSCacheControl.h>
#import <mach/mach_vm.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "StdPatch/StdPatch.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/LittleDia/LittleDia.h"
#import "Patches/Peek/Peek.h"
#import "Patches/HideToolbar/HideToolbar.h"
#import "Patches/SkipAccount/Startup.h"
#import "Settings/Settings.h"
#import "watchdog.h"
#import "runloop.h"

extern NSString *DPIDKey(id value);
extern NSArray<NSString *> *DPSelectionIDKeys(id selection);
extern void DPEachValue(id collection, void (^visit)(id));
extern id DPMakePureSwiftSelection(NSString *primary, NSArray<NSString *> *all);
extern id DPMakePureSwiftIDBox(NSString *raw);

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
DPPatch DPLittleDia, DPLittleDiaTabLinks;
DPPatch DPHideToolbar, DPRevealToolbarOnHover, DPShowLoadingProgress;
DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
BOOL DPPeekGiving;
BOOL DPSamplesProgressColors;
BOOL DPPeekFindingLink;

DPPatch *DPRequired(DPPatch *patch) { return nil; }
BOOL DPIsLocalPatch(DPPatch *patch) { return NO; }
void DPOnLaunch(void (^block)(void)) {}
BOOL DPShortcutMatches(NSEvent *event, DPPatch *patch) { return NO; }
BOOL DPEventIsKey(NSEvent *event, NSString *key) { return [event.charactersIgnoringModifiers.lowercaseString isEqualToString:key.lowercaseString]; }
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void)) { return [[NSMenuItem alloc] initWithTitle:title ?: @"" action:nil keyEquivalent:@""]; }
NSString *DPDomainKey(NSString *url) { return nil; }
NSString *DPRegistrableDomain(NSString *host) { return host; }
BOOL DPPeekShows(id page) { return NO; }
BOOL DPPeekCanOpen(id source) { return NO; }
void DPPeekLoad(id page, NSURL *url) {}
NSURL *DPPeekSearchURL(id page, NSString *text) { return nil; }
void DPPeekOpen(NSWindow *window, NSString *originTabID, NSURL *url, NSPoint origin, id delegate, id source) {}
void DPPeekWarm(NSWindow *window, id source, NSURL *url) {}
void DPPeekCool(void) {}
void DPPeekCloseAll(void) {}
NSArray<DPPeekCard *> *DPPeekAllCards(NSWindow *window) { return @[]; }
BOOL DPPeekHasCards(void) { return NO; }
void DPPeekInstallPages(void) {}
void DPPeekInstallSelection(void) {}
void DPPeekInstallZoom(void) {}
void DPPeekInstallCursor(void) {}
void DPPeekInstallChat(void) {}
NSString *DPPeekZoomProblem(void) { return nil; }
NSArray<NSView *> *DPPeekSettingsRows(void) { return @[]; }
BOOL DPKeptInPlace(NSView *pane) { return NO; }
void DPRemoveProgressLine(NSView *view) {}
void DPShowProgressLine(NSView *view, CGFloat fraction) {}
void DPFinishProgressLine(NSView *view) {}
void DPShowCopyToast(NSView *host, NSString *message) {}
NSURL *DPAddressURL(NSString *typed) { return [NSURL URLWithString:typed]; }
NSButton *DPMakeBarButton(NSString *symbol, NSString *label, NSString *key, void (^action)(void)) { return [NSButton new]; }
NSView *DPMakeDivider(void) { return [NSView new]; }
void DPMatchPage(NSView *row, id page) {}
NSView *DPPeekGlowFor(id page) { return [NSView new]; }

static NSPasteboard *gCopyBoard;
NSPasteboard *DPPeekPasteboard(void) { return gCopyBoard ?: [NSPasteboard pasteboardWithUniqueName]; }
NSTimeInterval DPPeekLookAheadDelay(void) { return 0.01; }

@implementation DPFillView
@end

@implementation DPPeekCard
- (NSRect)cardFrame { return NSZeroRect; }
- (void)close:(DPPeekExit)exit {}
- (void)handOverTo:(NSView *)destination attach:(void (^)(void))attach {}
@end

#import "Patches/ExtensionsShortcut/ExtensionsShortcut.m"
#import "Patches/HideHistorySuggestions/HideHistorySuggestions.m"

@interface DPKVCObject : NSObject
@property (nonatomic, copy) NSString *name;
@end
@implementation DPKVCObject
@end

@interface DPFakeAutocompleteResult : NSObject
@property (nonatomic, strong) NSArray *combinedMatches;
@property (nonatomic, strong) NSDictionary *perProviderMatches;
- (instancetype)init:(NSArray *)combined perProviderMatches:(NSDictionary *)perProvider;
@end
@implementation DPFakeAutocompleteResult
- (instancetype)init:(NSArray *)combined perProviderMatches:(NSDictionary *)perProvider {
    if ((self = [super init])) {
        _combinedMatches = combined;
        _perProviderMatches = perProvider;
    }
    return self;
}
@end

@interface DPFakeBrokenAutocompleteResult : NSObject
- (instancetype)init:(NSArray *)combined perProviderMatches:(NSDictionary *)perProvider;
@end
@implementation DPFakeBrokenAutocompleteResult
- (instancetype)init:(NSArray *)combined perProviderMatches:(NSDictionary *)perProvider { return [super init]; }
@end

@interface DPFakeScriptDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) id appleScriptWindows;
@end
@implementation DPFakeScriptDelegate
@end

@interface DPFakeVisibleWindow : NSWindow
@end
@implementation DPFakeVisibleWindow
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
@end

@interface DPKVOObservedPage : NSObject
@property (nonatomic, copy) NSString *selectedText, *title;
@property (nonatomic) BOOL isLoading;
@property (nonatomic, strong) NSURL *url;
@end
@implementation DPKVOObservedPage
@end

@interface DPStayingAction : NSProxy
@property (nonatomic, strong) id action;
- (NSInteger)navigationDisposition;
@end

@interface DPPeekChatBridge : NSObject
- (instancetype)initWithPeek:(DPPeekCard *)peek;
- (void)detach;
- (void)handleKey:(NSString *)keyPath;
@end

@interface DPPreviewLinkProxy : NSObject
@property (nonatomic, weak) DPPreviewView *target;
- (void)step:(CADisplayLink *)link;
@end

@interface DPPreviewView (DPTestExpose)
- (void)updatePlayback;
@end

static int failures;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s\n", msg); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DPArmTestWatchdog(120);

        DPStage("1. DPValueForKey / DPSetValueForKey KVC safety");
        NSObject *plain = [NSObject new];
        CHECK(DPValueForKey(plain, @"nonexistentKey") == nil, "DPValueForKey returns nil on missing key without NSUndefinedKeyException");
        CHECK(!DPSetValueForKey(plain, @"nonexistentKey", @1), "DPSetValueForKey returns NO on missing key without throwing");
        CHECK(DPValueForKey(nil, @"key") == nil && DPValueForKey(plain, nil) == nil, "DPValueForKey handles nil object/key");
        CHECK(!DPSetValueForKey(nil, @"key", @1) && !DPSetValueForKey(plain, nil, @1), "DPSetValueForKey handles nil object/key");

        DPKVCObject *kvc = [DPKVCObject new];
        CHECK(DPSetValueForKey(kvc, @"name", @"Dia") && [DPValueForKey(kvc, @"name") isEqualToString:@"Dia"],
              "DPValueForKey/DPSetValueForKey read and write valid keys");
        CHECK(DPValueForKey(@[ kvc, plain ], @"name") == nil, "DPValueForKey catches partial-key NSArray KVC failure safely");

        DPStage("2. ExtensionsShortcut: missing context/extensions/KVC keys degrade cleanly");
        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 400, 300)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        NSMenu *emptyExt = DPExtensionsMenu([NSObject new], win);
        CHECK(emptyExt.numberOfItems == 1 && [emptyExt.itemArray.firstObject.title isEqualToString:@"No Extensions"],
              "DPExtensionsMenu degrades cleanly to No Extensions when browser lacks context/extensions");
        CHECK(DPIconFor([NSObject new], win) != nil, "DPIconFor degrades to fallback symbol when extension info lacks name/icon");

        DPStage("3. HideHistorySuggestions: missing/malformed KVC keys never crash or wipe results");
        DPFakeBrokenAutocompleteResult *brokenRes = [DPFakeBrokenAutocompleteResult new];
        CHECK(DPWithoutHistory(brokenRes) == brokenRes, "DPWithoutHistory returns original result when KVC keys are missing");

        NSDictionary *histMatch = @{ @"hasTabMatch" : @NO, @"providerType" : @"HistoryURL", @"matchType" : @"history-url" };
        NSDictionary *searchMatch = @{ @"hasTabMatch" : @NO, @"providerType" : @"Search", @"matchType" : @"search-what-you-typed" };
        NSObject *opaqueMatch = [NSObject new];
        DPFakeAutocompleteResult *goodRes = [[DPFakeAutocompleteResult alloc] init:@[ histMatch, searchMatch, opaqueMatch ]
                                                                perProviderMatches:@{ @"HistoryURL" : @[ histMatch ], @"Search" : @[ searchMatch, opaqueMatch ], @"Bad" : @"not-an-array" }];
        DPFakeAutocompleteResult *filtered = DPWithoutHistory(goodRes);
        CHECK(filtered.combinedMatches.count == 2 && filtered.perProviderMatches[@"HistoryURL"] == nil && [filtered.perProviderMatches[@"Search"] count] == 2,
              "DPWithoutHistory filters history matches while surviving missing-key matches and non-array provider values");

        DPStage("4. CommandBar/Tabs + LittleDia/Profile: non-array & missing-key delegate safety");
        DPFakeScriptDelegate *delegate = [DPFakeScriptDelegate new];
        delegate.appleScriptWindows = @"not-an-array";
        NSApp.delegate = delegate;
        win.identifier = @"w1";
        CHECK(DPScriptWindow(win) == nil, "DPScriptWindow ignores non-array appleScriptWindows");
        CHECK(DPLittleDiaProfiles().count == 0, "DPLittleDiaProfiles returns empty array for non-array windows");

        delegate.appleScriptWindows = @[ [NSObject new], @{ @"windowId" : @"w1", @"appleScriptTabs" : @[ [NSObject new] ], @"appleScriptProfiles" : @[ [NSObject new] ] } ];
        id sw = DPScriptWindow(win);
        CHECK(sw != nil, "DPScriptWindow finds matching dict even when earlier window lacks windowId");
        CHECK(DPScriptTabIn(sw, @"t1") == nil && DPScriptTabInAnyProfile(sw, @"t1") == nil,
              "DPScriptTabIn/InAnyProfile survive objects lacking tabId/appleScriptTabs");
        CHECK(DPTabID([NSObject new]) == nil && DPActiveTabIDIn([NSObject new]) == nil,
              "DPTabID and DPActiveTabIDIn survive missing KVC keys");
        DPFocusTab([NSObject new]);
        DPCloseTab([NSObject new]);
        CHECK(DPLittleDiaProfiles().count == 0, "DPLittleDiaProfiles skips profiles missing name");
        delegate.appleScriptWindows = @[ @{ @"appleScriptProfiles" : @[ @{ @"name" : @"Work" } ] } ];
        __block BOOL openedResult = YES;
        DPOpenInProfile(@"https://example.com", 0, ^(BOOL opened) { openedResult = opened; });
        CHECK(!openedResult, "DPOpenInProfile returns NO synchronously when window lacks windowId");
        NSApp.delegate = nil;

        DPStage("5. Peek Address / CopyURL / Toolbar / ToolbarRules KVC + dealloc lifecycle");
        NSObject *opaquePage = [NSObject new];
        NSView *addr = DPPeekAddressFor(opaquePage);
        DPPeekRefreshAddress(addr);
        DPPeekNavigate(opaquePage, DPPeekBack);
        DPPeekNavigate(opaquePage, DPPeekForward);
        DPPeekNavigate(opaquePage, DPPeekReload);
        CHECK(addr != nil, "Peek Address & Navigate survive page lacking KVC keys/selectors");

        NSInteger generalChanges = NSPasteboard.generalPasteboard.changeCount;
        gCopyBoard = [NSPasteboard pasteboardWithUniqueName];
        NSMenu *copyMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
        NSMenuItem *copyURL = [[NSMenuItem alloc] initWithTitle:@"Copy URL" action:nil keyEquivalent:@"c"];
        copyURL.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
        NSMenuItem *copyMarkdown = [[NSMenuItem alloc] initWithTitle:@"Copy URL as Markdown" action:nil keyEquivalent:@"c"];
        copyMarkdown.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption;
        [copyMenu addItem:copyURL];
        [copyMenu addItem:copyMarkdown];
        NSMenuItem *copyRoot = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
        copyRoot.submenu = copyMenu;
        NSMenu *copyMain = [NSMenu new];
        [copyMain addItem:copyRoot];
        NSMenu *savedMain = NSApp.mainMenu;
        NSApp.mainMenu = copyMain;
        DPKVOObservedPage *copyPage = [DPKVOObservedPage new];
        copyPage.url = [NSURL URLWithString:@"https://copy.example/path"];
        copyPage.title = @"Copy Example";
        DPPeekCard *copyCard = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
        copyCard.page = (id<DPPeekPage>)copyPage;
        NSEventModifierFlags copyMods = NSEventModifierFlagCommand | NSEventModifierFlagShift;
        NSEvent *copyEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:copyMods timestamp:0 windowNumber:0
                                               context:nil characters:@"c" charactersIgnoringModifiers:@"c" isARepeat:NO keyCode:8];
        CHECK(DPPeekCopyURL(copyCard, copyEvent) && [[gCopyBoard stringForType:NSPasteboardTypeString] isEqualToString:@"https://copy.example/path"],
              "Copy URL writes the page URL to the pasteboard DPPeekPasteboard hands back");
        NSEvent *markdownEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:copyMods | NSEventModifierFlagOption
                                                 timestamp:0 windowNumber:0 context:nil characters:@"c" charactersIgnoringModifiers:@"c"
                                                 isARepeat:NO keyCode:8];
        CHECK(DPPeekCopyURL(copyCard, markdownEvent) && [[gCopyBoard stringForType:NSPasteboardTypeString] isEqualToString:@"[Copy Example](https://copy.example/path)"],
              "Copy URL as Markdown writes the title link to the scratch pasteboard");
        CHECK(NSPasteboard.generalPasteboard.changeCount == generalChanges, "Peek's Copy URL tests never touch the operator's general pasteboard");
        [gCopyBoard releaseGlobally];
        gCopyBoard = nil;
        NSApp.mainMenu = savedMain;
        CHECK(fabs(DPPeekLookAheadDelay() - 0.01) < 1e-6, "Peek delay accessor honors test override");
        CHECK(DPPeekPinnedLinks.verify && DPPeekPinnedLinks.verify(&DPPeekPinnedLinks) != nil,
              "DPPeekPinnedLinks.verify catches a missing navigation-policy hook");

        __weak NSView *weakZone = nil;
        @autoreleasepool {
            DPFakeVisibleWindow *peekWin = [[DPFakeVisibleWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 600, 400)
                                                                                  styleMask:NSWindowStyleMaskTitled
                                                                                    backing:NSBackingStoreBuffered defer:NO];
            DPPeekCard *card = [[DPPeekCard alloc] initWithFrame:peekWin.contentView.bounds];
            card.clip = [[NSView alloc] initWithFrame:card.bounds];
            card.page = (id<DPPeekPage>)opaquePage;
            [card addSubview:card.clip];
            DPPeekAddToolbar(card);
            weakZone = card.toolbarZone;
            [peekWin.contentView addSubview:card];
            DPShowLoadingProgress.on = YES;
            DPHideToolbar.on = YES;
            DPHideToolbar.progress = 1;
            [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
            [card removeFromSuperview];
            peekWin.contentView = [NSView new];
        }
        CHECK(weakZone == nil, "DPPeekBarZone deallocates cleanly with no timer/notification retain cycle");
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];

        DPStage("6. Peek ChatContext KVO off-main-thread detach race & idempotency");
        DPPeek.on = YES;
        DPKVOObservedPage *kvoPage = [DPKVOObservedPage new];
        DPKVOObservedPage *kvoSource = [DPKVOObservedPage new];
        __weak DPPeekChatBridge *weakBridge = nil;
        @autoreleasepool {
            DPPeekCard *card = [[DPPeekCard alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
            card.page = (id<DPPeekPage>)kvoPage;
            card.source = kvoSource;
            DPPeekChatBridge *bridge = [[DPPeekChatBridge alloc] initWithPeek:card];
            weakBridge = bridge;
            dispatch_semaphore_t fired = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                kvoPage.selectedText = @"from-bg";
                dispatch_semaphore_signal(fired);
            });
            dispatch_semaphore_wait(fired, DISPATCH_TIME_FOREVER);
            [bridge detach];
            [bridge detach]; // Idempotent double-detach must not throw over-remove KVO exception.
            [bridge handleKey:@"isLoading"];
        }
        DPDrainMainQueue(0.05);
        CHECK(weakBridge == nil, "DPPeekChatBridge deallocates cleanly after off-main-thread KVO + detach race");

        DPStage("7. DPStayingAction NSProxy safety");
        DPStayingAction *staying = [DPStayingAction alloc];
        staying.action = @"action-target";
        CHECK([staying respondsToSelector:@selector(navigationDisposition)], "DPStayingAction responds to navigationDisposition");
        CHECK([staying respondsToSelector:@selector(length)], "DPStayingAction forwards respondsToSelector:");
        CHECK(![staying respondsToSelector:@selector(nonexistentSelectorForActionTest)], "DPStayingAction returns NO for unknown selector");
        CHECK([staying isKindOfClass:NSString.class] && [staying conformsToProtocol:@protocol(NSCopying)],
              "DPStayingAction forwards isKindOfClass: and conformsToProtocol:");
        CHECK(staying.navigationDisposition == DPCurrentTab, "DPStayingAction overrides navigationDisposition");
        DPStayingAction *nilStaying = [DPStayingAction alloc];
        nilStaying.action = nil;
        CHECK([nilStaying respondsToSelector:@selector(navigationDisposition)] && ![nilStaying respondsToSelector:@selector(length)]
              && ![nilStaying isKindOfClass:NSString.class] && ![nilStaying conformsToProtocol:@protocol(NSCopying)],
              "nil-target DPStayingAction never aborts on NSProxy introspection");

        DPStage("8. Settings Preview: repeating NSTimer & CADisplayLink proxy break retain cycles");
        __weak DPPreviewView *weakPreview = nil;
        DPPreviewLinkProxy *linkProxy = [DPPreviewLinkProxy new];
        @autoreleasepool {
            DPFakeVisibleWindow *prevWin = [[DPFakeVisibleWindow alloc] initWithContentRect:NSMakeRect(-30000, -30000, 300, 200)
                                                                                  styleMask:NSWindowStyleMaskTitled
                                                                                    backing:NSBackingStoreBuffered defer:NO];
            DPPreviewView *preview = [[DPPreviewView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
            weakPreview = preview;
            linkProxy.target = preview;
            Ivar statesIvar = class_getInstanceVariable(DPPreviewView.class, "_states");
            Ivar mediaIvar = class_getInstanceVariable(DPPreviewView.class, "_media");
            CHECK(statesIvar != NULL && mediaIvar != NULL, "DPPreviewView ivars found");
            object_setIvar(preview, mediaIvar, [CALayer layer]);
            object_setIvar(preview, statesIvar, @[ @"s0", @"s1" ]);
            [prevWin.contentView addSubview:preview];
            [preview updatePlayback]; // Starts active repeating _flip timer on mainRunLoop!
            // Drop both window & preview without removing preview first: if timer retained self strongly, preview leaks!
            prevWin.contentView = [NSView new];
        }
        CHECK(weakPreview == nil, "DPPreviewView deallocates cleanly with zero NSTimer or CADisplayLink retain cycle");
        [linkProxy step:nil];

        DPStage("9. SkipAccount binary patcher NULL/empty guards & RX page round-trip");
        DPSkipPattern badNull = { .signature = NULL, .length = 1 };
        DPSkipInstruction dummy = { 0, 0 };
        DPSkipPattern badEmpty = { .signature = &dummy, .length = 0 };
        CHECK(!DPSkipFindPatterns(NULL, 0), "DPSkipFindPatterns rejects count=0");
        CHECK(!DPSkipFindPatterns(&badNull, 1), "DPSkipFindPatterns rejects NULL signature");
        CHECK(!DPSkipFindPatterns(&badEmpty, 1), "DPSkipFindPatterns rejects zero-length pattern");
        CHECK(!DPSkipWriteCode(NULL, 0, 0), "DPSkipWriteCode rejects NULL site");

        mach_vm_address_t codePage = 0;
        kern_return_t kr = mach_vm_allocate(mach_task_self(), &codePage, vm_page_size, VM_FLAGS_ANYWHERE);
        CHECK(kr == KERN_SUCCESS, "allocate executable page for DPSkipWriteCode");
        if (kr == KERN_SUCCESS) {
            uint32_t *slot = (uint32_t *)(uintptr_t)codePage;
            const uint32_t origInsn = 0x52800020; // mov w0, #1
            const uint32_t patchedInsn = 0x52800000; // mov w0, #0
            slot[0] = origInsn;
            slot[1] = 0xd65f03c0; // ret
            kr = mach_vm_protect(mach_task_self(), codePage, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
            sys_icache_invalidate(slot, 2 * sizeof(uint32_t));
            CHECK(kr == KERN_SUCCESS, "protect codePage RX");
            uint32_t (*fn)(void) = (uint32_t (*)(void))(void *)slot;
            CHECK(fn() == 1, "unpatched executable stub returns 1");
            CHECK(!DPSkipWriteCode(slot, 0xdeadbeef, patchedInsn), "DPSkipWriteCode rejects unexpected original word");
            CHECK(DPSkipWriteCode(slot, origInsn, patchedInsn) && slot[0] == patchedInsn && fn() == 0,
                  "DPSkipWriteCode patches RX page cleanly and invalidates icache");
            CHECK(DPSkipWriteCode(slot, patchedInsn, origInsn) && slot[0] == origInsn && fn() == 1,
                  "DPSkipWriteCode restores RX page cleanly");
            mach_vm_deallocate(mach_task_self(), codePage, vm_page_size);
        }

        DPStage("10. Swift reflection (Selection.swift) on pure Swift class (_TtCs12_SwiftObject)");
        NSString *u1 = @"11111111-2222-3333-4444-555555555555";
        NSString *u2 = @"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
        id pureMulti = DPMakePureSwiftSelection(u1, @[ u1, u2 ]);
        NSArray<NSString *> *multiKeys = DPSelectionIDKeys(pureMulti);
        CHECK(multiKeys.count == 2 && [multiKeys[0] isEqualToString:u1] && [multiKeys[1] isEqualToString:u2],
              "DPSelectionIDKeys extracts allSelectedTabIDs from pure Swift _TtCs12_SwiftObject");

        id pureSingle = DPMakePureSwiftSelection(u2, @[]);
        NSArray<NSString *> *singleKeys = DPSelectionIDKeys(pureSingle);
        CHECK(singleKeys.count == 1 && [singleKeys[0] isEqualToString:u2],
              "DPSelectionIDKeys falls back to primarySelectedTabID on pure Swift _TtCs12_SwiftObject");

        id pureBox = DPMakePureSwiftIDBox(u1);
        CHECK([[DPIDKey(pureBox) lowercaseString] isEqualToString:u1], "DPIDKey unwraps pure Swift rawValue box");
        CHECK(DPSelectionIDKeys(nil).count == 0 && DPIDKey(nil) == nil, "Swift reflection handles nil safely");

        __block int visited = 0;
        DPEachValue(@{ @"a" : @1, @"b" : @2 }, ^(id value) { if (value) visited++; });
        CHECK(visited == 2, "DPEachValue iterates dictionary values");

        if (failures) return 1;
        puts("PASS: ABI, KVC, KVO, NSProxy, Timer/DisplayLink, Swift reflection, and binary patcher checks");
    }
    return 0;
}
