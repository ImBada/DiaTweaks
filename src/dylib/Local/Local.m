#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import <sys/stat.h>

extern const struct mach_header_64 __dso_handle;

static NSMutableArray<NSValue *> *DPLocalTable;
static NSMutableDictionary<NSString *, NSString *> *DPLocalRepairNotes;
static NSMutableArray<NSDictionary *> *DPLocalStateItems;
static DPPatch **DPLocalArray;
static NSUInteger DPLocalArrayCount;
static BOOL DPLocalLoaded;
static NSDictionary *DPLocalSaved;  // local-state.json as read at the start of a load or a build
static NSSet<NSString *> *DPLocalOfficialKeys;

NSString *DPLocalFolder(void) { return DPAppSupport(@"DiaPatches/local"); }

NSString *DPLocalCacheFolder(void) {
    const char *home = getenv("DIAPATCH_HOME");
    if (home && *home) return [@(home) stringByAppendingPathComponent:@".cache/local"];
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DiaPatches/local"];
}

NSString *DPLocalStatePath(void) { return DPAppSupport(@"DiaPatches/local-state.json"); }

BOOL DPLocalTweaksEnabled(void) {
    if (DPPaused || DPSafeMode >= 1 || DPLocalSafeModeOff()) return NO;
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    id value = [defaults objectForKey:@"localTweaks"];
    return value ? [value boolValue] : YES;
}

void DPLocalReset(void) {
    DPLocalTable = nil;
    free(DPLocalArray);
    DPLocalArray = NULL;
    DPLocalArrayCount = 0;
    DPLocalLoaded = NO;
    DPLocalSaved = nil;
    DPLocalRepairNotes = nil;
    DPLocalStateItems = nil;
}

DPPatch **DPLocalPatches(void) { return DPLocalArray; }

static void DPLocalPack(void) {
    free(DPLocalArray);
    DPLocalArrayCount = DPLocalTable.count;
    DPLocalArray = DPLocalArrayCount ? calloc(DPLocalArrayCount, sizeof *DPLocalArray) : NULL;
    for (NSUInteger i = 0; i < DPLocalArrayCount; i++) DPLocalArray[i] = ((NSValue *)DPLocalTable[i]).pointerValue;
}

NSArray<NSDictionary *> *DPLocalFileStamps(NSArray<NSString *> *sources) {
    NSMutableArray<NSDictionary *> *stamps = [NSMutableArray new];
    for (NSString *source in sources) {
        struct stat info;
        if (stat(source.fileSystemRepresentation, &info) != 0) continue;
        [stamps addObject:@{
            @"path" : source,
            @"mtime" : @(info.st_mtimespec.tv_sec * 1000000000LL + info.st_mtimespec.tv_nsec),
            @"size" : @(info.st_size),
        }];
    }
    return stamps;
}

BOOL DPLocalFilesMatch(NSArray<NSDictionary *> *saved, NSArray<NSString *> *sources) {
    if (![saved isKindOfClass:NSArray.class] || saved.count != sources.count) return NO;
    NSArray<NSDictionary *> *now = DPLocalFileStamps(sources);
    if (now.count != saved.count) return NO;
    for (NSUInteger i = 0; i < now.count; i++)
        if (![now[i][@"path"] isEqual:saved[i][@"path"]] || ![now[i][@"mtime"] isEqual:saved[i][@"mtime"]]
            || ![now[i][@"size"] isEqual:saved[i][@"size"]])
            return NO;
    return YES;
}

id DPLocalSavedValue(NSString *key) { return DPLocalSaved[key]; }

NSDictionary *DPLocalSavedItem(NSString *identifier) {
    for (NSDictionary *item in DPLocalSaved[@"items"])
        if ([item[@"id"] isEqual:identifier]) return item;
    return nil;
}

NSString *DPLocalRun(NSArray<NSString *> *argv) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = task.standardError = pipe;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) return nil;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray<NSString *> *DPLocalSourcesIn(NSString *folder) {
    NSMutableArray<NSString *> *sources = [NSMutableArray new];
    for (NSString *relative in [NSFileManager.defaultManager enumeratorAtPath:folder]) {
        if ([relative.lastPathComponent hasPrefix:@"."]) continue;
        if (![relative.pathExtension isEqual:@"m"]) continue;
        [sources addObject:[folder stringByAppendingPathComponent:relative]];
    }
    [sources sortUsingSelector:@selector(compare:)];
    return sources;
}

static NSString *DPLocalBinaryKind(NSString *extension) {
    if ([extension isEqual:@"dylib"]) return @"dylib";
    if ([extension isEqual:@"patch"] || [extension isEqual:@"diff"]) return @"patch";
    if ([extension isEqual:@"zip"] || [extension isEqual:@"diatweak"]) return @"archive";
    return nil;
}

static NSArray<NSDictionary *> *DPLocalScan(void) {
    NSString *folder = DPLocalFolder();
    NSFileManager *files = NSFileManager.defaultManager;
    NSArray<NSString *> *names = [files contentsOfDirectoryAtPath:folder error:NULL];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if ([name hasPrefix:@"."] || [name isEqual:@"README.md"]) continue;
        NSString *path = [folder stringByAppendingPathComponent:name];
        BOOL directory = NO;
        if (![files fileExistsAtPath:path isDirectory:&directory]) continue;
        NSString *extension = name.pathExtension.lowercaseString, *identifier = name.stringByDeletingPathExtension;
        NSDictionary *item;
        if (directory) {
            NSArray<NSString *> *sources = DPLocalSourcesIn(path);
            if (!sources.count) continue;
            item = @{ @"id" : identifier, @"kind" : @"source", @"path" : path, @"sources" : sources, @"dir" : path };
        } else if ([extension isEqual:@"m"]) {
            item = @{ @"id" : identifier, @"kind" : @"source", @"path" : path, @"sources" : @[ path ], @"dir" : folder };
        } else {
            NSString *kind = DPLocalBinaryKind(extension);
            if (!kind) continue;
            item = @{ @"id" : identifier, @"kind" : kind, @"path" : path };
        }
        if ([seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        [items addObject:item];
    }
    return items;
}

static NSString *DPLocalStamp(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) return @"0";
    return [NSString stringWithFormat:@"%llx-%llx", (unsigned long long)info.st_mtimespec.tv_sec * 1000000000ULL + info.st_mtimespec.tv_nsec,
                                      (unsigned long long)info.st_size];
}

static NSDictionary *DPLocalPrepare(NSDictionary *item) {
    NSString *kind = item[@"kind"], *path = item[@"path"];
    if ([kind isEqual:@"source"]) {
        NSMutableArray<NSString *> *dirs = [NSMutableArray arrayWithObject:item[@"dir"]];
        for (NSString *source in item[@"sources"]) [dirs addObject:source.stringByDeletingLastPathComponent];
        return @{ @"sources" : item[@"sources"], @"includeDirs" : dirs };
    }
    if ([kind isEqual:@"dylib"]) return @{ @"dylib" : path };

    NSString *folder = [DPLocalCacheFolder() stringByAppendingPathComponent:
                                             [NSString stringWithFormat:@"extracted/%@/%@", item[@"id"], DPLocalStamp(path)]];
    NSString *marker = [folder stringByAppendingPathComponent:@".done"];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:marker]) {
        [files removeItemAtPath:folder error:NULL];
        if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL])
            return @{ @"error" : @"Couldn’t create the build folder for this tweak." };
        NSString *error = nil;
        if ([kind isEqual:@"patch"]) DPLocalExtractPatch(path, folder, &error);
        else DPLocalExtractArchive(path, folder, &error);
        if (error) return @{ @"error" : error };
        [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    NSArray<NSString *> *sources = DPLocalSourcesIn(folder);
    if (!sources.count) return @{ @"error" : @"This has no .m tweak files in it." };
    NSMutableArray<NSString *> *dirs = [NSMutableArray arrayWithObject:folder];
    for (NSString *source in sources) [dirs addObject:source.stringByDeletingLastPathComponent];
    NSString *defines = [folder stringByAppendingPathComponent:@"_dp_patch_defines.h"];
    return @{ @"sources" : sources, @"includeDirs" : dirs, @"defines" : [files fileExistsAtPath:defines] ? defines : @"" };
}

static id DPLocalFail(NSString **error, NSString *message, NSString *cleanup) {
    if (cleanup) [NSFileManager.defaultManager removeItemAtPath:cleanup error:NULL];
    *error = message;
    return nil;
}

static NSString *DPLocalHash(NSString *uuid, NSArray<NSString *> *sources, NSString *defines) {
    NSMutableData *feed = [NSMutableData data];
    [feed appendData:[uuid dataUsingEncoding:NSUTF8StringEncoding]];
    [feed appendData:[@"1" dataUsingEncoding:NSUTF8StringEncoding]];  // Bump when the compile command changes.
    for (NSDictionary *stamp in DPLocalFileStamps(sources)) {
        [feed appendData:[stamp[@"path"] dataUsingEncoding:NSUTF8StringEncoding]];
        [feed appendData:[[NSString stringWithFormat:@"%@:%@", stamp[@"mtime"], stamp[@"size"]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    if (defines.length) [feed appendData:[NSData dataWithContentsOfFile:defines] ?: NSData.data];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(feed.bytes, (CC_LONG)feed.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex substringToIndex:16];
}

// The warm path: a matching state entry and a dylib on disk means no hashing and no clang.
static NSString *DPLocalEnsureBuilt(NSString *identifier, NSArray<NSString *> *sources, NSArray<NSString *> *includeDirs, NSString *defines, NSString **error) {
    NSString *uuid = DPDylibUUID();
    NSDictionary *saved = DPLocalSavedItem(identifier);
    if (saved && [saved[@"uuid"] isEqual:uuid] && DPLocalFilesMatch(saved[@"files"], sources)) {
        NSString *cached = saved[@"dylib"];
        if ([cached isKindOfClass:NSString.class] && [NSFileManager.defaultManager fileExistsAtPath:cached]) return cached;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *bin = [DPLocalCacheFolder() stringByAppendingPathComponent:@"bin"];
    [files createDirectoryAtPath:bin withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *final = [bin stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.dylib", identifier, DPLocalHash(uuid, sources, defines)]];
    if ([files fileExistsAtPath:final]) return final;
    NSString *temporary = [final stringByAppendingString:@".tmp"];
    [files removeItemAtPath:temporary error:NULL];
    if (!DPLocalCompile(sources, includeDirs, defines, temporary, error)) return DPLocalFail(error, *error, temporary);
    // Rename over the old file: a running Dia may still have it mapped, and rename never disturbs that.
    if (rename(temporary.fileSystemRepresentation, final.fileSystemRepresentation) != 0)
        return DPLocalFail(error, @"Couldn’t put the built tweak in place.", temporary);
    return final;
}

static const struct mach_header_64 *DPLocalImageFor(NSString *path) {
    char want[PATH_MAX];
    if (!realpath(path.fileSystemRepresentation, want)) return NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && !strcmp(name, want)) return (const void *)_dyld_get_image_header(i);
    }
    return NULL;
}

// dlopen refuses an unsigned dylib, so a prebuilt one is checked, signed and loaded from the cache.
static NSString *DPLocalPrepareDylib(NSString *path, NSString *identifier, NSString **error) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:32];
    [handle closeFile];
    if (head.length < 32) return DPLocalFail(error, @"That file isn’t a dylib.", nil);
    const uint32_t *words = head.bytes;
    if (words[0] != MH_MAGIC_64 || words[3] != MH_DYLIB) return DPLocalFail(error, @"That file isn’t a 64-bit Mach-O dylib.", nil);
    if (words[1] != CPU_TYPE_ARM64)
        return DPLocalFail(error, [NSString stringWithFormat:@"It was built for another processor (cputype %u); Dia is arm64.", words[1]], nil);
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *folder = [DPLocalCacheFolder() stringByAppendingPathComponent:@"dylibs"];
    [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *copy = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.dylib", identifier, DPLocalStamp(path)]];
    if ([files fileExistsAtPath:copy]) return copy;
    NSString *temporary = [copy stringByAppendingString:@".tmp"];
    [files removeItemAtPath:temporary error:NULL];
    if (![files copyItemAtPath:path toPath:temporary error:NULL]) return DPLocalFail(error, @"Couldn’t copy it into the cache.", nil);
    DPLocalRun(@[ @"/usr/bin/xattr", @"-dr", @"com.apple.quarantine", temporary ]);
    if (!DPLocalRun(@[ @"/usr/bin/codesign", @"--force", @"--sign", @"-", temporary ]))
        return DPLocalFail(error, @"Couldn’t sign it, so macOS won’t load it.", temporary);
    if (rename(temporary.fileSystemRepresentation, copy.fileSystemRepresentation) != 0)
        return DPLocalFail(error, @"Couldn’t put the signed tweak in place.", temporary);
    return copy;
}

static NSArray<NSValue *> *DPLocalOpen(NSString *dylib, NSString **error) {
    void *handle = dlopen(dylib.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) return DPLocalFail(error, [NSString stringWithFormat:@"Couldn’t load it: %s", dlerror()], nil);
    const struct mach_header_64 *header = DPLocalImageFor(dylib);
    if (!header) return DPLocalFail(error, @"Couldn’t find the loaded tweak.", nil);
    // No stamp means it was built against some other DPPatch layout, so reading its fields would be a guess.
    unsigned long abiSize = 0;
    const uint32_t *abi = (const uint32_t *)getsectiondata(header, "__DATA", "__dpabi", &abiSize);
    if (!abi || abiSize < 8 || abi[0] != DP_LOCAL_ABI || abi[1] != sizeof(DPPatch))
        return DPLocalFail(error, @"Built for an older DiaTweaks ABI — recompile from source.", nil);
    unsigned long size = 0;
    DPPatch **entries = (DPPatch **)getsectiondata(header, "__DATA", "__dppatches", &size);
    if (!entries || !size) return DPLocalFail(error, @"It has no tweaks in it.", nil);
    NSMutableArray<NSValue *> *patches = [NSMutableArray new];
    for (NSUInteger i = 0; i < size / sizeof *entries; i++) [patches addObject:[NSValue valueWithPointer:entries[i]]];
    return patches;
}

static NSSet<NSString *> *DPLocalOfficialKeySet(void) {
    if (DPLocalOfficialKeys) return DPLocalOfficialKeys;
    NSMutableSet<NSString *> *keys = [NSMutableSet new];
    unsigned long size = 0;
    DPPatch **entries = (DPPatch **)getsectiondata(&__dso_handle, "__DATA", "__dppatches", &size);
    for (NSUInteger i = 0; entries && i < size / sizeof *entries; i++)
        if (entries[i]->key) [keys addObject:entries[i]->key];
    DPLocalOfficialKeys = keys;
    return keys;
}

static NSDictionary *DPLocalRecord(NSString *identifier, NSString *kind, NSString *path, NSArray<NSString *> *sources,
                                   NSArray<NSDictionary *> *patches, NSString *status, NSString *error, NSString *dylib) {
    NSMutableDictionary *record = [@{
        @"id" : identifier,
        @"kind" : kind,
        @"path" : path,
        @"status" : status,
        @"patches" : patches,
    } mutableCopy];
    if (error) record[@"error"] = error;
    if (dylib) record[@"dylib"] = dylib;
    if (sources.count) record[@"files"] = DPLocalFileStamps(sources);
    return record;
}

static NSDictionary *DPLocalPatchRecord(DPPatch *patch) {
    return @{
        @"key" : patch->key,
        @"title" : patch->title,
        @"detail" : patch->detail ?: @"",
        @"defaultOn" : @(patch->defaultOn),
        @"requires" : patch->requires ?: NSNull.null,
        @"disabledBy" : patch->disabledBy ?: NSNull.null,
        @"coveredBy" : patch->coveredBy ?: NSNull.null,
        @"relaunch" : @(patch->relaunch),
    };
}

static BOOL DPLocalHasKey(NSArray<NSValue *> *patches, NSString *key) {
    for (NSValue *value in patches)
        if ([((DPPatch *)value.pointerValue)->key isEqual:key]) return YES;
    return NO;
}

static NSDictionary *DPLocalProcessItem(NSDictionary *item, BOOL splice) {
    NSString *identifier = item[@"id"], *kind = item[@"kind"], *path = item[@"path"];
    NSDictionary *prepared = DPLocalPrepare(item);
    NSArray<NSString *> *sources = prepared[@"sources"] ?: @[];
    NSDictionary *(^failed)(NSString *, NSString *, NSString *) = ^NSDictionary *(NSString *status, NSString *problem, NSString *dylib) {
        return DPLocalRecord(identifier, kind, path, sources, @[], status, problem, dylib);
    };
    if (prepared[@"error"]) return failed(@"failed", prepared[@"error"], nil);

    NSString *dylib = prepared[@"dylib"], *error = nil;
    if (dylib) {
        dylib = DPLocalPrepareDylib(dylib, identifier, &error);
        if (!dylib) return failed(@"incompatible", error, nil);
    } else {
        dylib = DPLocalEnsureBuilt(identifier, sources, prepared[@"includeDirs"], prepared[@"defines"], &error);
        if (!dylib) return failed(@"failed", error, nil);
    }
    NSArray<NSValue *> *patches = DPLocalOpen(dylib, &error);
    if (!patches) return failed(@"incompatible", error, dylib);

    NSMutableArray<NSValue *> *accepted = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray new];
    NSMutableArray<NSString *> *problems = [NSMutableArray new];
    for (NSValue *value in patches) {
        DPPatch *patch = value.pointerValue;
        if (!patch->key.length || !patch->title.length) {
            [problems addObject:@"A tweak in it has no key or title."];
            continue;
        }
        // `order` packs the table index into 8 bits, so the table can't grow past 255.
        if (DPLocalTable.count + accepted.count >= 64) {
            [problems addObject:@"DiaTweaks runs at most 64 local tweaks."];
            break;
        }
        if ([DPLocalOfficialKeySet() containsObject:patch->key] || DPLocalHasKey(accepted, patch->key) || DPLocalHasKey(DPLocalTable, patch->key)) {
            [problems addObject:[NSString stringWithFormat:@"It uses the key “%@”, which DiaTweaks already has.", patch->key]];
            continue;
        }
        if (!patch->section) patch->section = @"Local";
        if (!patch->tint) patch->tint = @"systemOrangeColor";
        // A tweak that names no order would sort ahead of every official one and put Local at the top of Settings.
        if (patch->order <= 0) patch->order = 100000 + (int)(DPLocalTable.count + accepted.count);
        [accepted addObject:value];
        [records addObject:DPLocalPatchRecord(patch)];
    }
    if (!accepted.count) return failed(@"failed", problems.firstObject ?: @"It has no tweaks in it.", dylib);

    NSString *problem = problems.count ? [problems componentsJoinedByString:@" "] : nil;
    for (NSValue *value in accepted) {
        DPNoteLocalPatch(value.pointerValue, identifier, nil);
        if (splice) [DPLocalTable addObject:value];
    }
    return DPLocalRecord(identifier, kind, path, sources, records, splice ? @"loaded" : @"ready", problem, dylib);
}

NSUInteger DPLocalLoad(void) {
    if (DPLocalLoaded) return DPLocalArrayCount;
    DPLocalLoaded = YES;
    if (!DPLocalTweaksEnabled()) return 0;
    NSArray<NSDictionary *> *items = DPLocalScan();
    if (!items.count) return 0;
    DPLocalTable = [NSMutableArray new];
    DPLocalSaved = DPLocalReadState();
    NSMutableArray<NSDictionary *> *state = [NSMutableArray new];
    for (NSDictionary *item in items) [state addObject:DPLocalProcessItem(item, YES)];
    DPLocalPack();
    DPLocalStateItems = state;
    DPLocalWriteState(state);
    return DPLocalArrayCount;
}

void DPLocalRepairLinks(void) {
    for (NSValue *value in DPLocalTable) {
        DPPatch *patch = value.pointerValue;
        __unsafe_unretained NSString **links[] = { &patch->requires, &patch->disabledBy, &patch->coveredBy };
        for (int field = 0; field < 3; field++) {
            NSString *key = *links[field];
            if (!key) continue;
            DPPatch *target = DPPatchNamed(key);
            BOOL bad = !target || target == patch;
            int hops = 0;
            for (DPPatch *walk = target; !bad && walk && hops < 32; walk = DPRequired(walk), hops++) bad = walk == patch;
            if (!bad) continue;
            *links[field] = nil;
            NSString *identifier = DPLocalIdentifier(patch);
            if (!identifier) continue;
            if (!DPLocalRepairNotes) DPLocalRepairNotes = [NSMutableDictionary new];
            DPLocalRepairNotes[identifier] = [NSString stringWithFormat:@"“%@” points at “%@”, which isn’t there, so the link was dropped.",
                                                                        patch->title, key];
        }
    }
    if (!DPLocalRepairNotes.count) return;
    for (NSUInteger i = 0; i < DPLocalStateItems.count; i++) {
        NSMutableDictionary *record = [DPLocalStateItems[i] mutableCopy];
        NSString *note = DPLocalRepairNotes[record[@"id"]];
        if (!note) continue;
        record[@"error"] = record[@"error"] ? [NSString stringWithFormat:@"%@ %@", record[@"error"], note] : note;
        DPLocalStateItems[i] = record;
    }
    DPLocalWriteState(DPLocalStateItems);
}

NSArray<NSDictionary *> *DPLocalItems(void) {
    NSMutableDictionary<NSString *, NSDictionary *> *saved = [NSMutableDictionary new];
    for (NSDictionary *item in DPLocalReadState()[@"items"])
        if (item[@"id"]) saved[item[@"id"]] = item;
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSDictionary *item in DPLocalScan()) {
        [items addObject:saved[item[@"id"]] ?: @{
            @"id" : item[@"id"],
            @"kind" : item[@"kind"],
            @"path" : item[@"path"],
            @"status" : @"ready",
            @"patches" : @[],
        }];
    }
    return items;
}

static NSString *DPLocalDescribe(NSDictionary *record) {
    NSString *status = record[@"status"];
    NSString *line = @"build failed";
    if ([status isEqual:@"loaded"]) line = @"loaded";
    else if ([status isEqual:@"ready"]) line = @"ready — relaunch Dia";
    else if ([status isEqual:@"incompatible"]) line = @"incompatible";
    NSMutableArray<NSString *> *keys = [NSMutableArray new];
    for (NSDictionary *patch in record[@"patches"]) if (patch[@"key"]) [keys addObject:patch[@"key"]];
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@  %@  %@", record[@"id"], record[@"kind"], line];
    if (keys.count) [text appendFormat:@"  (%@)", [keys componentsJoinedByString:@", "]];
    if (record[@"error"]) [text appendFormat:@"\n    %@", record[@"error"]];
    return text;
}

BOOL DPLocalBuildAll(NSArray<NSString *> *names, NSString **report) {
    DPLocalSaved = DPLocalReadState();
    NSMutableArray<NSDictionary *> *state = [NSMutableArray new];
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    BOOL ok = YES;
    for (NSDictionary *item in DPLocalScan()) {
        if (names.count && ![names containsObject:item[@"id"]]) {
            NSDictionary *saved = DPLocalSavedItem(item[@"id"]);
            if (saved) [state addObject:saved];
            continue;
        }
        NSDictionary *record = DPLocalProcessItem(item, NO);
        [state addObject:record];
        if (![record[@"status"] isEqual:@"ready"]) ok = NO;
        [lines addObject:DPLocalDescribe(record)];
    }
    DPLocalWriteState(state);
    if (report) *report = lines.count ? [lines componentsJoinedByString:@"\n"] : @"There are no local tweaks to build.";
    return ok;
}

static BOOL DPLocalDoctor(void) {
    BOOL ok = YES;
    NSString *error = nil;
    NSDictionary *toolchain = DPLocalToolchain(&error);
    if (toolchain) {
        printf("clang      %s\nsdk        %s\n", [toolchain[@"clang"] UTF8String], [toolchain[@"sdk"] UTF8String]);
    } else {
        printf("clang      %s\n", error.UTF8String);
        ok = NO;
    }
    NSString *headers = DPLocalHeaders(&error);
    printf("headers    %s\n", headers ? headers.UTF8String : error.UTF8String);
    if (!headers) ok = NO;
    NSString *folder = DPLocalFolder();
    BOOL writable = [[NSFileManager defaultManager] isWritableFileAtPath:folder] || ![[NSFileManager defaultManager] fileExistsAtPath:folder];
    printf("local      %s (%s)\n", folder.UTF8String, writable ? "writable" : "not writable");
    if (!writable) ok = NO;
    NSString *report = nil;
    if (!DPLocalBuildAll(nil, &report)) ok = NO;
    printf("%s\n", report.UTF8String);
    return ok;
}

int DPLocalBuildCommand(int argc, const char *const *argv) {
    NSMutableArray<NSString *> *arguments = [NSMutableArray new];
    for (int i = 0; i < argc; i++) [arguments addObject:@(argv[i])];
    return DPLocalBuildMain(arguments) ? 0 : 1;
}

BOOL DPLocalBuildMain(NSArray<NSString *> *arguments) {
    NSMutableArray<NSString *> *rest = [arguments mutableCopy];
    while (rest.count && ![rest[0] isEqual:@"local"]) [rest removeObjectAtIndex:0];
    if (rest.count) [rest removeObjectAtIndex:0];
    NSString *action = rest.count && ![rest[0] hasPrefix:@"-"] ? rest[0] : @"list";
    if (rest.count && ![rest[0] hasPrefix:@"-"]) [rest removeObjectAtIndex:0];
    if ([action isEqual:@"build"]) {
        NSString *report = nil;
        BOOL ok = DPLocalBuildAll(rest, &report);
        printf("%s\n", report.UTF8String);
        return ok;
    }
    if ([action isEqual:@"doctor"]) return DPLocalDoctor();
    for (NSDictionary *item in DPLocalItems()) printf("%s\n", DPLocalDescribe(item).UTF8String);
    return YES;
}

NSString *DPLocalAdd(NSString *path, NSString **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:path]) {
        *error = @"There’s nothing at that path.";
        return nil;
    }
    NSString *folder = DPLocalFolder();
    if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]) {
        *error = @"Couldn’t create the local folder.";
        return nil;
    }
    DPLocalWriteReadme();
    NSString *name = path.lastPathComponent, *destination = [folder stringByAppendingPathComponent:name];
    if ([files fileExistsAtPath:destination]) {
        NSString *base = name.stringByDeletingPathExtension, *extension = name.pathExtension;
        for (int i = 2; i < 1000; i++) {
            NSString *candidate = extension.length ? [NSString stringWithFormat:@"%@ %d.%@", base, i, extension] : [NSString stringWithFormat:@"%@ %d", base, i];
            destination = [folder stringByAppendingPathComponent:candidate];
            if (![files fileExistsAtPath:destination]) break;
        }
    }
    if (![files copyItemAtPath:path toPath:destination error:NULL]) {
        *error = @"Couldn’t copy it into the local folder.";
        return nil;
    }
    return destination;
}

static NSString *const DPLocalReadme =
    @"# Local Tweaks\n"
    @"\n"
    @"Anything in this folder runs as a normal DiaTweaks tweak, with its own switch in Settings.\n"
    @"DiaTweaks updates and `diapatch uninstall --purge` never touch this folder.\n"
    @"\n"
    @"- `MyTweak.m` — a single source file. It compiles against the headers inside the installed\n"
    @"  DiaPatches.dylib, so it keeps working after a DiaTweaks update.\n"
    @"- `MyTweak/` — a folder of `.m` and `.h` files that compile together.\n"
    @"- `pr-123.patch` — a GitHub pull request diff. New `.m` and `.h` files are extracted and built;\n"
    @"  changes to existing tweaks need a full DiaTweaks build.\n"
    @"- `MyTweak.dylib` — a prebuilt tweak. It must be arm64 and built for this DiaTweaks.\n"
    @"- `MyTweak.zip` — a folder of sources, unpacked and built.\n"
    @"\n"
    @"Settings > Patches > Local Tweaks has Add Tweak…, New Starter Tweak…, Open Folder and Rebuild All.\n"
    @"`diatweaks local` does the same from a terminal.\n";

void DPLocalWriteReadme(void) {
    NSString *folder = DPLocalFolder();
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *readme = [folder stringByAppendingPathComponent:@"README.md"];
    if ([NSFileManager.defaultManager fileExistsAtPath:readme]) return;
    [DPLocalReadme writeToFile:readme atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
