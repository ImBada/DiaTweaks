#import "StdPatch/StdPatch.h"
#import "Title.h"

extern DPPatch DPTabTitles;
static char DPTitleMemoKey;

static NSString *DPContents_title(id self, SEL _cmd) {
    NSString *title = DPCallOriginal(DPContents_title, self);
    if (!DPTabTitles.on || !title.length) {
        if (!DPTabTitles.on && DPGet(self, &DPTitleMemoKey)) DPSet(self, &DPTitleMemoKey, nil);
        return title;
    }
    NSArray<NSString *> *memo = DPGet(self, &DPTitleMemoKey);
    if (memo && (memo[0] == title || [memo[0] isEqualToString:title])) return memo[1];
    NSString *raw = [title copy], *clean = DPDisplayTitle(raw);
    DPSet(self, &DPTitleMemoKey, @[ raw, clean ]);
    return clean;
}

static void DPInstallTabTitles(void) {
    DPHook(DPDiaWebContents, @selector(title), (IMP)DPContents_title);
}

DP_PATCH(DPTabTitles) {
    .key = @"tabTitles",
    .experimental = YES,
    .order = 205,
    .title = @"Clean Tab Titles",
    .detail = @"Show a tab’s own title when it starts with invisible characters that make Dia show the domain instead.",
    .hint = @"Reload open tabs after changing this setting.",
    .symbol = @"textformat",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaWebContents),
    .install = DPInstallTabTitles,
};
