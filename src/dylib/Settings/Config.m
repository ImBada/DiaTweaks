#import "Settings.h"

typedef enum { DPKeyChoice, DPKeyShortcut, DPKeySetting } DPKeyType;

@interface DPPortableKey : NSObject
@property (nonatomic) DPPatch *patch;
@property (nonatomic) DPKeyType type;
@property (nonatomic) const DPSetting *setting;
@end

@implementation DPPortableKey
@end

@interface DPConfigImport ()
@property (nonatomic) NSUInteger appliedCount, resetCount;
@property (nonatomic) NSArray<NSString *> *unknownKeys, *warnings, *relaunchTitles;
@end

@implementation DPConfigImport
@end

@interface DPConfigPreview ()
@property (nonatomic) NSUInteger changes, resets;
@property (nonatomic) NSArray<NSString *> *unknownKeys, *warnings;
@property (nonatomic) BOOL setsLaunchFlags;
@end

@implementation DPConfigPreview
- (BOOL)isEmpty { return !_changes && !_resets; }
@end

@interface DPConfigChanges : NSObject
@property (nonatomic) NSMutableDictionary<NSString *, id> *writes;
@property (nonatomic) NSMutableArray<NSString *> *unknownKeys, *warnings;
@property (nonatomic) BOOL setsLaunchFlags;
@end

@implementation DPConfigChanges
@end

static const NSUInteger DPConfigMaxBytes = 1 << 20;
static const NSEventModifierFlags DPShortcutFlags = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagCommand;
static NSString *const DPLaunchFlagsArgs = @"launchFlagsArgs";

static BOOL DPIsPortable(DPPatch *patch) { return !DPIsLocalPatch(patch) && ![patch->key isEqualToString:@"localTweaks"]; }

// A switch saved as something odd still has to read as off or on, not raise.
static BOOL DPFlagValue(id value, BOOL fallback) {
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

// Mirrors DPFormatLaunchFlagsArray in LaunchFlags/Parse.m, which this file can't link against.
static NSString *DPFlagsText(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if (![value isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:NSString.class] || ![item length]) continue;
        BOOL quote = [item hasPrefix:@"#"] || [item rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound
            || [item containsString:@"\""] || [item containsString:@"'"] || [item containsString:@"\\"];
        if (!quote) {
            [lines addObject:item];
            continue;
        }
        NSString *escaped = [[item stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
            stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        [lines addObject:[NSString stringWithFormat:@"\"%@\"", escaped]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

// Comment-only text sets nothing, so it needs no trust warning.
static BOOL DPMentionsFlags(NSString *text) {
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length && ![trimmed hasPrefix:@"#"]) return YES;
    }
    return NO;
}

static NSDictionary<NSString *, DPPortableKey *> *DPPortableKeys(void) {
    NSMutableDictionary<NSString *, DPPortableKey *> *keys = [NSMutableDictionary new];
    void (^add)(NSString *, DPPatch *, DPKeyType, const DPSetting *) = ^(NSString *key, DPPatch *patch, DPKeyType type, const DPSetting *setting) {
        if (!key) return;
        DPPortableKey *entry = [DPPortableKey new];
        entry.patch = patch;
        entry.type = type;
        entry.setting = setting;
        keys[key] = entry;
    };
    for (NSUInteger i = 0; i < DPPatchCount; i++) {
        DPPatch *patch = DPPatches[i];
        if (!DPIsPortable(patch)) continue;
        add(patch->choice, patch, DPKeyChoice, NULL);
        add(patch->shortcut, patch, DPKeyShortcut, NULL);
        for (const DPSetting *setting = patch->settings; setting && setting->kind; setting++) add(setting->key, patch, DPKeySetting, setting);
    }
    return keys;
}

static NSDictionary<NSString *, NSValue *> *DPPortablePatches(void) {
    NSMutableDictionary<NSString *, NSValue *> *patches = [NSMutableDictionary new];
    for (NSUInteger i = 0; i < DPPatchCount; i++)
        if (DPIsPortable(DPPatches[i])) patches[DPPatches[i]->key] = [NSValue valueWithPointer:DPPatches[i]];
    return patches;
}

static BOOL DPStoredOn(DPPatch *patch) {
    id value = [DPSettingsDefaults() objectForKey:patch->key];
    return DPFlagValue(value, patch->defaultOn);
}

static BOOL DPIsBool(id value) { return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID(); }

static BOOL DPIsNumber(id value) { return [value isKindOfClass:NSNumber.class] && !DPIsBool(value); }

static BOOL DPIsInteger(id value, long long low, long long high) {
    return DPIsNumber(value) && !CFNumberIsFloatType((__bridge CFNumberRef)value) && [value longLongValue] >= low && [value longLongValue] <= high;
}

static BOOL DPValidShortcut(NSDictionary *shortcut) {
    if (!shortcut.count) return YES;
    NSString *key = shortcut[@"key"];
    id modifiers = shortcut[@"modifiers"];
    BOOL named = [key isKindOfClass:NSString.class] && key.length && [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
    BOOL function = named && [key rangeOfString:@"^F([1-9]|1[0-2])$" options:NSRegularExpressionSearch].location != NSNotFound;
    if (shortcut.count != 3 || !named || !DPIsInteger(shortcut[@"keyCode"], 0, 65535) || !DPIsInteger(modifiers, 0, DPShortcutFlags)) return NO;
    NSEventModifierFlags flags = [modifiers unsignedIntegerValue];
    return !(flags & ~DPShortcutFlags) && (function || (flags & ~NSEventModifierFlagShift));
}

static id DPCheckedSetting(const DPSetting *setting, id value, NSMutableArray<NSString *> *warnings, NSString **problem) {
    if (setting->kind == DPSettingBool) {
        if (DPIsBool(value)) return value;
        *problem = @"must be true or false";
        return nil;
    }
    if (setting->kind == DPSettingNumber) {
        if (!DPIsNumber(value) || !isfinite([value doubleValue])) {
            *problem = @"must be a number";
            return nil;
        }
        double number = [value doubleValue], clamped = MIN(MAX(number, setting->min), setting->max);
        if (clamped == number) return value;
        [warnings addObject:[NSString stringWithFormat:@"%@ was %g, outside %g to %g, so it became %g.", setting->key, number, setting->min, setting->max, clamped]];
        return @(clamped);
    }
    *problem = [value isKindOfClass:NSString.class] ? setting->problem ? setting->problem(value) : nil : @"must be text";
    return *problem ? nil : value;
}

static id DPCheckedValue(DPPortableKey *entry, id value, NSMutableArray<NSString *> *warnings, NSString **problem) {
    if (entry.type == DPKeySetting) return DPCheckedSetting(entry.setting, value, warnings, problem);
    if (entry.type == DPKeyShortcut) {
        if ([value isKindOfClass:NSDictionary.class] && DPValidShortcut(value)) return value;
        *problem = @"must be {} or an object with key, keyCode and modifiers";
        return nil;
    }
    if (![value isKindOfClass:NSString.class]) {
        *problem = @"must be text";
        return nil;
    }
    NSArray<NSString *> *choices = DPChoiceValues(entry.patch);
    if (choices.count && ![choices containsObject:value])
        [warnings addObject:[NSString stringWithFormat:@"%@ has no “%@” on this Mac, so Dia uses its default.", entry.patch->title, value]];
    return value;
}

static id DPExportedValue(DPPortableKey *entry, id value) {
    if (entry.type == DPKeyChoice) return [value isKindOfClass:NSString.class] ? value : nil;
    if (entry.type == DPKeyShortcut) return [value isKindOfClass:NSDictionary.class] && DPValidShortcut(value) ? value : nil;
    if (entry.setting->kind == DPSettingBool) return [value isKindOfClass:NSNumber.class] ? @([value boolValue]) : nil;
    if (entry.setting->kind == DPSettingNumber) return DPIsNumber(value) && isfinite([value doubleValue]) ? DPCleanNumber([value doubleValue]) : nil;
    // Older versions saved launch flags as an array, which Launch Flags still reads.
    if ([entry.setting->key isEqualToString:DPLaunchFlagsArgs] && [value isKindOfClass:NSArray.class]) {
        NSString *text = DPFlagsText(value);
        return text.length ? text : nil;
    }
    return [value isKindOfClass:NSString.class] ? value : nil;
}

NSData *DPExportConfigJSON(NSError **error) {
    NSMutableDictionary<NSString *, id> *tweaks = [NSMutableDictionary new], *settings = [NSMutableDictionary new];
    [DPPortablePatches() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSValue *patch, BOOL *stop) { tweaks[key] = @(DPStoredOn(patch.pointerValue)); }];
    [DPPortableKeys() enumerateKeysAndObjectsUsingBlock:^(NSString *key, DPPortableKey *entry, BOOL *stop) {
        id value = DPExportedValue(entry, [DPSettingsDefaults() objectForKey:key]);
        if (value) settings[key] = value;
    }];
    NSMutableData *json = [[NSJSONSerialization dataWithJSONObject:@{@"version": @1, @"tweaks": tweaks, @"settings": settings}
                                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error] mutableCopy];
    [json appendBytes:"\n" length:1];
    return json.length > 1 ? json : nil;
}

static BOOL DPRejectConfig(NSError **error, NSArray<NSString *> *problems) {
    if (!error) return NO;
    NSArray<NSString *> *shown = [problems subarrayWithRange:NSMakeRange(0, MIN(problems.count, 5))];
    NSString *more = problems.count > shown.count ? [NSString stringWithFormat:@"\nAnd %lu more.", problems.count - shown.count] : @"";
    *error = [NSError errorWithDomain:@"DiaTweaksConfig" code:1
                             userInfo:@{NSLocalizedDescriptionKey: [[shown componentsJoinedByString:@"\n"] stringByAppendingString:more]}];
    return NO;
}

static NSArray<NSString *> *DPSortedKeys(NSDictionary *dictionary) { return [dictionary.allKeys sortedArrayUsingSelector:@selector(compare:)]; }

static NSDictionary *DPSection(NSDictionary *root, NSString *name, NSMutableArray<NSString *> *problems) {
    id section = root[name] ?: @{};
    if ([section isKindOfClass:NSDictionary.class]) return section;
    [problems addObject:[NSString stringWithFormat:@"“%@” must be an object.", name]];
    return @{};
}

static BOOL DPSetsLaunchFlags(NSDictionary<NSString *, id> *writes) {
    DPPatch *flags = DPPatchNamed(@"launchFlags");
    if (flags && DPFlagValue(writes[flags->key], NO)) return YES;
    NSString *text = DPFlagsText(writes[DPLaunchFlagsArgs]);
    return text.length ? DPMentionsFlags(text) : NO;
}

// Reads and checks a file once, so the preview and the import can't disagree about it.
static DPConfigChanges *DPReadConfig(NSData *data, NSError **error) {
    id root = data.length && data.length <= DPConfigMaxBytes ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![root isKindOfClass:NSDictionary.class]) {
        DPRejectConfig(error, @[@"This isn’t a DiaTweaks settings file."]);
        return nil;
    }

    NSMutableArray<NSString *> *problems = [NSMutableArray new], *warnings = [NSMutableArray new], *unknown = [NSMutableArray new];
    NSMutableDictionary<NSString *, id> *writes = [NSMutableDictionary new];
    for (NSString *key in DPSortedKeys(root))
        if (![@[@"version", @"tweaks", @"settings"] containsObject:key]) [problems addObject:[NSString stringWithFormat:@"“%@” isn’t part of a settings file.", key]];
    if (!DPIsInteger(root[@"version"], 1, 1)) [problems addObject:@"Only settings files with \"version\": 1 can be imported."];

    NSDictionary<NSString *, NSValue *> *patches = DPPortablePatches();
    NSDictionary<NSString *, DPPortableKey *> *keys = DPPortableKeys();
    NSDictionary *tweaks = DPSection(root, @"tweaks", problems), *settings = DPSection(root, @"settings", problems);
    for (NSString *key in DPSortedKeys(tweaks)) {
        if (!patches[key]) [unknown addObject:key];
        else if (DPIsBool(tweaks[key])) writes[key] = tweaks[key];
        else [problems addObject:[NSString stringWithFormat:@"tweaks.%@ must be true or false.", key]];
    }
    for (NSString *key in DPSortedKeys(settings)) {
        if (!keys[key]) {
            [unknown addObject:key];
            continue;
        }
        NSString *problem = nil;
        id checked = DPCheckedValue(keys[key], settings[key], warnings, &problem);
        if (checked) writes[key] = checked;
        else [problems addObject:[NSString stringWithFormat:@"settings.%@ %@.", key, problem]];
    }
    if (problems.count) {
        DPRejectConfig(error, problems);
        return nil;
    }

    DPConfigChanges *changes = [DPConfigChanges new];
    changes.writes = writes;
    changes.unknownKeys = unknown;
    changes.warnings = warnings;
    changes.setsLaunchFlags = DPSetsLaunchFlags(writes);
    return changes;
}

static NSString *DPKeyFor(DPPortableKey *entry) {
    if (!entry) return nil;
    if (entry.type == DPKeyChoice) return entry.patch->choice;
    if (entry.type == DPKeyShortcut) return entry.patch->shortcut;
    return entry.setting->key;
}

static id DPDefaultValue(DPPortableKey *entry) {
    if (entry.type == DPKeyChoice) return entry.patch->defaultChoice;
    if (entry.type == DPKeyShortcut) return entry.patch->defaultShortcut ? entry.patch->defaultShortcut() : @{};
    if (entry.setting->kind == DPSettingBool) return @(entry.setting->defaultBool);
    if (entry.setting->kind == DPSettingNumber) return @(entry.setting->defaultNumber);
    return entry.setting->defaultString ?: @"";
}

static BOOL DPStoredValueMatches(DPPortableKey *entry, id wanted) {
    NSString *key = DPKeyFor(entry);
    id current = key ? [DPSettingsDefaults() objectForKey:key] : nil;
    if (!current) return [wanted isEqual:DPDefaultValue(entry)];
    if (entry.type == DPKeySetting && entry.setting->kind == DPSettingNumber)
        return DPIsNumber(current) && DPIsNumber(wanted) && [current doubleValue] == [wanted doubleValue];
    if (entry.type == DPKeySetting && entry.setting->kind == DPSettingString)
        return [DPFlagsText(current) isEqual:DPFlagsText(wanted)];
    return [current isEqual:wanted];
}

DPConfigPreview *DPPreviewConfigData(NSData *data, BOOL replace, NSError **error) {
    DPConfigChanges *changes = DPReadConfig(data, error);
    if (!changes) return nil;
    NSDictionary<NSString *, NSValue *> *patches = DPPortablePatches();
    NSDictionary<NSString *, DPPortableKey *> *keys = DPPortableKeys();
    DPConfigPreview *preview = [DPConfigPreview new];
    preview.unknownKeys = changes.unknownKeys;
    preview.warnings = changes.warnings;
    preview.setsLaunchFlags = changes.setsLaunchFlags;
    [changes.writes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id wanted, BOOL *stop) {
        BOOL matches = patches[key] ? DPStoredOn(patches[key].pointerValue) == [wanted boolValue] : DPStoredValueMatches(keys[key], wanted);
        preview.changes += !matches;
    }];
    if (replace)
        for (NSString *key in [patches.allKeys arrayByAddingObjectsFromArray:keys.allKeys])
            preview.resets += !changes.writes[key] && [DPSettingsDefaults() objectForKey:key] != nil;
    return preview;
}

DPConfigImport *DPImportConfigData(NSData *data, BOOL replace, NSError **error) {
    DPConfigChanges *changes = DPReadConfig(data, error);
    if (!changes) return nil;
    NSDictionary<NSString *, id> *writes = changes.writes;
    NSDictionary<NSString *, NSValue *> *patches = DPPortablePatches();
    NSDictionary<NSString *, DPPortableKey *> *keys = DPPortableKeys();

    NSUserDefaults *defaults = DPSettingsDefaults();
    NSMutableDictionary<NSString *, NSNumber *> *wasOn = [NSMutableDictionary new];
    for (NSString *key in patches)
        if (((DPPatch *)patches[key].pointerValue)->relaunch) wasOn[key] = @(DPStoredOn(patches[key].pointerValue));
    NSString *argsBefore = DPFlagsText([defaults objectForKey:DPLaunchFlagsArgs]) ?: @"";

    DPConfigImport *result = [DPConfigImport new];
    NSMutableSet<NSValue *> *tuned = [NSMutableSet new];
    void (^touch)(NSString *) = ^(NSString *key) {
        if (keys[key].type == DPKeySetting) [tuned addObject:[NSValue valueWithPointer:keys[key].patch]];
    };
    if (replace) {
        for (NSString *key in [patches.allKeys arrayByAddingObjectsFromArray:keys.allKeys]) {
            if (writes[key] || ![defaults objectForKey:key]) continue;
            [defaults removeObjectForKey:key];
            touch(key);
            result.resetCount++;
        }
    }
    [writes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        [defaults setObject:value forKey:key];
        touch(key);
    }];

    DPApplySavedSettings();
    for (NSValue *value in tuned) {
        DPPatch *patch = value.pointerValue;
        if (patch->on && patch->apply && !patch->relaunch && !DPSafeMode && !DPPausedAtLaunch) patch->apply(patch);
    }
    // No notify_post here: our own DPWatchSavedSettings would run the whole apply loop again.

    NSMutableArray<NSString *> *relaunch = [NSMutableArray new];
    for (NSString *key in DPSortedKeys(wasOn)) {
        DPPatch *patch = patches[key].pointerValue;
        if (DPStoredOn(patch) != wasOn[key].boolValue) [relaunch addObject:patch->title];
    }
    DPPatch *flags = DPPatchNamed(@"launchFlags");
    NSString *argsAfter = DPFlagsText([defaults objectForKey:DPLaunchFlagsArgs]) ?: @"";
    if (flags && DPStoredOn(flags) && ![argsAfter isEqual:argsBefore] && ![relaunch containsObject:flags->title]) [relaunch addObject:flags->title];
    result.appliedCount = writes.count;
    result.unknownKeys = changes.unknownKeys;
    result.warnings = changes.warnings;
    result.relaunchTitles = relaunch;
    return result;
}

