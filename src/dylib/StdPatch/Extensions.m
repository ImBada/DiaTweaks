#import "StdPatch/StdPatch.h"

static NSMutableArray<NSString *> *DPExtensionFolders, *DPAddedFlags, *DPDroppedFlags;

static NSMutableArray<NSString *> *DPListValues(NSString *list) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (NSString *value in [list componentsSeparatedByString:@","]) {
        NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) [values addObject:trimmed];
    }
    return values;
}

static BOOL DPIsListFlag(NSString *flag) {
    return [flag isEqualToString:@"--enable-features="] || [flag isEqualToString:@"--disable-features="] ||
           [flag isEqualToString:@"--load-extension="] || [flag isEqualToString:@"--host-resolver-rules="];
}

// Chromium keeps only the last of a flag, so a list flag given more than once becomes one listing every value.
static void DPMergeListFlag(NSMutableArray<NSString *> *args, NSString *flag) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSUInteger first = NSNotFound;
    for (NSUInteger i = args.count; i-- > 1;)
        if ([args[i] hasPrefix:flag]) {
            NSArray<NSString *> *parts = DPListValues([args[i] substringFromIndex:flag.length]);
            for (NSUInteger j = parts.count; j-- > 0;) [values insertObject:parts[j] atIndex:0];
            [args removeObjectAtIndex:(first = i)];
        }
    NSMutableArray<NSString *> *unique = [NSMutableArray arrayWithCapacity:values.count];
    for (NSString *value in values)
        if (![unique containsObject:value]) [unique addObject:value];
    if (unique.count) [args insertObject:[flag stringByAppendingString:[unique componentsJoinedByString:@","]] atIndex:first];
}

// A relaunch Dia starts itself repeats the flags it ran with, so a flag a tweak is off for has to come out again.
static void DPDropFlags(NSMutableArray<NSString *> *args) {
    for (NSString *dropped in DPDroppedFlags) {
        NSRange eq = [dropped rangeOfString:@"="];
        NSString *flag = eq.location == NSNotFound ? nil : [dropped substringToIndex:eq.location + 1];
        if (!flag || !DPIsListFlag(flag)) {
            for (NSUInteger i = args.count; i-- > 1;)
                if ([args[i] isEqualToString:dropped]) [args removeObjectAtIndex:i];
            continue;
        }
        NSArray<NSString *> *values = DPListValues([dropped substringFromIndex:flag.length]);
        for (NSUInteger i = args.count; i-- > 1;) {
            if (![args[i] hasPrefix:flag]) continue;
            NSMutableArray<NSString *> *kept = DPListValues([args[i] substringFromIndex:flag.length]);
            [kept removeObjectsInArray:values];
            if (kept.count) args[i] = [flag stringByAppendingString:[kept componentsJoinedByString:@","]];
            else [args removeObjectAtIndex:i];
        }
    }
}

static id DPConfiguration_init(id self, SEL _cmd, int argc, NSArray<NSString *> *argv, NSString *profilePath, NSUInteger applicationID,
                               BOOL isProduction, NSUInteger restorationPolicy, BOOL loadAllProfiles, BOOL quitRunLoop, NSString *suiteName) {
    static NSString *const flag = @"--load-extension=";
    NSString *oursBase = DPAppSupport(@"DiaPatches").stringByStandardizingPath;
    NSString *ours = [oursBase stringByAppendingString:@"/"];
    NSMutableArray<NSString *> *args = [argv mutableCopy], *folders = [NSMutableArray array];
    DPDropFlags(args);
    [args addObjectsFromArray:DPAddedFlags];
    for (NSUInteger i = args.count; i-- > 1;)
        if ([args[i] hasPrefix:flag] || [args[i] isEqualToString:@"--load-extension"]) {
            if (args[i].length > flag.length) {
                NSArray<NSString *> *parts = [[args[i] substringFromIndex:flag.length] componentsSeparatedByString:@","];
                for (NSUInteger j = parts.count; j-- > 0;) {
                    NSString *folder = parts[j], *clean = folder.stringByStandardizingPath;
                    if (folder.length && ![clean isEqualToString:oursBase] && ![clean hasPrefix:ours]) [folders insertObject:folder atIndex:0];
                }
            }
            [args removeObjectAtIndex:i];
        }
    [folders addObjectsFromArray:DPExtensionFolders];
    if (folders.count) [args addObject:[flag stringByAppendingString:[folders componentsJoinedByString:@","]]];
    DPMergeListFlag(args, @"--enable-features=");
    DPMergeListFlag(args, @"--disable-features=");
    DPMergeListFlag(args, @"--host-resolver-rules=");
    return DPCallOriginal(DPConfiguration_init, self, argc + ((int)args.count - (int)argv.count), args, profilePath, applicationID, isProduction,
                          restorationPolicy, loadAllProfiles, quitRunLoop, suiteName);
}

static void DPHookConfiguration(void) {
    if (DPExtensionFolders) return;
    DPExtensionFolders = [NSMutableArray array];
    DPAddedFlags = [NSMutableArray array];
    DPDroppedFlags = [NSMutableArray array];
    DPHook(DPDiaAppConfiguration, @selector(init:argv:profilePath:applicationID:isProduction:sessionRestorationPolicy:shouldLoadAllProfilesAtStartup:quitRunLoopOnTermination:userDefaultsSuiteName:),
           (IMP)DPConfiguration_init);
}

void DPLoadExtension(NSString *folder) {
    DPHookConfiguration();
    if (![DPExtensionFolders containsObject:folder]) [DPExtensionFolders addObject:folder];
}

void DPAddLaunchFlag(NSString *flag) {
    DPHookConfiguration();
    [DPAddedFlags addObject:flag];
}

void DPDropLaunchFlag(NSString *flag) {
    DPHookConfiguration();
    if (![DPDroppedFlags containsObject:flag]) [DPDroppedFlags addObject:flag];
}

void DPDropExtension(NSString *folder) {
    DPDropLaunchFlag([@"--load-extension=" stringByAppendingString:folder]);
}
