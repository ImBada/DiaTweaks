#import "StdPatch/Hide.h"

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
BOOL DPTesting = YES;

#import "Patches/HideTrialButton/HideTrialButton.m"
#import "Patches/HideSetupSuggestions/HideSetupSuggestions.m"
#import "Patches/HideDefaultBrowserBanner/HideDefaultBrowserBanner.m"
#import "Patches/HideHistorySuggestions/HideHistorySuggestions.m"
#import "StdPatch/Hide.m"
#import "StdPatch/HideHosts.m"

@interface DPFakeHistoryResult : NSObject
@property(nonatomic, strong) NSArray *combinedMatches;
@property(nonatomic, strong) NSDictionary *perProviderMatches;
- (instancetype)init:(NSArray *)combined perProviderMatches:(NSDictionary *)perProvider;
@end
@implementation DPFakeHistoryResult
- (instancetype)init:(NSArray *)combined perProviderMatches:(NSDictionary *)perProvider {
    if ((self = [super init])) {
        _combinedMatches = combined;
        _perProviderMatches = perProvider;
    }
    return self;
}
@end

@interface _TtC13NavigationBar17NavigationBarView : NSView
@end
@implementation _TtC13NavigationBar17NavigationBarView
@end

@interface _TtC13NavigationBar24AdvancedChatUpsellButton : NSView
@end
@implementation _TtC13NavigationBar24AdvancedChatUpsellButton
@end

@interface _TtC14DefaultBrowser24DefaultBrowserUpsellView : NSView
@end
@implementation _TtC14DefaultBrowser24DefaultBrowserUpsellView
@end

@interface _TtC15BoostCommandBar19SuggestionTitleView : NSView
@end
@implementation _TtC15BoostCommandBar19SuggestionTitleView
@end

@interface _TtC15BoostCommandBar23SuggestionTableViewCell : NSTableCellView
@end
@implementation _TtC15BoostCommandBar23SuggestionTableViewCell
@end

@interface _TtC15BoostCommandBar15SuggestionsView : NSView <NSTableViewDelegate>
@end
@implementation _TtC15BoostCommandBar15SuggestionsView
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row { return 28; }
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row { return YES; }
@end

// Stands in for Dia's table: the rows are handed to it, so the test never needs a laid-out table view.
@interface _TtCC15BoostCommandBar15SuggestionsViewP33_086B7AAC03146EB344074D77152861FE9TableView : NSTableView
@property(nonatomic) NSMutableArray<NSView *> *rows;
@property(nonatomic) NSInteger notes;
@end
@implementation _TtCC15BoostCommandBar15SuggestionsViewP33_086B7AAC03146EB344074D77152861FE9TableView
- (NSInteger)numberOfRows { return (NSInteger)self.rows.count; }
- (NSInteger)rowForView:(NSView *)view {
    NSUInteger row = [self.rows indexOfObjectIdenticalTo:view];
    return row == NSNotFound ? -1 : (NSInteger)row;
}
- (NSView *)viewAtColumn:(NSInteger)column row:(NSInteger)row makeIfNecessary:(BOOL)makeIfNecessary {
    return row >= 0 && row < (NSInteger)self.rows.count ? self.rows[row] : nil;
}
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)indexes { self.notes++; }
- (void)reloadData { self.notes = 0; }
@end

@interface DPOuterHost : NSView
@end
@implementation DPOuterHost
@end

@interface DPInnerButton : NSView
@end
@implementation DPInnerButton
@end

static BOOL isOuterHost(NSView *view) { return [view isKindOfClass:DPOuterHost.class]; }
static BOOL isInnerButton(NSView *view) { return [view isKindOfClass:DPInnerButton.class]; }

@interface DPTestWindow : NSWindow
@end
@implementation DPTestWindow
- (BOOL)isVisible { return YES; }
@end

static int failures;

static void check(const char *what, BOOL ok) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

static _TtC15BoostCommandBar23SuggestionTableViewCell *makeCell(NSString *title) {
    _TtC15BoostCommandBar23SuggestionTableViewCell *cell = [[_TtC15BoostCommandBar23SuggestionTableViewCell alloc] initWithFrame:NSMakeRect(0, 0, 300, 28)];
    _TtC15BoostCommandBar19SuggestionTitleView *titleView = [[_TtC15BoostCommandBar19SuggestionTitleView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
    [titleView addSubview:[NSTextField labelWithString:title]];
    [cell addSubview:titleView];
    return cell;
}

static void layoutAll(NSArray<NSView *> *cells) {
    for (NSView *cell in cells) [cell layout];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        DPPatch *patches[] = { &DPHideTrialButton, &DPHideSetupSuggestions, &DPHideDefaultBrowserBanner };
        DPPatches = patches;
        DPPatchCount = 3;

        DPHideTrialButton.on = NO;
        DPHideSetupSuggestions.on = NO;
        DPHideDefaultBrowserBanner.on = NO;
        DPInstallHides();
        DPHideTrialButton.install();
        DPHideSetupSuggestions.install();
        DPHideDefaultBrowserBanner.install();

        DPTestWindow *window = [[DPTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 700)
                                                               styleMask:NSWindowStyleMaskBorderless
                                                                 backing:NSBackingStoreBuffered
                                                                   defer:NO];

        _TtC13NavigationBar17NavigationBarView *toolbar = [[_TtC13NavigationBar17NavigationBarView alloc] initWithFrame:NSMakeRect(0, 660, 1000, 40)];
        _TtC13NavigationBar24AdvancedChatUpsellButton *trial = [[_TtC13NavigationBar24AdvancedChatUpsellButton alloc] initWithFrame:NSMakeRect(900, 6, 90, 28)];
        NSView *share = [[NSView alloc] initWithFrame:NSMakeRect(800, 6, 40, 28)];
        _TtC13NavigationBar24AdvancedChatUpsellButton *diaHiddenTrial = [[_TtC13NavigationBar24AdvancedChatUpsellButton alloc] initWithFrame:NSMakeRect(700, 6, 90, 28)];
        diaHiddenTrial.hidden = YES;
        for (NSView *view in @[ trial, share, diaHiddenTrial ]) [toolbar addSubview:view];
        [window.contentView addSubview:toolbar];

        check("trial predicate matches the pill", DPIsTrialButton(trial));
        check("trial predicate leaves other toolbar views alone", !DPIsTrialButton(share));

        [toolbar layout];
        check("trial pill shows while the tweak is off", !trial.hidden);
        check("a pill Dia hid itself stays hidden while the tweak is off", diaHiddenTrial.hidden);

        DPHideTrialButton.on = YES;
        DPApplyHides(&DPHideTrialButton);
        [toolbar layout];
        check("trial pill hides when the tweak is on", trial.hidden);
        check("other toolbar views still show", !share.hidden);
        check("a pill Dia hid itself is still hidden", diaHiddenTrial.hidden);

        DPHideTrialButton.on = NO;
        DPApplyHides(&DPHideTrialButton);
        [toolbar layout];
        check("trial pill comes back when the tweak is turned off", !trial.hidden);
        check("a pill Dia hid itself is not revealed by turning the tweak off", diaHiddenTrial.hidden);

        // Dia 1.59.0's new tab page is not one of the hide hosts, so the banner has to hide itself.
        NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 600)];
        _TtC14DefaultBrowser24DefaultBrowserUpsellView *banner = [[_TtC14DefaultBrowser24DefaultBrowserUpsellView alloc] initWithFrame:NSMakeRect(0, 0, 1000, 40)];
        NSView *pageContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 40, 1000, 560)];
        [page addSubview:banner];
        [page addSubview:pageContent];
        [window.contentView addSubview:page];

        check("banner predicate matches the banner", DPIsDefaultBrowserBanner(banner));
        check("banner predicate leaves the page alone", !DPIsDefaultBrowserBanner(pageContent));

        [banner layout];
        check("banner shows while the tweak is off", !banner.hidden);

        DPHideDefaultBrowserBanner.on = YES;
        DPApplyHides(&DPHideDefaultBrowserBanner);
        [banner layout];
        check("banner hides when the tweak is on", banner.hidden);
        check("the page itself still shows", !pageContent.hidden);

        DPHideDefaultBrowserBanner.on = NO;
        DPApplyHides(&DPHideDefaultBrowserBanner);
        [banner layout];
        check("banner comes back when the tweak is turned off", !banner.hidden);

        _TtC15BoostCommandBar15SuggestionsView *suggestions = [[_TtC15BoostCommandBar15SuggestionsView alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)];
        _TtCC15BoostCommandBar15SuggestionsViewP33_086B7AAC03146EB344074D77152861FE9TableView *table =
            [[_TtCC15BoostCommandBar15SuggestionsViewP33_086B7AAC03146EB344074D77152861FE9TableView alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)];
        NSArray<NSString *> *titles = @[ @"Upgrade Chat", @"Some Page", @"Import from another browser", @"Sign in to Google Calendar", @"Import passwords" ];
        NSMutableArray<NSView *> *cells = [NSMutableArray array];
        for (NSString *title in titles) [cells addObject:makeCell(title)];
        table.rows = cells;
        for (NSView *cell in cells) [table addSubview:cell];
        [suggestions addSubview:table];
        [window.contentView addSubview:suggestions];

        _TtC15BoostCommandBar23SuggestionTableViewCell *onboarding = (_TtC15BoostCommandBar23SuggestionTableViewCell *)cells[0];
        _TtC15BoostCommandBar23SuggestionTableViewCell *real = (_TtC15BoostCommandBar23SuggestionTableViewCell *)cells[1];
        check("setup predicate matches “Upgrade Chat”", DPIsSetupSuggestion(onboarding));
        check("setup predicate matches “Import from another browser”", DPIsSetupSuggestion(cells[2]));
        check("setup predicate matches “Sign in to Google Calendar”", DPIsSetupSuggestion(cells[3]));
        check("setup predicate matches “Import passwords”", DPIsSetupSuggestion(cells[4]));
        check("setup predicate leaves a real suggestion alone", !DPIsSetupSuggestion(real));

        layoutAll(cells);
        check("setup rows show while the tweak is off", !onboarding.hidden && !real.hidden);
        check("every row keeps its height while the tweak is off", [suggestions tableView:table heightOfRow:0] == 28);

        DPHideSetupSuggestions.on = YES;
        DPHideSetupSuggestions.apply(&DPHideSetupSuggestions);
        layoutAll(cells);
        check("setup row hides when the tweak is on", onboarding.hidden);
        check("a real suggestion still shows", !real.hidden);
        check("a setup row collapses to no height", [suggestions tableView:table heightOfRow:0] == 0);
        check("a real suggestion keeps its height", [suggestions tableView:table heightOfRow:1] == 28);
        check("a setup row cannot be picked", ![suggestions tableView:table shouldSelectRow:0]);
        check("a real suggestion can still be picked", [suggestions tableView:table shouldSelectRow:1]);
        check("the table is asked to re-measure the collapsed row", table.notes > 0);

        DPHideSetupSuggestions.on = NO;
        DPHideSetupSuggestions.apply(&DPHideSetupSuggestions);
        layoutAll(cells);
        check("setup row comes back when the tweak is turned off", !onboarding.hidden);
        check("a setup row gets its height back", [suggestions tableView:table heightOfRow:0] == 28);
        check("a real suggestion is untouched by turning the tweak off", !real.hidden && [suggestions tableView:table heightOfRow:1] == 28);

        DPHideSetupSuggestions.on = YES;
        DPHideSetupSuggestions.apply(&DPHideSetupSuggestions);
        layoutAll(cells);
        check("setup row collapses again", [suggestions tableView:table heightOfRow:0] == 0);
        NSMutableArray<NSView *> *reused = [NSMutableArray array];
        for (NSString *title in @[ @"Some Page", @"Another Page", @"Third Page", @"Fourth Page", @"Fifth Page" ]) [reused addObject:makeCell(title)];
        table.rows = reused;
        [table reloadData];
        layoutAll(reused);
        check("a reused row is not left collapsed", [suggestions tableView:table heightOfRow:0] == 28);
        check("a reused row shows its suggestion", !reused[0].hidden);

        DPHideSetupSuggestions.on = NO;
        DPHideSetupSuggestions.apply(&DPHideSetupSuggestions);

        static DPPatch outer = { .key = @"outerTest", .hides = isOuterHost }, inner = { .key = @"innerTest", .hides = isInnerButton };
        DPPatch *nested[] = { &outer, &inner };
        DPPatches = nested;
        DPPatchCount = 2;
        DPOuterHost *outerView = [[DPOuterHost alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        DPInnerButton *innerButton = [[DPInnerButton alloc] initWithFrame:NSMakeRect(0, 0, 40, 20)];
        [outerView addSubview:innerButton];
        [window.contentView addSubview:outerView];
        [DPHideHosts addObject:outerView];

        DPEnforceHides(outerView);
        check("nothing is enforced or hooked while every tweak is off",
              !innerButton.hidden && !outerView.hidden && DPSuppressed.count == 0
              && !DPIsHooked(DPInnerButton.class, @selector(setHidden:), (IMP)DPHidden_setHidden)
              && !DPIsHooked(DPOuterHost.class, @selector(isHidden), (IMP)DPHidden_isHidden));

        inner.on = YES;
        DPApplyHides(&inner);
        check("a tweak that is off doesn't shadow the on tweak's view inside its container", innerButton.hidden && !outerView.hidden);
        check("only the class an on tweak hides gets hooked",
              DPIsHooked(DPInnerButton.class, @selector(setHidden:), (IMP)DPHidden_setHidden)
              && !DPIsHooked(DPOuterHost.class, @selector(setHidden:), (IMP)DPHidden_setHidden)
              && !DPIsHooked(DPOuterHost.class, @selector(viewDidMoveToWindow), (IMP)DPHidden_viewDidMoveToWindow));
        check("the on tweak verifies through the off tweak's container", !DPProblem(outerView, &inner));
        check("the off tweak has nothing to verify", !DPProblem(outerView, &outer));

        outer.on = YES;
        DPApplyHides(&outer);
        check("turning the container's tweak on hides the container", outerView.hidden);
        outer.on = NO;
        DPApplyHides(&outer);
        check("turning it off again restores only the container", !outerView.hidden && innerButton.hidden);

        inner.on = NO;
        DPApplyHides(&inner);
        check("turning the inner tweak off restores its view once and clears the marker", !innerButton.hidden && DPSuppressed.count == 0);

        DPHideTrialButton.on = YES;
        DPPatch *replaced[] = { &DPHideTrialButton };
        DPPatches = replaced;
        DPPatchCount = 1;
        check("a new patch table is matched from scratch", DPHider(trial) == &DPHideTrialButton && !DPHider([[DPInnerButton alloc] initWithFrame:NSZeroRect]));
        DPHideTrialButton.on = NO;

        NSDictionary *hist = @{ @"hasTabMatch" : @NO, @"providerType" : @"HistoryURL", @"matchType" : @"history-url" };
        NSDictionary *search = @{ @"hasTabMatch" : @NO, @"providerType" : @"Search", @"matchType" : @"search-what-you-typed" };
        NSDictionary *typed = @{ @"hasTabMatch" : @NO, @"providerType" : @"HistoryURL", @"matchType" : @"url-what-you-typed" };
        DPFakeHistoryResult *streaming = [[DPFakeHistoryResult alloc] init:nil perProviderMatches:@{ @"HistoryURL" : @[ hist ], @"Search" : @[ search ] }];
        DPFakeHistoryResult *filteredStreaming = DPWithoutHistory(streaming);
        check("per-provider-only autocomplete result preserves nil combinedMatches", filteredStreaming.combinedMatches == nil);
        check("per-provider-only autocomplete result strips history provider and keeps search",
              !filteredStreaming.perProviderMatches[@"HistoryURL"] && [filteredStreaming.perProviderMatches[@"Search"] isEqual:@[ search ]]);

        DPFakeHistoryResult *combinedOnly = [[DPFakeHistoryResult alloc] init:@[ hist, typed ] perProviderMatches:nil];
        DPFakeHistoryResult *filteredCombined = DPWithoutHistory(combinedOnly);
        check("combined-only autocomplete result preserves nil perProviderMatches and keeps url-what-you-typed",
              filteredCombined.perProviderMatches == nil && [filteredCombined.combinedMatches isEqual:@[ typed ]]);

        DPFakeHistoryResult *allHist = [[DPFakeHistoryResult alloc] init:@[ hist ] perProviderMatches:@{ @"HistoryURL" : @[ hist ] }];
        DPFakeHistoryResult *filteredEmpty = DPWithoutHistory(allHist);
        check("non-nil combinedMatches with only history becomes empty array, not nil",
              filteredEmpty.combinedMatches != nil && filteredEmpty.combinedMatches.count == 0 && filteredEmpty.perProviderMatches.count == 0);

        if (failures) printf("%d failure(s)\n", failures);
        else printf("hide-ntp-prompts: all checks passed\n");
        return failures ? 1 : 0;
    }
}
