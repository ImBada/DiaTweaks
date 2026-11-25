#import "ProfileColorPicker.h"

static NSHashTable<NSViewController *> *DPColorPanes;
static char DPCircleKey;

NSString *DPProfilePaneSpaceID(NSViewController *pane) {
    return DPNormalizedSpaceID(DPSwiftValue(pane, @"spaceID"));
}

static NSViewController *DPOwningPaneForView(NSView *view) {
    if (!view) return nil;
    for (NSViewController *pane in DPColorPanes)
        if (pane.isViewLoaded && [view isDescendantOf:pane.view]) return pane;
    return nil;
}

static DPProfileColorCircle *DPCircleForView(NSView *view) {
    NSViewController *pane = DPOwningPaneForView(view);
    return pane ? DPGet(pane, &DPCircleKey) : nil;
}

NSString *DPAnchoredPanelSpaceID(NSWindow *window) {
    NSView *anchor = DPSwiftValue(window, @"anchor");
    NSViewController *pane = DPOwningPaneForView(anchor);
    return pane ? DPProfilePaneSpaceID(pane) : nil;
}

static NSStackView *DPPickerStack(NSView *picker) {
    return (NSStackView *)DPSubview(picker, "NSStackView");
}

static uint8_t *DPIvarBytes(id object, const char *name, size_t length) {
    Class cls = object ? object_getClass(object) : Nil;
    Ivar ivar = cls ? class_getInstanceVariable(cls, name) : NULL;
    ptrdiff_t offset = ivar ? ivar_getOffset(ivar) : -1;
    if (offset < 0 || (size_t)offset + length > class_getInstanceSize(cls)) return NULL;
    return (uint8_t *)(__bridge void *)object + offset;
}

static uint8_t DPThemeTag(NSView *button) {
    uint8_t *theme = DPIvarBytes(button, "theme", 33);
    return theme ? theme[32] : 9;
}

static void DPSetPresetSelection(NSView *picker, BOOL suppress) {
    uint8_t *name = DPIvarBytes(picker, "selectedThemeName", 1);
    uint8_t selected = suppress || !name ? 9 : *name;
    for (NSView *view in DPPickerStack(picker).arrangedSubviews) {
        if (!DPIsKind(view, DPDiaThemeOption)) continue;
        BOOL *flag = (BOOL *)DPIvarBytes(view, "isSelected", sizeof(BOOL));
        if (flag) *flag = DPThemeTag(view) == selected;
        view.needsDisplay = YES;
    }
}

void DPRefreshPresetRings(NSView *picker) {
    DPSetPresetSelection(picker, DPProfileColorPicker.on && DPCircleForView(picker).suppressesPresets);
}

static void DPRemoveCircle(NSViewController *pane) {
    DPProfileColorCircle *circle = DPGet(pane, &DPCircleKey);
    if (!circle) return;
    [circle prepareForRemoval];
    [circle removeFromSuperview];
    DPSet(pane, &DPCircleKey, nil);
}

static void DPMountCircle(NSViewController *pane) {
    if (!pane || !pane.isViewLoaded) return;
    NSView *picker = DPFindView(pane.view, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaThemePicker); });
    NSStackView *stack = DPPickerStack(picker);
    NSString *spaceID = DPProfilePaneSpaceID(pane);
    if (!stack || !spaceID) return;

    DPProfileColorCircle *circle = DPGet(pane, &DPCircleKey);
    if (circle && circle.superview == stack) {
        [circle switchToSpaceID:spaceID];
        return;
    }
    if (circle) DPRemoveCircle(pane);

    NSNumber *option = DPValueForKey(picker, @"optionDimension");
    CGFloat dimension = [option isKindOfClass:NSNumber.class] && option.doubleValue > 0 ? option.doubleValue : 24;
    circle = [[DPProfileColorCircle alloc] initWithSpaceID:spaceID dimension:dimension];
    circle.picker = picker;
    [stack addArrangedSubview:circle];
    [NSLayoutConstraint activateConstraints:@[
        [circle.widthAnchor constraintEqualToConstant:dimension],
        [circle.heightAnchor constraintEqualToConstant:dimension],
    ]];
    DPSet(pane, &DPCircleKey, circle);
}

void DPSyncProfileColorUI(NSString *spaceID) {
    NSString *key = DPNormalizedSpaceID(spaceID);
    for (NSViewController *pane in DPColorPanes.allObjects) {
        if (key && ![DPProfilePaneSpaceID(pane) isEqualToString:key]) continue;
        [DPGet(pane, &DPCircleKey) syncFromDefaults];
    }
}

void DPApplyProfileColorUI(BOOL on) {
    for (NSViewController *pane in DPColorPanes.allObjects) {
        if (on) DPMountCircle(pane);
        else DPRemoveCircle(pane);
    }
}

static void DPColorPane_viewDidLoad(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPColorPane_viewDidLoad, self);
    [DPColorPanes addObject:self];
    if (DPProfileColorPicker.on) DPMountCircle(self);
}

static void DPColorPane_viewWillDisappear(NSViewController *self, SEL _cmd) {
    [DPGet(self, &DPCircleKey) closePopover];
    DPCallOriginal(DPColorPane_viewWillDisappear, self);
}

static void DPThemePicker_viewDidMoveToWindow(NSView *self, SEL _cmd) {
    DPCallOriginal(DPThemePicker_viewDidMoveToWindow, self);
    if (!DPProfileColorPicker.on || !self.window) return;
    NSViewController *pane = DPOwningPaneForView(self);
    if (pane) DPMountCircle(pane);
}

// Dia keeps its own preset selected in the model; hiding the ring here leaves that model intact so it returns when the custom color goes.
static void DPThemeOption_updateLayer(NSView *self, SEL _cmd) {
    if (DPProfileColorPicker.on && DPCircleForView(self).suppressesPresets) {
        BOOL *selected = (BOOL *)DPIvarBytes(self, "isSelected", sizeof(BOOL));
        if (selected) *selected = NO;
    }
    DPCallOriginal(DPThemeOption_updateLayer, self);
}

static void DPThemePicker_themeClicked(NSView *self, SEL _cmd, id sender) {
    DPProfileColorCircle *circle = DPProfileColorPicker.on ? DPCircleForView(self) : nil;
    if (circle.suppressesPresets) {
        [circle closePopover];
        DPSetProfileHexForSpace(circle.spaceID, nil);
        [circle syncFromDefaults];
        DPSetPresetSelection(self, YES);
        DPRefreshProfileColors();
    }
    DPCallOriginal(DPThemePicker_themeClicked, self, sender);
    DPRefreshPresetRings(self);
}

NSString *DPVerifyProfileColorUI(DPPatch *patch) {
    if (!DPIsHooked(objc_getClass(DPDiaThemePicker), @selector(themeClicked:), (IMP)DPThemePicker_themeClicked))
        return @"theme picker hook didn't install";
    for (NSViewController *pane in DPColorPanes.allObjects) {
        if (!pane.isViewLoaded || !pane.view.window.isVisible) continue;
        DPProfileColorCircle *circle = DPGet(pane, &DPCircleKey);
        BOOL mounted = circle != nil && circle.superview != nil;
        if (mounted != patch->on) return patch->on ? @"custom color circle is missing" : @"custom color circle stayed mounted";
        if (!patch->on && circle.popoverOpen) return @"custom color popover stayed open";
    }
    return nil;
}

void DPInstallProfileColorUI(void) {
    DPColorPanes = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaProfilePane, @selector(viewDidLoad), (IMP)DPColorPane_viewDidLoad);
    DPHook(DPDiaProfilePane, @selector(viewWillDisappear), (IMP)DPColorPane_viewWillDisappear);
    DPHook(DPDiaThemePicker, @selector(viewDidMoveToWindow), (IMP)DPThemePicker_viewDidMoveToWindow);
    DPHook(DPDiaThemePicker, @selector(themeClicked:), (IMP)DPThemePicker_themeClicked);
    if (objc_getClass(DPDiaThemeOption)) DPHook(DPDiaThemeOption, @selector(updateLayer), (IMP)DPThemeOption_updateLayer);
}
