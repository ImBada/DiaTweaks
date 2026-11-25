#import "PullRequestRepo.h"

static char DPDiaTextKey, DPCheckedKey, DPInListKey, DPPRCacheKey;

static NSString *DPMatch(NSString *pattern, NSString *text) {
    if (!text.length) return nil;
    static NSMutableDictionary<NSString *, NSRegularExpression *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSRegularExpression *regex = cache[pattern];
    if (!regex) cache[pattern] = regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match ? [text substringWithRange:[match rangeAtIndex:match.numberOfRanges - 1]] : nil;
}

BOOL DPIsPRSubtitle(NSView *label) {
    return DPIsKind(label, DPDiaFeatheredLabel) && DPIsKind(label.superview, DPDiaTransitioningLabel);
}

NSView *DPEnclosingView(NSView *view, const char *className) {
    while (view && !DPIsKind(view, className)) view = view.superview;
    return view;
}

static BOOL DPInTabList(NSView *view) { return DPEnclosingView(view, DPDiaTabListCollection) != nil; }

NSString *DPPRTabIDOf(NSView *view) {
    view = DPEnclosingView(view, DPDiaTabContentView);
    id controller = DPSwiftValue(DPSwiftValue(view, @"viewModel"), @"delegate");
    return DPMatch(@"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", [DPSwiftValue(controller, @"tabID") description]);
}

NSDictionary *DPPullRequestOf(NSView *view) {
    view = DPEnclosingView(view, DPDiaTabContentView);
    if (!view) return nil;
    id controller = DPSwiftValue(DPSwiftValue(view, @"viewModel"), @"delegate");
    NSString *item = [DPSwiftValue(controller, @"currentlyRenderedLiveItem") description];
    if (![item containsString:@".pullRequest("]) return nil;
    NSString *rawTab = [DPSwiftValue(controller, @"tabID") description] ?: @"";
    NSArray *cached = DPGet(view, &DPPRCacheKey);
    if (cached && [cached[0] isEqualToString:item] && [cached[1] isEqualToString:rawTab])
        return cached[2] == NSNull.null ? nil : cached[2];
    NSString *repo = DPMatch(@"github\\.com/[^/\\s]+/([^/\\s)]+)/pull/[0-9]+", item), *number = DPMatch(@"github\\.com/[^\\s)]+/pull/([0-9]+)", item);
    NSString *author = DPMatch(@"author: \"([^\"]+)\"", item), *state = DPMatch(@"PullRequest\\.Status\\.([a-zA-Z]+)", item);
    NSString *tab = DPMatch(@"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}", rawTab);
    NSDictionary *parsed = nil;
    if (repo && number && author) {
        NSString *line = [NSString stringWithFormat:@"%@ #%@", repo, number];
        state = state.length ? [[state substringToIndex:1].uppercaseString stringByAppendingString:[state substringFromIndex:1]] : @"";
        if (state.length) line = [line stringByAppendingFormat:@" · %@", state];
        parsed = @{@"repo": line, @"state": state, @"author": author, @"tab": tab ?: @""};
    }
    DPSet(view, &DPPRCacheKey, @[ item, rawTab, parsed ?: NSNull.null ]);
    return parsed;
}

static NSString *DPSplit(NSView *label, NSString *text, NSString **status, NSString **tab) {
    NSDictionary *pr = text.length ? DPPullRequestOf(label) : nil;
    NSString *author = pr[@"author"];
    if (!pr || ![text hasPrefix:author]) return nil;
    NSString *rest = [text substringFromIndex:author.length];
    if (rest.length && ![rest hasPrefix:@" "] && ![rest hasPrefix:@"•"]) return nil;
    NSString *review = [rest stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" •"]];
    *tab = pr[@"tab"];
    if (!review.length) return [pr[@"repo"] stringByAppendingString:rest];
    NSString *words = [[review componentsSeparatedByCharactersInSet:NSCharacterSet.letterCharacterSet.invertedSet] componentsJoinedByString:@""];
    NSString *repo = pr[@"repo"], *state = pr[@"state"], *from = [rest substringFromIndex:[rest rangeOfString:review].location];
    if (state.length && [words caseInsensitiveCompare:state] == NSOrderedSame)
        return [[repo substringToIndex:repo.length - state.length] stringByAppendingString:from];
    if (!DPInTabList(label)) return [repo stringByAppendingString:rest];
    *status = from;
    return repo;
}

static void DPRelayoutRow(NSView *label) {
    for (NSView *view = label.superview; view; view = view.superview) {
        view.needsLayout = YES;
        if (DPIsKind(view, DPDiaTabContentView)) break;
    }
}

static void DPLabel_setStringValue(NSTextField *self, SEL _cmd, NSString *value) {
    if (!DPPullRequestRepo.on) {
        if (DPGet(self, &DPDiaTextKey)) {
            DPSet(self, &DPDiaTextKey, nil);
            DPSet(self, &DPCheckedKey, nil);
            DPSetPRStatus(self, nil, nil);
        }
        return DPCallOriginal(DPLabel_setStringValue, self, value);
    }
    if (!DPIsPRSubtitle(self)) return DPCallOriginal(DPLabel_setStringValue, self, value);
    NSString *status = nil, *tab = nil, *shown = value ? DPSplit(self, value, &status, &tab) : nil;
    NSArray *saved = DPGet(self, &DPDiaTextKey);
    if (!shown && saved && [value isEqual:saved[1]] && DPPullRequestOf(self)) {
        DPSet(self, &DPCheckedKey, value);
        DPSet(self, &DPInListKey, @(DPInTabList(self)));
        return DPCallOriginal(DPLabel_setStringValue, self, value);
    }
    if (shown) DPOverride(self, &DPDiaTextKey, value, shown);
    else if (saved) DPSet(self, &DPDiaTextKey, nil);
    DPSet(self, &DPCheckedKey, shown ?: value);
    DPSet(self, &DPInListKey, @(DPInTabList(self)));
    DPSetPRStatus(self, tab ?: DPPRTabIDOf(self), status);
    DPCallOriginal(DPLabel_setStringValue, self, shown ?: value);
}

static void DPLabel_layout(NSTextField *self, SEL _cmd) {
    DPCallOriginal(DPLabel_layout, self);
    if (!DPIsPRSubtitle(self)) return;
    if (!DPPullRequestRepo.on) {
        if (!DPGet(self, &DPDiaTextKey)) return;
        self.stringValue = DPDiaValue(self, &DPDiaTextKey, self.stringValue);
        DPRelayoutRow(self);
        return;
    }
    BOOL moved = [DPGet(self, &DPInListKey) boolValue] != DPInTabList(self);
    if (!moved && [self.stringValue isEqual:DPGet(self, &DPCheckedKey)]) return;
    self.stringValue = DPDiaValue(self, &DPDiaTextKey, self.stringValue);
    DPRelayoutRow(self);
}

static void DPCollectLabels(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (NSView *sub in view.subviews) DPCollectLabels(sub, cls, out);
}

void DPRefreshPRSubtitles(void) {
    Class cls = objc_getClass(DPDiaFeatheredLabel);
    if (!cls) return;
    NSMutableArray<NSView *> *labels = [NSMutableArray new];
    for (NSWindow *window in NSApp.windows) DPCollectLabels(window.contentView, cls, labels);
    for (NSView *view in labels) {
        if (!DPIsPRSubtitle(view)) continue;
        if (!DPPullRequestRepo.on && !DPGet(view, &DPDiaTextKey)) continue;
        NSTextField *label = (NSTextField *)view;
        label.stringValue = DPDiaValue(label, &DPDiaTextKey, label.stringValue);
        DPRelayoutRow(label);
    }
}

void DPInstallPRSubtitles(void) {
    DPHook(DPDiaFeatheredLabel, @selector(setStringValue:), (IMP)DPLabel_setStringValue);
    DPHook(DPDiaFeatheredLabel, @selector(layout), (IMP)DPLabel_layout);
}
