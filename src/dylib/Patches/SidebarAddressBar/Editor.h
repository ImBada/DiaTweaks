#import "NativeControls.h"

@interface DPAddressSuggestionList : NSStackView
@property (copy) void (^hoverChanged)(NSInteger);
@property (copy) void (^activateIndex)(NSInteger);
@property NSTrackingArea *hoverTracking;
- (NSInteger)indexAtPoint:(NSPoint)point;
@end

@interface DPSidebarAddressRow () <NSTextFieldDelegate>
@property NSButton *address;
@property NSTextField *inlineEditor;
@property BOOL startingSuggestionSession;
@property (weak) NSView *nativeSuggestionPanel;
@property CGFloat nativeSuggestionAlpha;
@property BOOL submittingSuggestion;
@property (weak) NSView *nativeOverlay;
@property NSMapTable<NSView *, NSNumber *> *nativeSurfaceAlphas;
@property (weak) NSTextView *nativeSuggestionEditor;
@property NSArray<NSNumber *> *nativeSuggestionRows;
@property NSArray<NSImage *> *nativeSuggestionIcons;
@property NSUInteger suggestionGeneration;
@property DPAddressSuggestionList *suggestions;
@property NSInteger hoveredSuggestion;
@property NSArray<NSString *> *suggestionURLs;
@property NSInteger selectedSuggestion;
@property NSTimer *suggestionTimer;
@property NSString *editingTabURL;
@property NSString *editingTabID;
@property BOOL pendingSubmit;
@property (nonatomic) BOOL nativeEditorVisible;
@property NSUInteger copyFeedback;
@property id editingClickMonitor;
@property (weak) NSTextView *addressFieldEditor;
@property (weak) NSWindow *inlineHostWindow;
@property NSColor *previousCaretColor;
@end


@interface DPSidebarAddressRow (EditorMethods)
- (void)finishInlineEditing;
- (void)startSuggestionSession;
- (void)updateNativeSuggestionsWithQuery:(NSString *)query;
- (void)refreshNativeSuggestions;
- (NSTableView *)nativeSuggestionTable;
- (void)submitSuggestionAtIndex:(NSInteger)index;
- (void)submitAddress:(NSString *)address;
- (void)renderSuggestions;
- (void)positionSuggestions;
- (void)dismissSuggestionList;
- (void)highlightSuggestion:(NSInteger)index;
- (void)refreshSuggestionHighlight;
@end
void DPSidebarSetInlineOwner(DPSidebarAddressRow *row, BOOL active);
void DPSidebarShieldDropdown(NSView *surface, NSWindow *parent);
void DPSidebarUnshieldDropdown(NSView *surface);
NSColor *DPSidebarEditorFill(void);
NSColor *DPSidebarEditorBorder(void);

NSImage *DPSidebarSuggestionIcon(NSImage *image);
void DPSidebarHideSuggestionSurface(NSView *surface, BOOL hide);

BOOL DPSidebarSuggestionsContainScreenPoint(NSPoint point);
void DPSidebarInstallSuggestionTooltips(void);

void DPSidebarInstallSuggestionOverlay(void);
void DPSidebarQuietSuggestionOverlay(DPSidebarAddressRow *row);
