#import "StdPatch/StdPatch.h"
#import "StdPatch/Hide.h"
#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#include <mach-o/getsect.h>
#include <notify.h>

extern const struct mach_header_64 __dso_handle;

static const CFTimeInterval DPAnimationDuration = 0.25;

DPPatch *const *DPPatches;
NSUInteger DPPatchCount;
static NSMutableDictionary<NSString *, NSString *> *DPAppliedChoices;

NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";

DPPatch *DPPatchNamed(NSString *key) {
    if (!key) return NULL;
    for (NSUInteger i = 0; i < DPPatchCount; i++) if ([DPPatches[i]->key isEqualToString:key]) return DPPatches[i];
    return NULL;
}

DPPatch *DPRequired(DPPatch *patch) {
    return DPPatchNamed(patch->requires);
}

// The low byte of `order` is the tweak's place in the source, which DPReadPatches keeps as its tie-break.
int DPDeclaredOrder(DPPatch *patch) { return patch->order & 0xFF; }

static NSTimer *DPEaseTimer;

static void DPAnimate(void) {
    static CFTimeInterval start;
    static CGFloat *from;
    static NSUInteger fromCount;
    if (fromCount < DPPatchCount) {
        from = realloc(from, DPPatchCount * sizeof *from);
        fromCount = DPPatchCount;
    }
    start = CACurrentMediaTime();
    for (NSUInteger i = 0; i < DPPatchCount; i++) from[i] = DPPatches[i]->progress;
    if (DPEaseTimer) return;
    DPEaseTimer = [NSTimer timerWithTimeInterval:1.0 / 120 repeats:YES block:^(NSTimer *t) {
        CGFloat elapsed = CACurrentMediaTime() - start, omega = 22;
        BOOL done = elapsed >= DPAnimationDuration * 2;
        CGFloat eased = done ? 1 : 1 - (1 + omega * elapsed) * exp(-omega * elapsed);
        for (NSUInteger i = 0; i < DPPatchCount; i++) DPPatches[i]->progress = from[i] + (DPPatches[i]->on - from[i]) * eased;
        // Tweaks share relayouts, so run each one once, and only while one of the tweaks using it is still easing.
        for (NSUInteger i = 0; i < DPPatchCount; i++) {
            void (*relayout)(void) = DPPatches[i]->relayout;
            if (!relayout) continue;
            BOOL moving = NO, ran = NO;
            for (NSUInteger j = 0; j < DPPatchCount; j++) {
                if (DPPatches[j]->relayout != relayout) continue;
                if (j < i) ran = YES;
                if (from[j] != DPPatches[j]->on || DPPatches[j]->progress != DPPatches[j]->on) moving = YES;
            }
            if (moving && !ran) relayout();
        }
        if (done) {
            [t invalidate];
            DPEaseTimer = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:DPEaseTimer forMode:NSRunLoopCommonModes];
}

BOOL DPAnimating(void) {
    if (DPEaseTimer) return YES;
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPPatches[i]->animating && DPPatches[i]->animating()) return YES;
    return NO;
}

BOOL DPTesting;

static void DPEnsureReady(DPPatch *patch) {
    NSString *problem = patch->ready(patch);
    for (int tries = 1; problem && tries < 3; tries++) {
        if (patch->apply) patch->apply(patch);
        problem = patch->ready(patch);
    }
    if (!problem || DPTesting) return;
    NSLog(@"DiaPatches: %@ couldn't turn on: %@", patch->title, problem);
    patch->on = NO;
    [DPSettingsDefaults() setBool:NO forKey:patch->key];
    if (patch->apply) patch->apply(patch);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
        NSAlert *alert = [NSAlert new];
        alert.messageText = [NSString stringWithFormat:@"Couldn’t turn on %@", patch->title];
        alert.informativeText = problem;
        [alert runModal];
    });
}

void DPSetPatch(DPPatch *patch, BOOL on, BOOL save) {
    if (save) [DPSettingsDefaults() setBool:on forKey:patch->key];
    if (DPPaused) on = NO;
    if (patch->on == on) return;
    patch->on = on;
    if (DPSafeMode || DPPausedAtLaunch) return;
    if (patch->apply) patch->apply(patch);
    else if (patch->relayout) DPAnimate();
    else patch->progress = on;
    if (on && patch->ready) DPEnsureReady(patch);
}

BOOL DPEffectiveOn(DPPatch *patch) { return !DPPaused && DPSavedOn(patch); }

NSString *DPAppSupport(NSString *path) {
    const char *home = getenv("DIAPATCH_HOME");
    if (!home || !*home) {
        static NSString *system;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ system = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject; });
        return [system stringByAppendingPathComponent:path];
    }
    if ([path isEqualToString:@"DiaPatches"]) return @(home);
    return [@(home) stringByAppendingPathComponent:[path hasPrefix:@"DiaPatches/"] ? [path substringFromIndex:11] : path];
}

static NSMapTable<NSValue *, NSString *> *DPLocalIDs, *DPLocalProblems;

void DPNoteLocalPatch(DPPatch *patch, NSString *identifier, NSString *problem) {
    if (!patch) return;
    if (!DPLocalIDs) {
        DPLocalIDs = [NSMapTable strongToStrongObjectsMapTable];
        DPLocalProblems = [NSMapTable strongToStrongObjectsMapTable];
    }
    NSValue *key = [NSValue valueWithPointer:patch];
    if (identifier) [DPLocalIDs setObject:identifier forKey:key];
    if (problem && ![DPLocalProblems objectForKey:key]) [DPLocalProblems setObject:problem forKey:key];
}

NSString *DPLocalIdentifier(DPPatch *patch) { return patch ? [DPLocalIDs objectForKey:[NSValue valueWithPointer:patch]] : nil; }

BOOL DPIsLocalPatch(DPPatch *patch) { return DPLocalIdentifier(patch) != nil; }

NSString *DPLocalProblem(DPPatch *patch) { return patch ? [DPLocalProblems objectForKey:[NSValue valueWithPointer:patch]] : nil; }

BOOL DPSavedOn(DPPatch *patch) {
    id value = [DPSettingsDefaults() objectForKey:patch->key];
    return !patch->unavailable && (value ? [value boolValue] : patch->defaultOn);
}

NSString *DPChoice(DPPatch *patch) {
    id value = patch && patch->choice ? [DPSettingsDefaults() objectForKey:patch->choice] : nil;
    return [value isKindOfClass:NSString.class] ? value : patch ? patch->defaultChoice : nil;
}

static void DPRecordChoice(DPPatch *patch) {
    if (!patch->choice) return;
    if (!DPAppliedChoices) DPAppliedChoices = [NSMutableDictionary new];
    NSString *choice = DPChoice(patch);
    if (choice) DPAppliedChoices[patch->key] = choice;
    else [DPAppliedChoices removeObjectForKey:patch->key];
}

void DPSetChoice(DPPatch *patch, NSString *value) {
    if (!patch || !patch->choice) return;
    [DPSettingsDefaults() setObject:value forKey:patch->choice];
    if (!DPSafeMode && !DPPausedAtLaunch && patch->on && patch->apply) {
        DPRecordChoice(patch);
        patch->apply(patch);
    }
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

static NSMapTable<NSValue *, NSNumber *> *DPDeclaredOrders;

static int DPCompareOrder(const void *a, const void *b) {
    return (*(DPPatch *const *)a)->order - (*(DPPatch *const *)b)->order;
}

static void DPReadPatches(BOOL includeLocal) {
    unsigned long size = 0;
    DPPatch **entries = (DPPatch **)getsectiondata(&__dso_handle, "__DATA", "__dppatches", &size);
    NSUInteger official = entries && size ? size / sizeof *entries : 0;
    NSUInteger local = includeLocal ? DPLocalLoad() : 0;
    NSUInteger total = official + local;
    if (!total) return;
    DPPatch **sorted = calloc(total, sizeof *sorted);
    if (official) memcpy(sorted, entries, official * sizeof *sorted);
    if (local) memcpy(sorted + official, DPLocalPatches(), local * sizeof *sorted);
    free((void *)DPPatches);
    DPPatches = sorted;
    DPPatchCount = total;
    if (local) DPLocalRepairLinks();
    // The section pass below overwrites `order`, so a reload first restores what each patch declared.
    if (!DPDeclaredOrders) DPDeclaredOrders = [NSMapTable strongToStrongObjectsMapTable];
    for (NSUInteger i = 0; i < total; i++) {
        NSValue *key = [NSValue valueWithPointer:sorted[i]];
        NSNumber *declared = [DPDeclaredOrders objectForKey:key];
        if (declared) sorted[i]->order = declared.intValue;
        else [DPDeclaredOrders setObject:@(sorted[i]->order) forKey:key];
    }
    qsort(sorted, total, sizeof *sorted, DPCompareOrder);
    NSMutableArray<NSString *> *sections = [NSMutableArray new];
    for (NSUInteger i = 0; i < total; i++) {
        DPPatch *patch = sorted[i], *root = patch;
        // An option's own section names a card on its tweak's page, so only the tweak at the top of the chain has one.
        for (int hops = 0; DPRequired(root) && hops < 32; hops++) root = DPRequired(root);
        NSString *section = root->section ?: @"Other";
        NSUInteger sectionIndex = [sections indexOfObject:section];
        if (sectionIndex == NSNotFound) {
            sectionIndex = sections.count;
            [sections addObject:section];
        }
        patch->order = (int)(sectionIndex << 24 | [patch->title hasPrefix:@"Hide "] << 16 | patch->title.length << 8 | i);
    }
    qsort(sorted, total, sizeof *sorted, DPCompareOrder);
}

void DPLoadPatches(void) {
    DPReadPatches(YES);

    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        for (const char *const *name = DPPatches[i]->classes; name && *name; name++) {
            if (!objc_getClass(*name)) {
                DPPatches[i]->unavailable = YES;
                break;
            }
        }
    }
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        for (DPPatch *required = DPRequired(patch); required; required = DPRequired(required)) {
            if (required->unavailable) {
                patch->unavailable = YES;
                break;
            }
        }
        patch->on = DPEffectiveOn(patch);
        patch->progress = patch->on;
        DPRecordChoice(patch);
        if (!patch->hides) continue;
        patch->apply = patch->apply ?: DPApplyHides;
        patch->verify = patch->verify ?: DPVerifyHides;
    }
}

void DPApplySavedSettings(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DPSettingsDomain());
    DPPaused = DPPauseSaved();
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        BOOL wasOn = patch->on;
        DPSetPatch(patch, DPEffectiveOn(patch), NO);
        if (patch->choice && patch->on && patch->apply && !DPSafeMode && !DPPausedAtLaunch) {
            NSString *choice = DPChoice(patch), *applied = DPAppliedChoices[patch->key];
            BOOL changed = (choice != applied) && ![choice isEqualToString:applied];
            DPRecordChoice(patch);
            if (wasOn && changed) patch->apply(patch);
        }
    }
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

void DPWatchSavedSettings(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int token;
        notify_register_dispatch([DPSettingsDomain() stringByAppendingString:@".changed"].UTF8String, &token, dispatch_get_main_queue(),
                                 ^(int _) { DPApplySavedSettings(); });
    });
}

// Hooks install in Settings order (section, non-"Hide" first, then title length): a later hook runs first, and the sidebar drag tweaks rely on it.
void DPInstallPatches(void) {
    // Window Material copies the corner radius Window Corners sets, so it has to hook the floating sidebar after it.
    for (int late = 0; late < 2; late++)
        for (NSUInteger i = 0; i < DPPatchCount; i++)
            if (!DPPatches[i]->unavailable && DPPatches[i]->install && DPPatches[i]->installLate == late) DPPatches[i]->install();
    DPOnLaunch(^{
        for (NSUInteger i = 0; i < DPPatchCount; i++) if (DPPatches[i]->on && DPPatches[i]->ready) DPEnsureReady(DPPatches[i]);
    });
    DPInstallHides();
}

NSNumber *DPCleanNumber(double value) {
    return [NSDecimalNumber decimalNumberWithString:[NSString stringWithFormat:@"%.10g", value]];
}

NSArray<NSString *> *DPChoiceValues(DPPatch *patch) {
    NSMutableArray<NSString *> *values = [NSMutableArray new];
    for (NSMenuItem *item in patch->choices ? patch->choices().itemArray : @[])
        if ([item.representedObject isKindOfClass:NSString.class]) [values addObject:item.representedObject];
    return values;
}

static NSArray<NSDictionary *> *DPSettingEntries(DPPatch *patch) {
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
    for (const DPSetting *setting = patch->settings; setting && setting->kind; setting++) {
        NSMutableDictionary *entry = [@{@"key": setting->key, @"min": NSNull.null, @"max": NSNull.null} mutableCopy];
        if (setting->kind == DPSettingBool) {
            entry[@"type"] = @"bool";
            entry[@"default"] = @(setting->defaultBool);
        } else if (setting->kind == DPSettingNumber) {
            entry[@"type"] = @"number";
            entry[@"default"] = DPCleanNumber(setting->defaultNumber);
            entry[@"min"] = DPCleanNumber(setting->min);
            entry[@"max"] = DPCleanNumber(setting->max);
        } else {
            entry[@"type"] = @"string";
            entry[@"default"] = setting->defaultString ?: @"";
        }
        [entries addObject:entry];
    }
    return entries;
}

static id DPChoiceEntry(DPPatch *patch) {
    if (!patch->choice) return NSNull.null;
    return @{@"key": patch->choice, @"default": patch->defaultChoice ?: NSNull.null, @"values": DPChoiceValues(patch)};
}

static id DPShortcutEntry(DPPatch *patch) {
    if (!patch->shortcut) return NSNull.null;
    return @{@"key": patch->shortcut, @"default": (patch->defaultShortcut ? patch->defaultShortcut() : nil) ?: NSNull.null};
}

BOOL DPWriteManifest(NSString *path) {
    // Reading without local tweaks keeps a developer's private ones out of the release manifest; it replaces DPPatches, so the live table and order are restored after.
    DPPatch *const *saved = DPPatches;
    NSUInteger savedCount = DPPatchCount;
    int *savedOrders = savedCount ? malloc(savedCount * sizeof *savedOrders) : NULL;
    for (NSUInteger i = 0; i < savedCount; i++) savedOrders[i] = saved[i]->order;
    DPPatches = NULL;
    DPPatchCount = 0;
    DPReadPatches(NO);
    NSMutableArray<NSDictionary *> *patches = [NSMutableArray arrayWithCapacity:DPPatchCount];
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i], *required = DPRequired(patch), *disabler = DPPatchNamed(patch->disabledBy), *cover = DPPatchNamed(patch->coveredBy);
        [patches addObject:@{
            @"key": patch->key,
            @"title": patch->title,
            @"detail": patch->detail,
            @"defaultOn": @(patch->defaultOn),
            @"experimental": @(patch->experimental),
            @"requires": required ? required->key : NSNull.null,
            @"disabledBy": disabler ? disabler->key : NSNull.null,
            @"coveredBy": cover ? cover->key : NSNull.null,
            @"relaunch": @(patch->relaunch),
            @"section": patch->section ?: NSNull.null,
            @"group": patch->group ?: NSNull.null,
            @"tint": patch->tint ?: NSNull.null,
            @"symbol": patch->symbol ?: NSNull.null,
            @"choice": DPChoiceEntry(patch),
            @"shortcut": DPShortcutEntry(patch),
            @"settings": DPSettingEntries(patch),
        }];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"patches": patches}
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    BOOL wrote = [json writeToFile:path atomically:YES];
    free((void *)DPPatches);
    DPPatches = saved;
    DPPatchCount = savedCount;
    for (NSUInteger i = 0; i < savedCount; i++) saved[i]->order = savedOrders[i];
    free(savedOrders);
    return wrote;
}
