#import "Local/Local.h"
#import <mach-o/getsect.h>
#import <mach-o/loader.h>

extern const struct mach_header_64 __dso_handle;

NSString *DPDylibUUID(void) {
    // Tests change this to pretend a DiaTweaks update happened.
    const char *override = getenv("DIAPATCH_DYLIB_UUID");
    if (override && *override) return @(override);
    static NSString *uuid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const struct mach_header_64 *header = &__dso_handle;
        const struct load_command *command = (const void *)(header + 1);
        for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const uint8_t *)command + command->cmdsize))
            if (command->cmd == LC_UUID) {
                uuid = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
                break;
            }
        if (!uuid) uuid = @"unknown";
    });
    return uuid;
}

NSString *DPLocalHeaders(NSString **error) {
    NSString *folder = [DPLocalCacheFolder() stringByAppendingPathComponent:[NSString stringWithFormat:@"headers/%@", DPDylibUUID()]];
    NSString *marker = [folder stringByAppendingPathComponent:@".done"];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:marker]) return folder;

    unsigned long size = 0;
    const uint8_t *blob = getsectiondata(&__dso_handle, "__TEXT", "__dp_headers", &size);
    if (!blob || size < 4) {
        *error = @"This DiaPatches has no headers inside it, so it can’t compile .m tweaks. Reinstall DiaTweaks.";
        return nil;
    }
    [files removeItemAtPath:folder error:NULL];
    if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]) {
        *error = @"Couldn’t create the header folder.";
        return nil;
    }
    uint32_t count = 0;
    memcpy(&count, blob, sizeof count);
    unsigned long offset = sizeof count;
    for (uint32_t i = 0; i < count; i++) {
        if (offset + sizeof(uint16_t) > size) break;
        uint16_t pathLength = 0;
        memcpy(&pathLength, blob + offset, sizeof pathLength);
        offset += sizeof pathLength;
        if (offset + pathLength + sizeof(uint32_t) > size) break;
        NSString *relative = [[NSString alloc] initWithBytes:blob + offset length:pathLength encoding:NSUTF8StringEncoding];
        offset += pathLength;
        uint32_t contentLength = 0;
        memcpy(&contentLength, blob + offset, sizeof contentLength);
        offset += sizeof contentLength;
        if (offset + contentLength > size) break;
        NSString *path = [folder stringByAppendingPathComponent:relative];
        [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NSData dataWithBytes:blob + offset length:contentLength] writeToFile:path atomically:YES];
        offset += contentLength;
    }
    [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return folder;
}

static NSDictionary *DPLocalToolchainCache;

NSDictionary *DPLocalToolchainSaved(void) { return DPLocalToolchainCache; }

NSDictionary *DPLocalToolchain(NSString **error) {
    if (DPLocalToolchainCache) return DPLocalToolchainCache;
    NSFileManager *files = NSFileManager.defaultManager;
    const char *override = getenv("DIAPATCH_CLANG");
    NSString *clang = override && *override ? @(override) : nil;
    id saved = DPLocalSavedValue(@"toolchain");
    if (![saved isKindOfClass:NSDictionary.class]) saved = @{};
    NSString *sdk = nil;
    if (!clang && [saved[@"clang"] isKindOfClass:NSString.class] && [files isExecutableFileAtPath:saved[@"clang"]]) clang = saved[@"clang"];
    if ([saved[@"sdk"] isKindOfClass:NSString.class] && [files fileExistsAtPath:saved[@"sdk"]]) sdk = saved[@"sdk"];
    if (!clang) clang = DPLocalRun(@[ @"/usr/bin/xcrun", @"--find", @"clang" ]);
    if (!sdk) sdk = DPLocalRun(@[ @"/usr/bin/xcrun", @"--show-sdk-path" ]);
    if (!clang.length || !sdk.length) {
        *error = @"Install Xcode Command Line Tools (xcode-select --install) to compile .m tweaks, or use a prebuilt .dylib.";
        return nil;
    }
    DPLocalToolchainCache = @{ @"clang" : clang, @"sdk" : sdk };
    return DPLocalToolchainCache;
}

// Compiler output names the cache folder, which means nothing to the person who wrote the tweak.
static NSString *DPLocalDiagnostics(NSString *text, NSArray<NSString *> *sources, NSArray<NSString *> *includeDirs) {
    NSMutableArray<NSString *> *folders = [NSMutableArray arrayWithArray:includeDirs];
    for (NSString *source in sources) [folders addObject:source.stringByDeletingLastPathComponent];
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!trimmed.length) continue;
        for (NSString *folder in folders) trimmed = [trimmed stringByReplacingOccurrencesOfString:[folder stringByAppendingString:@"/"] withString:@""];
        [lines addObject:trimmed];
        if (lines.count == 6) break;
    }
    return lines.count ? [lines componentsJoinedByString:@"\n"] : @"clang couldn’t build it.";
}

BOOL DPLocalCompile(NSArray<NSString *> *sources, NSArray<NSString *> *includeDirs, NSString *defines, NSString *output, NSString **error) {
    NSDictionary *toolchain = DPLocalToolchain(error);
    if (!toolchain) return NO;
    NSString *headers = DPLocalHeaders(error);
    if (!headers) return NO;
    NSMutableArray<NSString *> *arguments = [@[
        @"-arch", @"arm64", @"-mmacosx-version-min=14.0", @"-fobjc-arc", @"-O2", @"-Wall", @"-Wno-unused-parameter",
        @"-DDP_LOCAL_TWEAK=1", @"-isysroot", toolchain[@"sdk"], @"-I", headers,
    ] mutableCopy];
    for (NSString *folder in includeDirs) [arguments addObjectsFromArray:@[ @"-I", folder ]];
    if (defines.length) [arguments addObjectsFromArray:@[ @"-include", defines ]];
    [arguments addObjectsFromArray:@[
        @"-dynamiclib", @"-undefined", @"dynamic_lookup",
        @"-framework", @"Foundation", @"-framework", @"AppKit", @"-framework", @"QuartzCore",
        @"-o", output,
    ]];
    [arguments addObjectsFromArray:sources];

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:toolchain[@"clang"]];
    task.arguments = arguments;
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = task.standardError = pipe;
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:NULL]) {
        *error = @"Couldn’t run clang.";
        return NO;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus == 0) return YES;
    *error = DPLocalDiagnostics([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"", sources, includeDirs);
    return NO;
}
