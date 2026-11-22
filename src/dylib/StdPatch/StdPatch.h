#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "StdPatch/Dia.h"

typedef struct DPPatch DPPatch;
struct DPPatch {
    __unsafe_unretained NSString *key;
    BOOL defaultOn;
    int order;
    __unsafe_unretained NSString *title, *detail;
    __unsafe_unretained NSString *hint;
    __unsafe_unretained NSString *symbol, *tint;  // symbol: space-separated fallbacks for older macOS. tint: an NSColor class property.
    __unsafe_unretained NSString *section;
    const char *const *classes;
    __unsafe_unretained NSString *requires;
    __unsafe_unretained NSString *disabledBy;
    __unsafe_unretained NSString *coveredBy;
    BOOL relaunch;  // Applies only at launch.
    __unsafe_unretained NSString *choice, *defaultChoice;  // Saved as the chosen item's representedObject.
    NSMenu *(*choices)(void);
    NSArray<NSView *> *(*rows)(void);
    __unsafe_unretained NSString *shortcut, *sharesShortcutWith;
    NSDictionary *(*defaultShortcut)(void);
    BOOL (*hides)(NSView *view);
    void (*install)(void);  // Runs at launch whether or not the patch is on.
    void (*apply)(DPPatch *patch);  // Without it, `progress` eases toward `on` and every `relayout` runs each frame.
    void (*relayout)(void);
    // nil if Dia's views match `on`, else what's wrong. Use DPFindViews, not your hooks, so a hook that never ran fails.
    NSString *(*verify)(DPPatch *patch);
    BOOL (*animating)(void);  // Non-nil when verify must wait for an ease.
    NSString *(*ready)(DPPatch *patch);
    BOOL on, unavailable;
    CGFloat progress;
};

#define DPClasses(...) ((const char *const []){__VA_ARGS__, NULL})

#define DP_PATCH(name)                                                                                                      \
    DPPatch name;                                                                                                           \
    __attribute__((used, no_sanitize("address"), section("__DATA,__dppatches"))) static DPPatch *const name##Entry = &name; \
    DPPatch name =

extern DPPatch *const *DPPatches;
extern NSUInteger DPPatchCount;
DPPatch *DPPatchNamed(NSString *key);
DPPatch *DPRequired(DPPatch *patch);
void DPSetPatch(DPPatch *patch, BOOL on, BOOL save);
void DPApplySavedSettings(void);
BOOL DPEffectiveOn(DPPatch *patch);
BOOL DPAnimating(void);
BOOL DPSavedOn(DPPatch *patch);
NSString *DPChoice(DPPatch *patch);
void DPSetChoice(DPPatch *patch, NSString *value);
void DPLoadPatches(void);
void DPWatchSavedSettings(void);
void DPInstallPatches(void);
BOOL DPWriteManifest(NSString *path);
NSString *DPAppSupport(NSString *path);
NSArray<NSString *> *DPHostFolders(void);
NSString *DPHostFolder(BOOL create, NSError **error);
NSString *DPSystemHostFolder(void);
NSString *DPRelayProblem(void);
NSString *DPHostProblem(NSString *manifest, NSString *name);
NSString *DPWriteProblem(NSString *path, NSError *error);
extern NSNotificationName const DPPatchesDidChangeNotification;
#define DPLeadingOption @"DPLeadingOption"
extern BOOL DPTesting;

typedef struct DPHookFrame {
    const void *object;
    SEL sel;
    IMP replacement;
    Class cls;
    struct DPHookFrame *previous;
} DPHookFrame;

void DPHook(const char *className, SEL sel, IMP replacement);
void DPHookClass(Class cls, SEL sel, IMP replacement);
BOOL DPIsHooked(Class cls, SEL sel, IMP replacement);
IMP DPDiaIMP(Class cls, SEL sel);
IMP DPOriginalIMP(id object, SEL sel, IMP replacement);
IMP DPPushOriginalIMP(id object, SEL sel, IMP replacement, DPHookFrame *frame);
void DPPopOriginalIMP(DPHookFrame *frame);

#define DPCallOriginal(hook, self, ...)                                                                      \
    ({                                                                                                       \
        DPHookFrame dp_frame __attribute__((cleanup(DPPopOriginalIMP)));                                     \
        ((__typeof__(&hook))DPPushOriginalIMP(self, _cmd, (IMP)hook, &dp_frame))(self, _cmd, ##__VA_ARGS__); \
    })

NSView *DPFindView(NSView *root, BOOL (^match)(NSView *view));
NSArray<NSView *> *DPFindViews(const char *className);
NSString *DPTabLayout(void);
NSView *DPSubview(NSView *parent, const char *className);
BOOL DPIsKind(id object, const char *className);
BOOL DPIsFloatingChat(NSView *popover);
BOOL DPIsChatButton(NSView *view);
BOOL DPHasLabel(NSView *view, NSString *accessibilityLabel);
void DPRelayoutViews(NSHashTable<NSView *> *views);
// Call before changing a frame during layout: if Dia keeps restoring it, the two loop until AppKit aborts Dia.
BOOL DPMayAdjust(NSView *view);
void *DPIvar(id object, const char *name);
id DPSwiftValue(id object, NSString *key);
static inline id DPValueForKey(id object, NSString *key) {
    if (!object || !key) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}
static inline BOOL DPSetValueForKey(id object, NSString *key, id value) {
    if (!object || !key) return NO;
    @try { [object setValue:value forKey:key]; return YES; } @catch (NSException *exception) { return NO; }
}
NSMenu *DPTabContextMenu(NSView *tab);
NSArray<NSString *> *DPUUIDsIn(NSString *text);
NSWindowController *DPOpenTabSwitcher(void);

void DPSetHint(NSView *view, NSString *text);
NSString *DPHintOf(NSView *view);
void DPShowHint(NSView *view);

NSView *DPShortcutRow(DPPatch *patch);
BOOL DPShortcutMatches(NSEvent *event, DPPatch *patch);
BOOL DPShortcutRecording(void);
BOOL DPEventIsKey(NSEvent *event, NSString *key);

id DPGet(id object, const void *key);
void DPSet(id object, const void *key, id value);

void DPOverride(id object, const void *key, id dia, id ours);
id DPDiaValue(id object, const void *key, id current);

NSURL *DPAddressURL(NSString *typed);

float DPZoomStep(float now, int direction);

// Call DPLoad*/DPAdd* when on, or DPDrop* when off, from install.
void DPLoadExtension(NSString *folder);
void DPAddLaunchFlag(NSString *flag);
void DPDropExtension(NSString *folder);
void DPDropLaunchFlag(NSString *flag);
void DPDropStaleLaunchFlags(void);

void DPOnLaunch(void (^block)(void));
void DPOnQuit(void (^block)(void));

// Menus exist once Dia has launched: call these from DPOnLaunch.
NSMenuItem *DPMenuItem(NSString *title, void (^action)(void));
NSMenuItem *DPAddMenuItem(NSString *menu, NSString *title, void (^action)(void));
void DPOnMenuItem(NSString *menu, NSString *titlePrefix, void (^action)(void));
