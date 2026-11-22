#import "PullRequestRepo.h"
#import "Patches/CompactTabRows/CompactTabRows.h"
#import <objc/message.h>

static const CGFloat DPExtra = 14;
static NSMutableSet<NSString *> *DPTallTabs;
static char DPStatusKey, DPStatusTabKey, DPLineKey, DPAdjustedKey, DPEditsKey;

@implementation DPPRStatusLine
@end

static void DPCollectLists(NSView *view, Class cls, NSMutableArray<NSView *> *out) {
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (NSView *sub in view.subviews) DPCollectLists(sub, cls, out);
}

static void DPInvalidateRows(void) {
    static BOOL scheduled;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        Class cls = objc_getClass(DPDiaTabListCollection);
        if (!cls) return;
        NSMutableArray<NSView *> *lists = [NSMutableArray new];
        for (NSWindow *window in NSApp.windows) DPCollectLists(window.contentView, cls, lists);
        for (NSView *view in lists) [((NSCollectionView *)view).collectionViewLayout invalidateLayout];
    });
}

void DPSetPRStatus(NSView *subtitle, NSString *tab, NSString *status) {
    NSView *content = DPEnclosingView(subtitle.superview, DPDiaTabContentView);
    NSString *tabID = tab.length ? tab : DPPRTabIDOf(content);
    DPSet(content, &DPStatusKey, status);
    DPSet(content, &DPStatusTabKey, status && tabID.length ? tabID : nil);
    content.needsLayout = YES;
    if (!tabID.length || [DPTallTabs containsObject:tabID] == (status != nil)) return;
    if (status) [DPTallTabs addObject:tabID];
    else [DPTallTabs removeObject:tabID];
    DPInvalidateRows();
}

void DPResetPRRows(void) {
    [DPTallTabs removeAllObjects];
    Class contentCls = objc_getClass(DPDiaTabContentView);
    if (contentCls) {
        NSMutableArray<NSView *> *contents = [NSMutableArray new];
        for (NSWindow *window in NSApp.windows) DPCollectLists(window.contentView, contentCls, contents);
        for (NSView *content in contents) {
            NSTextField *line = DPGet(content, &DPLineKey);
            if (!line && !DPGet(content, &DPStatusKey) && !DPGet(content, &DPStatusTabKey)) continue;
            [line removeFromSuperview];
            DPSet(content, &DPLineKey, nil);
            DPSet(content, &DPStatusKey, nil);
            DPSet(content, &DPStatusTabKey, nil);
            content.needsLayout = YES;
        }
    }
    DPInvalidateRows();
}

static NSString *DPTabAt(id source, NSIndexPath *path) {
    NSString *item = [((id (*)(id, SEL, id))objc_msgSend)(source, @selector(itemIdentifierForIndexPath:), path) description];
    NSRange open = [item rangeOfString:@".tab("];
    return open.location == NSNotFound || item.length < NSMaxRange(open) + 36 ? nil : [item substringWithRange:NSMakeRange(NSMaxRange(open), 36)];
}

static id DPObjectIvar(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static void DPLayout_prepareLayout(NSCollectionViewLayout *self, SEL _cmd) {
    DPCallOriginal(DPLayout_prepareLayout, self);
    void *height = DPIvar(self, "contentHeight");
    NSArray *(*elements)(id, SEL, NSRect) = (void *)DPDiaIMP(objc_getClass(DPDiaTabListLayout), @selector(layoutAttributesForElementsInRect:));
    NSArray *prev = DPGet(self, &DPAdjustedKey);
    if (prev && height) {
        DPSet(self, &DPAdjustedKey, nil);
        NSArray<NSArray *> *written = prev[1];
        BOOL reused = written.count > 0;
        for (NSArray *entry in written) {
            NSCollectionViewLayoutAttributes *a = entry[0];
            if (!NSEqualRects(a.frame, [entry[1] rectValue])) { reused = NO; break; }
        }
        if (reused) {
            for (NSArray *entry in written) {
                NSCollectionViewLayoutAttributes *a = entry[0];
                NSRect frame = a.frame;
                frame.origin.y -= [entry[2] doubleValue];
                frame.size.height -= [entry[3] doubleValue];
                a.frame = frame;
            }
            *(double *)height -= [prev[0] doubleValue];
        }
    }
    if (!DPPullRequestRepo.on || !DPTallTabs.count) {
        if (DPGet(self, &DPEditsKey)) DPSet(self, &DPEditsKey, nil);
        return;
    }
    id diffable = self.collectionView.dataSource;
    id source = DPObjectIvar(diffable, "_impl");
    if (![source respondsToSelector:@selector(itemIdentifierForIndexPath:)] || !height) return;
    // Use Dia's IMP so we mutate real attributes, not Collapse Pinned Tabs' copies.
    NSArray<NSCollectionViewLayoutAttributes *> *all = elements(self, @selector(layoutAttributesForElementsInRect:), NSMakeRect(-1e5, -1e5, 2e5, 1e7));
    NSMutableArray<NSCollectionViewLayoutAttributes *> *tall = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all)
        if (a.representedElementCategory == NSCollectionElementCategoryItem && [DPTallTabs containsObject:DPTabAt(source, a.indexPath)]) [tall addObject:a];
    if (!tall.count) {
        DPSet(self, &DPEditsKey, nil);
        return;
    }
    NSMutableArray<NSValue *> *rows = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in tall) [rows addObject:[NSValue valueWithRect:a.frame]];
    NSMutableArray *edits = [NSMutableArray new], *written = [NSMutableArray new];
    for (NSCollectionViewLayoutAttributes *a in all) {
        NSRect frame = a.frame;
        for (NSValue *value in rows) {
            NSRect row = value.rectValue;
            if (NSMinY(a.frame) >= NSMaxY(row) - 0.5) frame.origin.y += DPExtra;
            else if (NSMinY(a.frame) <= NSMinY(row) + 0.5 && NSMaxY(a.frame) >= NSMaxY(row) - 0.5) frame.size.height += DPExtra;
        }
        CGFloat dy = frame.origin.y - a.frame.origin.y, dh = frame.size.height - a.frame.size.height;
        if (a.representedElementCategory == NSCollectionElementCategoryItem)
            [edits addObject:@[a, @(dy), @(dh)]];
        if (dy != 0 || dh != 0) [written addObject:@[a, [NSValue valueWithRect:frame], @(dy), @(dh)]];
        a.frame = frame;
    }
    DPSet(self, &DPEditsKey, edits);
    double added = DPExtra * rows.count;
    *(double *)height += added;
    DPSet(self, &DPAdjustedKey, @[@(added), written]);
}

static NSArray<NSArray<NSValue *> *> *DPMoves(NSCollectionViewLayout *layout) {
    NSMutableArray *moves = [NSMutableArray new];
    for (NSArray *edit in DPGet(layout, &DPEditsKey)) {
        NSCollectionViewLayoutAttributes *shown = [layout layoutAttributesForItemAtIndexPath:[edit[0] indexPath]];
        if (!shown || shown.hidden || shown.alpha < 1) continue;
        NSRect now = shown.frame, then = now;
        then.origin.y -= [edit[1] doubleValue];
        then.size.height -= [edit[2] doubleValue];
        [moves addObject:@[ [NSValue valueWithRect:now], [NSValue valueWithRect:then] ]];
    }
    return moves;
}

static id<NSDraggingInfo> DPDiaDrag(NSView *tabList, id<NSDraggingInfo> info) {
    if (!DPPullRequestRepo.on || !DPTallTabs.count) return info;
    NSCollectionView *list = (NSCollectionView *)DPFindView(tabList, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaTabListCollection); });
    NSArray *moves = DPMoves(list.collectionViewLayout);
    if (!moves.count) return info;
    NSPoint point = [list convertPoint:info.draggingLocation fromView:nil];
    point.y = DPTabListDiaY(moves, point.y);
    return DPDraggingInfoAt(info, [list convertPoint:point toView:nil]);
}

static NSDragOperation DPTabList_entered(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    NSDragOperation operation = DPCallOriginal(DPTabList_entered, self, DPDiaDrag(self, info));
    if (DPPullRequestRepo.on) DPPlaceDraggedTab();
    return operation;
}
static NSDragOperation DPTabList_updated(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    NSDragOperation operation = DPCallOriginal(DPTabList_updated, self, DPDiaDrag(self, info));
    if (DPPullRequestRepo.on) DPPlaceDraggedTab();
    return operation;
}
static BOOL DPTabList_prepare(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    BOOL ok = DPCallOriginal(DPTabList_prepare, self, DPDiaDrag(self, info));
    DPClearDraggedTab();
    return ok;
}
static BOOL DPTabList_perform(NSView *self, SEL _cmd, id<NSDraggingInfo> info) {
    BOOL ok = DPCallOriginal(DPTabList_perform, self, DPDiaDrag(self, info));
    DPClearDraggedTab();
    return ok;
}

static NSView *DPPart(NSView *content, const char *name) {
    id part = DPObjectIvar(content, name);
    return [part isKindOfClass:NSView.class] ? part : nil;
}

static void DPContent_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPContent_layout, self);
    NSString *status = DPPullRequestRepo.on ? DPGet(self, &DPStatusKey) : nil;
    NSTextField *line = DPGet(self, &DPLineKey);
    if (!status && !line) return;
    if (!DPPullRequestRepo.on) {
        [line removeFromSuperview];
        DPSet(self, &DPLineKey, nil);
        DPSet(self, &DPStatusKey, nil);
        DPSet(self, &DPStatusTabKey, nil);
        return;
    }
    NSView *title = DPPart(self, "$__lazy_storage_$_titleView"), *subtitle = DPPart(self, "subtitleView"), *icon = DPPart(self, "subtitleIconView");
    NSString *statusTab = DPGet(self, &DPStatusTabKey), *currentTab = statusTab.length ? DPPRTabIDOf(self) : nil;
    if (subtitle.hidden || (statusTab.length && currentTab.length && ![currentTab isEqualToString:statusTab])) {
        DPSet(self, &DPStatusKey, nil);
        DPSet(self, &DPStatusTabKey, nil);
        line.hidden = YES;
        return;
    }
    NSTextField *source = (NSTextField *)DPSubview(subtitle, DPDiaFeatheredLabel);
    BOOL tall = status && title && source && NSHeight(self.bounds) >= DPCompactRowHeight() + DPExtra - 1;
    line.hidden = !tall;
    if (!tall) return;
    if (!line) DPSet(self, &DPLineKey, line = [DPPRStatusLine labelWithString:@""]);
    if (line.superview != self) [self addSubview:line];
    if (![line.font isEqual:source.font]) line.font = source.font;
    if (![line.textColor isEqual:source.textColor]) line.textColor = source.textColor;
    line.lineBreakMode = NSLineBreakByTruncatingTail;
    if (![line.stringValue isEqualToString:status]) line.stringValue = status;
    CGFloat lineHeight = NSHeight(subtitle.frame), bottom = round((NSHeight(self.bounds) - NSHeight(title.frame) - 2 * lineHeight) / 2);
    CGFloat x = NSMinX(subtitle.frame), width = NSWidth(self.bounds) - x - 8;
    CGFloat text = ceil([status sizeWithAttributes:@{NSFontAttributeName: line.font ?: [NSFont systemFontOfSize:11]}].width);
    NSRect lineFrame = NSMakeRect(x, bottom, width, lineHeight);
    if (!NSEqualRects(line.frame, lineFrame)) line.frame = lineFrame;
    NSPoint subOrigin = NSMakePoint(x, bottom + lineHeight), titleOrigin = NSMakePoint(NSMinX(title.frame), bottom + 2 * lineHeight);
    if (!NSEqualPoints(subtitle.frame.origin, subOrigin)) [subtitle setFrameOrigin:subOrigin];
    if (!NSEqualPoints(title.frame.origin, titleOrigin)) [title setFrameOrigin:titleOrigin];
    if (icon && !icon.hidden) {
        NSPoint iconOrigin = NSMakePoint(x + MIN(text, width) + 5, bottom + (lineHeight - NSHeight(icon.frame)) / 2);
        if (!NSEqualPoints(icon.frame.origin, iconOrigin)) [icon setFrameOrigin:iconOrigin];
    }
}

void DPInstallPRRows(void) {
    DPTallTabs = [NSMutableSet new];
    DPHook(DPDiaTabListLayout, @selector(prepareLayout), (IMP)DPLayout_prepareLayout);
    DPHook(DPDiaTabContentView, @selector(layout), (IMP)DPContent_layout);
    DPHook(DPDiaTabList, @selector(draggingEntered:), (IMP)DPTabList_entered);
    DPHook(DPDiaTabList, @selector(draggingUpdated:), (IMP)DPTabList_updated);
    DPHook(DPDiaTabList, @selector(prepareForDragOperation:), (IMP)DPTabList_prepare);
    DPHook(DPDiaTabList, @selector(performDragOperation:), (IMP)DPTabList_perform);
}
