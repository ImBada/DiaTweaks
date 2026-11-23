#import "StdPatch/StdPatch.h"
#import "Updates/Updates.h"
#import "SafeMode/SafeMode.h"

void DPInstallSettings(void);
void DPInstallPreviews(void);

extern NSToolbarItemIdentifier const DPSearchItemIdentifier;

NSView *DPGroup(NSArray<NSView *> *rows);
NSView *DPRow(NSView *leading, NSView *trailing);
NSView *DPLinkRow(NSView *row, NSString *title, void (^open)(void));
NSTextField *DPLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color);
NSTextField *DPHeader(NSString *text);
NSView *DPIconTile(NSString *symbol, NSColor *color);
NSView *DPIconTileOfSize(NSString *symbol, NSColor *color, CGFloat size);
NSImageView *DPSymbol(NSString *symbols, CGFloat size, NSColor *color);
NSStackView *DPColumn(NSArray<NSView *> *views, CGFloat spacing);
NSStackView *DPHeading(NSString *symbol, NSString *tint, NSArray<NSView *> *lines);
NSStackView *DPDisclosure(NSView *leading);
NSTextField *DPHiddenNote(void);
void DPFillStack(NSStackView *stack, NSArray<NSView *> *views);

@interface DPFlippedView : NSView
@end

@interface DPFillView : NSView
@end

@interface DPPatchSwitch : NSSwitch
@property (nonatomic, readonly) DPPatch *patch;
@property (nonatomic, readonly) NSImageView *hiddenIcon;
- (NSView *)withHiddenIcon;
- (instancetype)initWithPatch:(DPPatch *)patch;
- (void)sync;
@end

void DPForEachOption(DPPatch *patch, void (^body)(DPPatch *option));
BOOL DPShownOn(DPPatch *patch);
NSString *DPActiveSummary(DPPatch *patch);
NSString *DPWhyDisabled(DPPatch *patch);
NSString *DPWhyHidden(DPPatch *patch);
NSString *DPWhyHiddenBy(DPPatch *disabler);
NSURL *DPWikiURL(DPPatch *patch);
NSArray<NSString *> *DPRelaunchingOnPause(void);
void DPSyncPauseRow(NSTextField *label, NSButton *button);
void DPSetTweaksPaused(BOOL paused, NSWindow *window);

typedef struct DPFolderSpec {
    __unsafe_unretained NSString *key, *title, *detail, *symbol, *tint, *section;
} DPFolderSpec;

const DPFolderSpec *DPFolderSpecNamed(NSString *key);
NSArray<NSValue *> *DPFolderMembers(NSString *key);
NSColor *DPTintColor(NSString *tint);

@interface DPPreviewView : DPFillView
- (instancetype)initWithKey:(NSString *)key;
@end

@interface DPPageView : NSStackView
- (instancetype)initWithPatch:(DPPatch *)patch;
- (void)sync;
@end

@interface DPFolderView : NSStackView
- (instancetype)initWithFolder:(const DPFolderSpec *)folder;
@property (nonatomic, copy) void (^open)(NSString *title, NSView *page);
- (void)sync;
@end

@protocol DPPaneContent <NSObject>
@property (nonatomic, copy) void (^open)(NSString *title, NSView *page);
@optional
- (void)syncWithQuery:(NSString *)query;
- (void)refresh;
@end

@interface DPOverviewView : NSStackView <DPPaneContent>
@property (nonatomic, copy) void (^open)(NSString *title, NSView *page);
@property (nonatomic, strong) NSMapTable<NSView *, NSString *> *searchText;
- (void)syncWithQuery:(NSString *)query;
@end

@interface DPHomeView : NSStackView <DPPaneContent>
@property (nonatomic, copy) void (^open)(NSString *title, NSView *page);
- (void)refresh;
@end

@interface DPSoftwareUpdateView : NSStackView
@end

@interface DPPaneView : NSView <NSSearchFieldDelegate>
- (instancetype)initWithTitle:(NSString *)title content:(NSView<DPPaneContent> *)content;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSView<DPPaneContent> *content;
@property (nonatomic, readonly) NSSearchToolbarItem *searchItem;
@property (nonatomic, copy) void (^titleChanged)(NSString *title, BOOL canGoBack);
@property (nonatomic, readonly) BOOL showsPage;
- (void)goBack;
- (void)reset;
@end
