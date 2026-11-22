#import "ProfileColorPicker.h"

static NSHashTable<NSViewController *> *DPColorPanes;
static char DPRowViewsKey;

NSString *DPProfilePaneSpaceID(NSViewController *pane) {
    return DPNormalizedSpaceID(DPSwiftValue(pane, @"spaceID"));
}

static NSViewController *DPOwningPaneForView(NSView *view) {
    if (!view) return nil;
    for (NSViewController *pane in DPColorPanes.allObjects)
        if (pane.isViewLoaded && [view isDescendantOf:pane.view]) return pane;
    return nil;
}

NSString *DPAnchoredPanelSpaceID(NSWindow *window) {
    NSView *anchor = DPSwiftValue(window, @"anchor");
    NSViewController *pane = DPOwningPaneForView(anchor);
    return pane ? DPProfilePaneSpaceID(pane) : nil;
}

static void DPRemoveColorRow(NSViewController *pane) {
    NSArray<NSView *> *views = DPGet(pane, &DPRowViewsKey);
    for (NSView *view in views) {
        if ([view isKindOfClass:DPProfileColorRow.class]) [(DPProfileColorRow *)view prepareForRemoval];
        [view removeFromSuperview];
    }
    DPSet(pane, &DPRowViewsKey, nil);
}

static void DPMountColorRow(NSViewController *pane) {
    if (!pane || !pane.isViewLoaded) return;
    NSView *group = DPFindView(pane.view, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSettingsFormGroup); });
    NSStackView *rows = (NSStackView *)DPSubview(group, "NSStackView");
    NSTextField *title = (NSTextField *)DPFindView(rows.arrangedSubviews.firstObject, ^BOOL(NSView *v) { return [v isKindOfClass:NSTextField.class]; });
    NSString *spaceID = DPProfilePaneSpaceID(pane);
    if (!rows || !title || !spaceID) return;

    NSArray<NSView *> *existing = DPGet(pane, &DPRowViewsKey);
    if (existing.count == 2 && existing[1].superview == rows) {
        DPProfileColorRow *row = (DPProfileColorRow *)existing[1];
        [row switchToSpaceID:spaceID];
        return;
    }
    if (existing) DPRemoveColorRow(pane);

    NSBox *line = [NSBox new];
    line.boxType = NSBoxSeparator;
    DPProfileColorRow *row = [[DPProfileColorRow alloc] initWithSpaceID:spaceID font:title.font textColor:title.textColor];

    __block NSUInteger insertAt = rows.arrangedSubviews.count;
    [rows.arrangedSubviews enumerateObjectsUsingBlock:^(NSView *sub, NSUInteger idx, BOOL *stop) {
        if (DPFindView(sub, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaThemePicker); })) {
            insertAt = idx + 1;
            *stop = YES;
        }
    }];
    [rows insertArrangedSubview:line atIndex:insertAt];
    [rows insertArrangedSubview:row atIndex:insertAt + 1];
    [NSLayoutConstraint activateConstraints:@[
        [line.widthAnchor constraintEqualToAnchor:rows.widthAnchor],
        [row.widthAnchor constraintEqualToAnchor:rows.widthAnchor],
    ]];
    DPSet(pane, &DPRowViewsKey, @[ line, row ]);
}

void DPSyncProfileColorUI(NSString *spaceID) {
    NSString *key = DPNormalizedSpaceID(spaceID);
    for (NSViewController *pane in DPColorPanes.allObjects) {
        if (key && ![DPProfilePaneSpaceID(pane) isEqualToString:key]) continue;
        NSArray<NSView *> *views = DPGet(pane, &DPRowViewsKey);
        if (views.count == 2 && [views[1] isKindOfClass:DPProfileColorRow.class]) [(DPProfileColorRow *)views[1] syncFromDefaults:YES];
    }
}

void DPApplyProfileColorUI(BOOL on) {
    for (NSViewController *pane in DPColorPanes.allObjects) {
        if (on) DPMountColorRow(pane);
        else DPRemoveColorRow(pane);
    }
}

static void DPColorPane_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPColorPane_viewDidLoad, self);
    [DPColorPanes addObject:self];
    if (DPProfileColorPicker.on) DPMountColorRow(self);
}

static void DPColorPane_viewWillDisappear(NSViewController *self, SEL _cmd) {
    NSArray<NSView *> *views = DPGet(self, &DPRowViewsKey);
    if (views.count == 2 && [views[1] isKindOfClass:DPProfileColorRow.class]) {
        DPProfileColorWell *well = ((DPProfileColorRow *)views[1]).well;
        if (well.isActive) [well deactivate];
    }
    DPCallOriginal(DPColorPane_viewWillDisappear, self);
}

static void DPThemePicker_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPThemePicker_viewDidMoveToWindow, self);
    if (!DPProfileColorPicker.on || !self.window) return;
    NSViewController *pane = DPOwningPaneForView(self);
    if (pane) DPMountColorRow(pane);
}

static void DPThemePicker_themeClicked(NSView *self, SEL _cmd, id sender) {
    BOOL openingDial = [DPSwiftValue(sender, @"isSelected") boolValue] && [DPSwiftValue(sender, @"showsEditIcon") boolValue];
    DPCallOriginal(DPThemePicker_themeClicked, self, sender);
    if (!DPProfileColorPicker.on || openingDial) return;
    NSViewController *pane = DPOwningPaneForView(self);
    NSString *spaceID = pane ? DPProfilePaneSpaceID(pane) : nil;
    if (!spaceID) return;
    NSArray<NSView *> *views = DPGet(pane, &DPRowViewsKey);
    if (views.count == 2 && [views[1] isKindOfClass:DPProfileColorRow.class]) {
        DPProfileColorWell *well = ((DPProfileColorRow *)views[1]).well;
        if (well.isActive) [well deactivate];
    }
    if (!DPSavedProfileHexForSpace(spaceID)) return;
    DPSetProfileHexForSpace(spaceID, nil);
    DPSyncProfileColorUI(spaceID);
    DPRefreshProfileColors();
}

NSString *DPVerifyProfileColorUI(DPPatch *patch) {
    if (!DPIsHooked(objc_getClass(DPDiaThemePicker), @selector(themeClicked:), (IMP)DPThemePicker_themeClicked))
        return @"theme picker hook didn't install";
    for (NSViewController *pane in DPColorPanes.allObjects) {
        if (!pane.isViewLoaded || !pane.view.window.isVisible) continue;
        NSArray<NSView *> *views = DPGet(pane, &DPRowViewsKey);
        BOOL mounted = views.count == 2 && views[1].superview != nil;
        if (mounted != patch->on) return patch->on ? @"custom color row is missing" : @"custom color row stayed mounted";
    }
    return nil;
}

void DPInstallProfileColorUI(void) {
    DPColorPanes = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaProfilePane, @selector(viewDidLoad), (IMP)DPColorPane_viewDidLoad);
    DPHook(DPDiaProfilePane, @selector(viewWillDisappear), (IMP)DPColorPane_viewWillDisappear);
    DPHook(DPDiaThemePicker, @selector(viewDidMoveToWindow), (IMP)DPThemePicker_viewDidMoveToWindow);
    DPHook(DPDiaThemePicker, @selector(themeClicked:), (IMP)DPThemePicker_themeClicked);
}
