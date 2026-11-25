#import "StdPatch/StdPatch.h"

extern DPPatch DPDiaChatModel, DPDiaChatModelFallback;
NSArray<NSString *> *DPInstalledChatModels(void);
NSString *DPSelectedDiaChatModel(NSString *choice, NSArray<NSString *> *models, BOOL fallback);
NSString *DPVerifyDiaModelPage(DPPatch *patch);

static NSTextField *DPModelNote(NSView *overview) {
    NSView *row = DPFindView(overview, ^BOOL(NSView *view) {
        return DPIsKind(view, "DPLinkRowView") && DPHasLabel(view, DPDiaChatModel.title);
    });
    NSTextField *title = (id)DPFindView(row, ^BOOL(NSView *view) {
        return [view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue isEqual:DPDiaChatModel.title];
    });
    NSStackView *column = [title.superview isKindOfClass:NSStackView.class] ? (id)title.superview : nil;
    id note = column.arrangedSubviews.lastObject;
    return note != title && [note isKindOfClass:NSTextField.class] ? note : nil;
}

static NSString *DPModelSummary(void) {
    return DPSelectedDiaChatModel(DPChoice(&DPDiaChatModel), DPInstalledChatModels(), DPDiaChatModelFallback.on) ?: @"Dia Default";
}

static void DPUpdateModelNote(NSView *overview) {
    if (DPDiaChatModel.unavailable) return;
    NSTextField *note = DPModelNote(overview);
    note.stringValue = DPDiaChatModel.on ? DPModelSummary() : @"";
    note.hidden = !DPDiaChatModel.on;
}

static void DPModelOverview_syncWithQuery(NSView *self, SEL _cmd, NSString *query) {
    DPCallOriginal(DPModelOverview_syncWithQuery, self, query);
    DPUpdateModelNote(self);
}

void DPInstallDiaModelOverview(void) {
    DPHook("DPOverviewView", @selector(syncWithQuery:), (IMP)DPModelOverview_syncWithQuery);
}

NSString *DPVerifyDiaModelOverview(DPPatch *patch) {
    Class list = objc_getClass("DPOverviewView");
    if (list && !DPIsHooked(list, @selector(syncWithQuery:), (IMP)DPModelOverview_syncWithQuery)) return @"the tweak list doesn't show the selected model";
    for (NSView *overview in DPFindViews("DPOverviewView")) {
        if (overview.hiddenOrHasHiddenAncestor) continue;
        NSTextField *note = DPModelNote(overview);
        if (!note) continue;
        if (patch->on && (note.hidden || ![note.stringValue isEqual:DPModelSummary()])) return @"the selected model is not shown in the tweak list";
        if (!patch->on && !note.hidden) return @"the model summary is shown while the tweak is off";
    }
    return DPVerifyDiaModelPage(patch);
}
