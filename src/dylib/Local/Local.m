#import "Local/Local.h"
#import "SafeMode/SafeMode.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import <sys/stat.h>
#import <sys/xattr.h>

extern const struct mach_header_64 __dso_handle;

static NSMutableArray<NSValue *> *DPLocalTable;
static NSMutableDictionary<NSString *, NSString *> *DPLocalRepairNotes;
static NSMutableArray<NSDictionary *> *DPLocalStateItems;
static DPPatch **DPLocalArray;
static NSUInteger DPLocalArrayCount;
static BOOL DPLocalLoaded;
static NSDictionary *DPLocalSaved;
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
    id value = [DPSettingsDefaults() objectForKey:@"localTweaks"];
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

NSString *DPLocalStamp(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) return @"0";
    return [NSString stringWithFormat:@"%llx-%llx", (unsigned long long)info.st_mtimespec.tv_sec * 1000000000ULL + info.st_mtimespec.tv_nsec,
                                      (unsigned long long)info.st_size];
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

static BOOL DPLocalStampsMatch(id saved, NSArray<NSDictionary *> *stamps, NSUInteger count) {
    return [saved isKindOfClass:NSArray.class] && [saved count] == count && [stamps isEqualToArray:saved];
}

BOOL DPLocalFilesMatch(NSArray<NSDictionary *> *saved, NSArray<NSString *> *sources) {
    return DPLocalStampsMatch(saved, DPLocalFileStamps(sources), sources.count);
}

id DPLocalSavedValue(NSString *key) { return DPLocalSaved[key]; }

NSDictionary *DPLocalSavedItem(NSString *identifier) {
    for (NSDictionary *item in DPLocalSaved[@"items"])
        if ([item[@"id"] isEqual:identifier]) return item;
    return nil;
}

int DPLocalExec(NSArray<NSString *> *argv, NSString **output) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:argv[0]];
    task.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = task.standardError = pipe;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    *output = nil;
    if (![task launchAndReturnError:NULL]) return -1;
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    *output = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return task.terminationStatus;
}

NSString *DPLocalRun(NSArray<NSString *> *argv) {
    NSString *output = nil;
    return DPLocalExec(argv, &output) == 0 ? output : nil;
}

static NSArray<NSString *> *DPLocalTracked(NSString *folder) {
    NSMutableArray<NSString *> *found = [NSMutableArray new];
    NSDirectoryEnumerator *walk = [NSFileManager.defaultManager enumeratorAtPath:folder];
    for (NSString *relative in walk) {
        if ([relative.lastPathComponent hasPrefix:@"."]) [walk skipDescendants];
        else if ([@[ @"m", @"h" ] containsObject:relative.pathExtension.lowercaseString]) [found addObject:[folder stringByAppendingPathComponent:relative]];
    }
    [found sortUsingSelector:@selector(compare:)];
    return found;
}

static NSArray<NSString *> *DPLocalSourcesIn(NSArray<NSString *> *tracked) {
    return [tracked filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path, id bindings) {
        return [path.pathExtension.lowercaseString isEqual:@"m"];
    }]];
}

static NSString *DPLocalBinaryKind(NSString *extension) {
    if ([extension isEqual:@"dylib"]) return @"dylib";
    if ([extension isEqual:@"patch"] || [extension isEqual:@"diff"]) return @"patch";
    if ([extension isEqual:@"zip"] || [extension isEqual:@"diatweak"]) return @"archive";
    return nil;
}

static NSString *DPLocalUnreadable(void) {
    NSString *folder = DPLocalFolder();
    NSError *error = nil;
    if ([NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:&error]) return nil;
    BOOL directory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:folder isDirectory:&directory] || !directory) return nil;
    return [NSString stringWithFormat:@"Couldn’t read %@: %@ To fix it, run: sudo chown -R \"%@\" \"%@\" && chmod -R u+rwX \"%@\"", folder,
                                      error.localizedDescription, NSUserName(), folder, folder];
}

static BOOL DPLocalWritable(NSString *folder) {
    while (folder.length > 1 && access(folder.fileSystemRepresentation, F_OK) != 0) folder = folder.stringByDeletingLastPathComponent;
    return access(folder.fileSystemRepresentation, W_OK) == 0;
}

static NSArray<NSDictionary *> *DPLocalScan(void) {
    NSString *folder = DPLocalFolder();
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (NSString *name in [[files contentsOfDirectoryAtPath:folder error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSString *path = [folder stringByAppendingPathComponent:name], *identifier = name.stringByDeletingPathExtension, *extension = name.pathExtension.lowercaseString;
        BOOL directory = NO;
        if ([name hasPrefix:@"."] || [name isEqual:@"README.md"] || [seen containsObject:identifier] || ![files fileExistsAtPath:path isDirectory:&directory]) continue;
        NSString *kind = directory || [extension isEqual:@"m"] ? @"source" : DPLocalBinaryKind(extension);
        if (!kind) continue;
        NSDictionary *item = @{ @"id" : identifier, @"kind" : kind, @"path" : path };
        if ([kind isEqual:@"source"]) {
            NSArray<NSString *> *tracked = directory ? DPLocalTracked(path) : @[ path ], *sources = DPLocalSourcesIn(tracked);
            if (!sources.count) continue;
            item = @{ @"id" : identifier, @"kind" : kind, @"path" : path, @"sources" : sources, @"tracked" : tracked, @"dir" : directory ? path : folder };
        }
        [seen addObject:identifier];
        [items addObject:item];
    }
    return items;
}

static NSString *DPLocalExtracted(NSDictionary *item) {
    return [DPLocalCacheFolder() stringByAppendingPathComponent:[NSString stringWithFormat:@"extracted/%@/%@", item[@"id"], DPLocalStamp(item[@"path"])]];
}

static NSDictionary *DPLocalSourceFields(NSString *dir, NSArray<NSString *> *tracked, NSArray<NSString *> *sources, NSString *defines) {
    NSMutableArray<NSString *> *dirs = [NSMutableArray arrayWithObject:dir];
    for (NSString *source in sources) [dirs addObject:source.stringByDeletingLastPathComponent];
    return @{ @"sources" : sources, @"tracked" : tracked, @"stamps" : DPLocalFileStamps(tracked), @"includeDirs" : dirs, @"defines" : defines };
}

static NSDictionary *DPLocalPrepare(NSDictionary *item) {
    NSString *kind = item[@"kind"], *path = item[@"path"];
    if ([kind isEqual:@"dylib"]) return @{ @"prebuilt" : path };
    if ([kind isEqual:@"source"]) return DPLocalSourceFields(item[@"dir"], item[@"tracked"], item[@"sources"], @"");
    NSString *folder = DPLocalExtracted(item), *marker = [folder stringByAppendingPathComponent:@".done"];
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
    NSArray<NSString *> *tracked = DPLocalTracked(folder), *sources = DPLocalSourcesIn(tracked);
    if (!sources.count) return @{ @"error" : @"This has no .m tweak files in it." };
    NSString *defines = [folder stringByAppendingPathComponent:@"_dp_patch_defines.h"];
    return DPLocalSourceFields(folder, tracked, sources, [files fileExistsAtPath:defines] ? defines : @"");
}

static id DPLocalFail(NSString **error, NSString *message, NSString *cleanup) {
    if (cleanup) [NSFileManager.defaultManager removeItemAtPath:cleanup error:NULL];
    *error = message;
    return nil;
}

static NSString *const DPLocalCompileRevision = @"2";

static NSString *DPLocalHash(NSDictionary *job) {
    NSMutableString *feed = [NSMutableString stringWithFormat:@"%@%@", DPDylibUUID(), DPLocalCompileRevision];
    for (NSDictionary *stamp in job[@"stamps"]) [feed appendFormat:@"%@%@:%@", stamp[@"path"], stamp[@"mtime"], stamp[@"size"]];
    NSMutableData *data = [[feed dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    if ([job[@"defines"] length]) [data appendData:[NSData dataWithContentsOfFile:job[@"defines"]] ?: NSData.data];
    return DPLocalDigest(data);
}

static NSMutableDictionary *DPLocalJob(NSDictionary *item, BOOL force) {
    NSMutableDictionary *job = [item mutableCopy];
    [job addEntriesFromDictionary:DPLocalPrepare(item)];
    if (!job[@"stamps"]) return job;
    NSFileManager *files = NSFileManager.defaultManager;
    NSDictionary *saved = DPLocalSavedItem(item[@"id"]);
    NSString *cached = saved[@"dylib"];
    if (!force && [saved[@"uuid"] isEqual:DPDylibUUID()] && DPLocalStampsMatch(saved[@"files"], job[@"stamps"], [job[@"tracked"] count])
        && [cached isKindOfClass:NSString.class] && [files fileExistsAtPath:cached]) {
        job[@"dylib"] = cached;
        return job;
    }
    NSString *output = [DPLocalCacheFolder() stringByAppendingPathComponent:[NSString stringWithFormat:@"bin/%@-%@.dylib", item[@"id"], DPLocalHash(job)]];
    if (!force && [files fileExistsAtPath:output]) job[@"dylib"] = output;
    else job[@"output"] = output;
    return job;
}

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
    NSString *copy = [folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.dylib", identifier, DPLocalStamp(path)]];
    if ([files fileExistsAtPath:copy]) return copy;
    NSString *temporary = [copy stringByAppendingString:@".tmp"];
    [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    [files removeItemAtPath:temporary error:NULL];
    if (![files copyItemAtPath:path toPath:temporary error:NULL]) return DPLocalFail(error, @"Couldn’t copy it into the cache.", nil);
    removexattr(temporary.fileSystemRepresentation, "com.apple.quarantine", 0);
    if (!DPLocalRun(@[ @"/usr/bin/codesign", @"--force", @"--sign", @"-", temporary ]))
        return DPLocalFail(error, @"Couldn’t sign it, so macOS won’t load it.", temporary);
    if (rename(temporary.fileSystemRepresentation, copy.fileSystemRepresentation) != 0)
        return DPLocalFail(error, @"Couldn’t put the signed tweak in place.", temporary);
    return copy;
}

static void DPLocalMake(NSMutableDictionary *job, NSString *pch) {
    NSString *error = nil, *output = job[@"output"];
    if (job[@"prebuilt"]) {
        NSString *dylib = DPLocalPrepareDylib(job[@"prebuilt"], job[@"id"], &error);
        [job addEntriesFromDictionary:dylib ? @{ @"dylib" : dylib } : @{ @"status" : @"incompatible", @"error" : error }];
        return;
    }
    if (!output) return;
    NSString *temporary = [output stringByAppendingString:@".tmp"];
    [NSFileManager.defaultManager createDirectoryAtPath:output.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [NSFileManager.defaultManager removeItemAtPath:temporary error:NULL];
    // Rename over the old file: a running Dia may still have it mapped, and rename never disturbs that.
    if (DPLocalCompile(job[@"sources"], job[@"includeDirs"], job[@"defines"], pch, temporary, &error)
        && rename(temporary.fileSystemRepresentation, output.fileSystemRepresentation) == 0) {
        job[@"dylib"] = output;
        return;
    }
    [NSFileManager.defaultManager removeItemAtPath:temporary error:NULL];
    [job addEntriesFromDictionary:@{ @"status" : @"failed", @"error" : error ?: @"Couldn’t put the built tweak in place." }];
}

static NSArray<NSMutableDictionary *> *DPLocalJobs(NSArray<NSDictionary *> *items, BOOL force) {
    NSMutableArray<NSMutableDictionary *> *jobs = [NSMutableArray new], *compiles = [NSMutableArray new];
    for (NSDictionary *item in items) {
        NSMutableDictionary *job = DPLocalJob(item, force);
        [jobs addObject:job];
        if (job[@"output"]) [compiles addObject:job];
    }
    NSString *error = nil, *pch = nil;
    if (compiles.count && DPLocalToolchain(&error) && DPLocalHeaders(&error)) pch = DPLocalEnsurePCH(compiles.count >= 2);
    else
        for (NSMutableDictionary *job in compiles) {
            [job removeObjectForKey:@"output"];
            [job addEntriesFromDictionary:@{ @"status" : @"failed", @"error" : error }];
        }
    void (^make)(size_t) = ^(size_t i) {
        @autoreleasepool {
            DPLocalMake(jobs[i], pch);
        }
    };
    if (compiles.count >= 2) dispatch_apply(jobs.count, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), make);
    else for (size_t i = 0; i < jobs.count; i++) make(i);
    return jobs;
}

static const struct mach_header_64 *DPLocalImageFor(NSString *path) {
    char want[PATH_MAX];
    if (!realpath(path.fileSystemRepresentation, want)) return NULL;
    for (uint32_t i = _dyld_image_count(); i-- > 0;) {
        const char *name = _dyld_get_image_name(i);
        if (name && !strcmp(name, want)) return (const void *)_dyld_get_image_header(i);
    }
    return NULL;
}

static NSArray<NSValue *> *DPLocalOpen(NSString *dylib, NSString **error) {
    void *handle = dlopen(dylib.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) return DPLocalFail(error, [NSString stringWithFormat:@"Couldn’t load it: %s", dlerror()], nil);
    const struct mach_header_64 *header = DPLocalImageFor(dylib);
    if (!header) return DPLocalFail(error, @"Couldn’t find the loaded tweak.", nil);
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

NSSet<NSString *> *DPLocalOfficialKeySet(void) {
    if (DPLocalOfficialKeys) return DPLocalOfficialKeys;
    NSMutableSet<NSString *> *keys = [NSMutableSet new];
    unsigned long size = 0;
    DPPatch **entries = (DPPatch **)getsectiondata(&__dso_handle, "__DATA", "__dppatches", &size);
    for (NSUInteger i = 0; entries && i < size / sizeof *entries; i++)
        if (entries[i]->key) [keys addObject:entries[i]->key];
    DPLocalOfficialKeys = keys;
    return keys;
}

static NSDictionary *DPLocalRecord(NSDictionary *job, NSArray<NSDictionary *> *patches, NSString *status, NSString *error, NSString *dylib) {
    NSMutableDictionary *record = [@{
        @"id" : job[@"id"],
        @"kind" : job[@"kind"],
        @"path" : job[@"path"],
        @"status" : status,
        @"patches" : patches,
        @"uuid" : DPDylibUUID(),
    } mutableCopy];
    record[@"error"] = error;
    record[@"dylib"] = dylib;
    if ([job[@"tracked"] count]) record[@"files"] = job[@"stamps"];
    return record;
}

static NSDictionary *DPLocalPatchRecord(DPPatch *patch) {
    return @{
        @"key" : patch->key,
        @"title" : patch->title,
        @"symbol" : patch->symbol ?: @"",
        @"tint" : patch->tint ?: @"systemOrangeColor",
        @"section" : patch->section ?: (patch->requires ? NSNull.null : @"Local"),
        @"detail" : patch->detail ?: @"",
        @"defaultOn" : @(patch->defaultOn),
        @"requires" : patch->requires ?: NSNull.null,
        @"disabledBy" : patch->disabledBy ?: NSNull.null,
        @"coveredBy" : patch->coveredBy ?: NSNull.null,
        @"relaunch" : @(patch->relaunch),
    };
}

static BOOL DPLocalUnchanged(NSDictionary *saved, NSDictionary *job) {
    NSUInteger count = [job[@"tracked"] count];
    return [saved[@"uuid"] isEqual:DPDylibUUID()]
           && (count ? DPLocalStampsMatch(saved[@"files"], job[@"stamps"], count) : [job[@"dylib"] isEqual:saved[@"dylib"]]);
}

static NSDictionary *DPLocalReuse(NSDictionary *saved, NSDictionary *job, NSMutableSet<NSString *> *taken, NSUInteger *total) {
    if (!DPLocalUnchanged(saved, job) || saved[@"error"] || ![@[ @"loaded", @"ready" ] containsObject:saved[@"status"]]) return nil;
    if (![saved[@"kind"] isEqual:job[@"kind"]] || ![saved[@"path"] isEqual:job[@"path"]] || ![saved[@"dylib"] isEqual:job[@"dylib"]]) return nil;
    NSArray *patches = saved[@"patches"];
    if (![patches isKindOfClass:NSArray.class] || !patches.count) return nil;
    NSArray<NSString *> *keys = [patches valueForKey:@"key"];
    if (*total + keys.count > 64 || [taken intersectsSet:[NSSet setWithArray:keys]]) return nil;
    [taken addObjectsFromArray:keys];
    *total += keys.count;
    return saved;
}

static NSDictionary *DPLocalAccept(NSDictionary *job, NSMutableSet<NSString *> *taken, NSUInteger *total, BOOL splice, BOOL force) {
    NSString *dylib = job[@"dylib"], *error = nil;
    if (!dylib) return DPLocalRecord(job, @[], job[@"status"] ?: @"failed", job[@"error"], nil);
    NSDictionary *saved = DPLocalSavedItem(job[@"id"]), *reused = splice || force ? nil : DPLocalReuse(saved, job, taken, total);
    if (reused) return reused;
    NSArray<NSValue *> *patches = DPLocalOpen(dylib, &error);
    if (!patches) return DPLocalRecord(job, @[], @"incompatible", error, dylib);

    NSMutableArray<NSValue *> *accepted = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *records = [NSMutableArray new];
    NSMutableArray<NSString *> *problems = [NSMutableArray new];
    for (NSValue *value in patches) {
        DPPatch *patch = value.pointerValue;
        if (!patch->key.length || !patch->title.length) {
            [problems addObject:@"A tweak in it has no key or title."];
            continue;
        }
        if (*total + accepted.count >= 64) {
            [problems addObject:@"DiaTweaks runs at most 64 local tweaks."];
            break;
        }
        if ([taken containsObject:patch->key]) {
            [problems addObject:[NSString stringWithFormat:@"It uses the key “%@”, which DiaTweaks already has.", patch->key]];
            continue;
        }
        if (splice) {
            if (!patch->section && !patch->requires) patch->section = @"Local";
            if (!patch->tint) patch->tint = @"systemOrangeColor";
            if (patch->order <= 0) patch->order = 100000 + (int)(*total + accepted.count);
        }
        [taken addObject:patch->key];
        [accepted addObject:value];
        [records addObject:DPLocalPatchRecord(patch)];
    }
    if (!accepted.count) return DPLocalRecord(job, @[], @"failed", problems.firstObject ?: @"It has no tweaks in it.", dylib);

    *total += accepted.count;
    if (splice)
        for (NSValue *value in accepted) {
            DPNoteLocalPatch(value.pointerValue, job[@"id"], nil);
            [DPLocalTable addObject:value];
        }
    NSString *status = splice || ([saved[@"status"] isEqual:@"loaded"] && DPLocalUnchanged(saved, job)) ? @"loaded" : @"ready";
    return DPLocalRecord(job, records, status, problems.count ? [problems componentsJoinedByString:@" "] : nil, dylib);
}

NSUInteger DPLocalLoad(void) {
    if (DPLocalLoaded) return DPLocalArrayCount;
    DPLocalLoaded = YES;
    if (!DPLocalTweaksEnabled()) return 0;
    NSArray<NSDictionary *> *items = DPLocalScan();
    if (!items.count) return 0;
    DPLocalTable = [NSMutableArray new];
    DPLocalSaved = DPLocalReadState();
    NSMutableSet<NSString *> *taken = [DPLocalOfficialKeySet() mutableCopy];
    NSUInteger total = 0;
    NSMutableArray<NSDictionary *> *state = [NSMutableArray new];
    for (NSDictionary *job in DPLocalJobs(items, NO)) [state addObject:DPLocalAccept(job, taken, &total, YES, NO)];
    DPLocalPack();
    DPLocalStateItems = state;
    DPLocalSaved = DPLocalUpdateState(state, DPLocalSaved);
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
    DPLocalSaved = DPLocalUpdateState(DPLocalStateItems, DPLocalSaved);
}

NSArray<NSDictionary *> *DPLocalItems(void) {
    NSMutableDictionary<NSString *, NSDictionary *> *saved = [NSMutableDictionary new];
    for (NSDictionary *item in DPLocalReadState()[@"items"])
        if (item[@"id"]) saved[item[@"id"]] = item;
    NSMutableArray<NSDictionary *> *items = [NSMutableArray new];
    for (NSDictionary *item in DPLocalScan())
        [items addObject:saved[item[@"id"]] ?: @{ @"id" : item[@"id"], @"kind" : item[@"kind"], @"path" : item[@"path"], @"status" : @"ready", @"patches" : @[] }];
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

static void DPLocalPruneIn(NSString *folder, BOOL (^stale)(NSString *path)) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in [files contentsOfDirectoryAtPath:folder error:NULL]) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if (![name hasSuffix:@".tmp"] && stale(path)) [files removeItemAtPath:path error:NULL];
    }
}

static void DPLocalPrune(NSArray<NSDictionary *> *items, NSArray<NSDictionary *> *state) {
    NSString *cache = DPLocalCacheFolder();
    NSMutableSet<NSString *> *keep = [NSMutableSet setWithObject:[cache stringByAppendingPathComponent:[@"headers" stringByAppendingPathComponent:DPDylibUUID()]]];
    for (NSArray<NSDictionary *> *records in @[ DPLocalSaved[@"items"] ?: @[], state ])
        for (NSDictionary *record in records)
            if ([record[@"dylib"] isKindOfClass:NSString.class]) [keep addObject:record[@"dylib"]];
    NSMutableArray<NSString *> *folders = [@[ @"headers", @"bin", @"dylibs", @"extracted" ] mutableCopy];
    for (NSDictionary *item in items) {
        if ([item[@"kind"] isEqual:@"source"] || [item[@"kind"] isEqual:@"dylib"]) continue;
        NSString *extracted = DPLocalExtracted(item);
        [keep addObjectsFromArray:@[ extracted, extracted.stringByDeletingLastPathComponent ]];
        [folders addObject:[@"extracted" stringByAppendingPathComponent:item[@"id"]]];
    }
    for (NSString *folder in folders)
        DPLocalPruneIn([cache stringByAppendingPathComponent:folder], ^BOOL(NSString *path) { return ![keep containsObject:path]; });
    DPLocalPruneIn([cache stringByAppendingPathComponent:@"staging"], ^BOOL(NSString *path) {
        return [[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL].fileModificationDate timeIntervalSinceNow] < -600;
    });
}

BOOL DPLocalBuildAllForced(NSArray<NSString *> *names, BOOL force, NSString **report) {
    NSString *unreadable = DPLocalUnreadable();
    if (unreadable) {
        if (report) *report = unreadable;
        return NO;
    }
    DPLocalSaved = DPLocalReadState();
    NSArray<NSDictionary *> *items = DPLocalScan();
    NSMutableSet<NSString *> *taken = [DPLocalOfficialKeySet() mutableCopy];
    NSUInteger total = 0;
    NSMutableArray<NSDictionary *> *targets = [NSMutableArray new];
    for (NSDictionary *item in items) {
        if (!names.count || [names containsObject:item[@"id"]]) {
            [targets addObject:item];
            continue;
        }
        NSArray<NSDictionary *> *patches = DPLocalSavedItem(item[@"id"])[@"patches"];
        for (NSDictionary *patch in patches) if (patch[@"key"]) [taken addObject:patch[@"key"]];
        total += patches.count;
    }
    NSEnumerator<NSMutableDictionary *> *jobs = DPLocalJobs(targets, force).objectEnumerator;
    NSMutableArray<NSDictionary *> *state = [NSMutableArray new];
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    BOOL ok = YES;
    for (NSDictionary *item in items) {
        if (names.count && ![names containsObject:item[@"id"]]) {
            NSDictionary *saved = DPLocalSavedItem(item[@"id"]);
            if (saved) [state addObject:saved];
            continue;
        }
        NSDictionary *record = DPLocalAccept(jobs.nextObject, taken, &total, NO, force);
        [state addObject:record];
        ok &= [record[@"status"] isEqual:@"loaded"] || [record[@"status"] isEqual:@"ready"];
        [lines addObject:DPLocalDescribe(record)];
    }
    if (!names.count) DPLocalPrune(items, state);
    DPLocalSaved = DPLocalUpdateState(state, DPLocalSaved);
    if (![DPLocalSaved[@"items"] isEqual:state])
        [lines addObject:[NSString stringWithFormat:@"Couldn’t save the build results to %@; check that folder’s permissions and ownership.", DPLocalStatePath()]];
    if (report) *report = lines.count ? [lines componentsJoinedByString:@"\n"] : @"There are no local tweaks to build.";
    return ok;
}

BOOL DPLocalBuildAll(NSArray<NSString *> *names, NSString **report) { return DPLocalBuildAllForced(names, NO, report); }

BOOL DPLocalBuildNames(NSArray<NSString *> *names, BOOL force, NSString **report) {
    NSString *tool = [DPAppSupport(@"DiaPatches") stringByAppendingPathComponent:@"bin/diapatch"];
    if (getenv("DIAPATCH_LOCAL_BUILD") || ![NSFileManager.defaultManager isExecutableFileAtPath:tool]) return DPLocalBuildAllForced(names, force, report);
    NSMutableArray<NSString *> *command = [@[ tool, @"local", @"build" ] mutableCopy];
    if (force) [command addObject:@"--force"];
    [command addObjectsFromArray:names ?: @[]];
    BOOL ok = DPLocalExec(command, report) == 0;
    if (!(*report).length && !ok) *report = @"diapatch couldn’t build your local tweaks.";
    return ok;
}

BOOL DPLocalBuild(BOOL force, NSString **report) { return DPLocalBuildNames(nil, force, report); }

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
    else if (toolchain) DPLocalEnsurePCH(YES);
    for (NSArray<NSString *> *row in @[ @[ @"support", DPAppSupport(@"DiaPatches") ], @[ @"local", DPLocalFolder() ] ]) {
        BOOL writable = DPLocalWritable(row[1]);
        printf("%-11s%s (%s)\n", row[0].UTF8String, row[1].UTF8String, writable ? "writable" : "not writable; check its permissions and ownership");
        ok &= writable;
    }
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

static NSDictionary *DPLocalMatchCatalog(NSArray<NSDictionary *> *catalog, NSString *query) {
    for (NSDictionary *entry in catalog) {
        NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:entry[@"id"]];
        for (NSDictionary *patch in entry[@"patches"]) [names addObjectsFromArray:@[ patch[@"key"], patch[@"title"] ]];
        for (NSString *name in names)
            if ([name caseInsensitiveCompare:query] == NSOrderedSame) return entry;
    }
    return nil;
}

static BOOL DPLocalPrintAvailable(void) {
    NSString *error = nil;
    NSArray<NSDictionary *> *catalog = DPLocalFetchCatalog(&error) ?: DPLocalCachedCatalog();
    if (!catalog) {
        fprintf(stderr, "%s\n", error.UTF8String);
        return NO;
    }
    NSArray<NSDictionary *> *items = DPLocalItems(), *available = DPLocalAvailableCatalogForItems(catalog, items);
    if (!available.count) {
        printf("No optional tweaks are available yet.\n");
        return YES;
    }
    for (NSDictionary *entry in available) {
        NSDictionary *primary = DPLocalPrimaryPatch(entry);
        printf("%s  %s%s\n    %s\n", [entry[@"id"] UTF8String], [primary[@"title"] UTF8String],
               DPLocalIsCatalogItemInstalled(entry, items) ? "  (installed)" : "", [primary[@"detail"] UTF8String] ?: "");
    }
    return YES;
}

static BOOL DPLocalInstallNamed(NSArray<NSString *> *queries) {
    if (!queries.count) {
        fprintf(stderr, "usage: diapatch local install <name>...\n");
        return NO;
    }
    NSString *error = nil;
    NSArray<NSDictionary *> *catalog = DPLocalFetchCatalog(&error);
    if (!catalog) {
        fprintf(stderr, "%s\n", error.UTF8String);
        return NO;
    }
    NSMutableArray<NSDictionary *> *entries = [NSMutableArray new];
    for (NSString *query in queries) {
        NSDictionary *entry = DPLocalMatchCatalog(catalog, query);
        if (!entry) {
            fprintf(stderr, "No optional tweak matching “%s”. Run 'diatweaks local available' to see the list.\n", query.UTF8String);
            return NO;
        }
        if (DPLocalIsBuiltIn(entry)) {
            fprintf(stderr, "%s is already built into this DiaTweaks.\n", [DPLocalPrimaryPatch(entry)[@"title"] UTF8String]);
            return NO;
        }
        [entries addObject:entry];
    }
    if (!DPLocalInstallCatalogItems(entries, &error)) {
        fprintf(stderr, "%s\n", error.UTF8String);
        return NO;
    }
    for (NSDictionary *entry in entries) printf("Installed %s — relaunch Dia to load it.\n", [DPLocalPrimaryPatch(entry)[@"title"] UTF8String]);
    return YES;
}

BOOL DPLocalBuildMain(NSArray<NSString *> *arguments) {
    NSMutableArray<NSString *> *rest = [arguments mutableCopy];
    while (rest.count && ![rest[0] isEqual:@"local"]) [rest removeObjectAtIndex:0];
    if (rest.count) [rest removeObjectAtIndex:0];
    NSString *action = rest.count && ![rest[0] hasPrefix:@"-"] ? rest[0] : @"list";
    if (rest.count && ![rest[0] hasPrefix:@"-"]) [rest removeObjectAtIndex:0];
    if ([action isEqual:@"build"]) {
        BOOL force = [rest containsObject:@"--force"];
        [rest removeObject:@"--force"];
        NSString *report = nil;
        BOOL ok = DPLocalBuildAllForced(rest, force, &report);
        printf("%s\n", report.UTF8String);
        return ok;
    }
    if ([action isEqual:@"doctor"]) return DPLocalDoctor();
    if ([action isEqual:@"available"] || [action isEqual:@"catalog"]) return DPLocalPrintAvailable();
    if ([action isEqual:@"install"]) return DPLocalInstallNamed(rest);
    NSString *unreadable = DPLocalUnreadable();
    if (unreadable) {
        fprintf(stderr, "%s\n", unreadable.UTF8String);
        return NO;
    }
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
    for (int i = 2; i < 1000 && [files fileExistsAtPath:destination]; i++) {
        NSString *numbered = [NSString stringWithFormat:@"%@ %d", name.stringByDeletingPathExtension, i];
        destination = [folder stringByAppendingPathComponent:name.pathExtension.length ? [numbered stringByAppendingPathExtension:name.pathExtension] : numbered];
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
    NSString *readme = [DPLocalFolder() stringByAppendingPathComponent:@"README.md"];
    [NSFileManager.defaultManager createDirectoryAtPath:DPLocalFolder() withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![NSFileManager.defaultManager fileExistsAtPath:readme]) [DPLocalReadme writeToFile:readme atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
