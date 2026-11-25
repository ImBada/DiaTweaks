#import "Local/Local.h"
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>

extern const struct mach_header_64 __dso_handle;

NSString *DPLocalDigest(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:16];
    for (int i = 0; i < 8; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *DPLocalImageUUID(void) {
    const struct load_command *command = (const void *)(&__dso_handle + 1);
    for (uint32_t i = 0; i < __dso_handle.ncmds; i++, command = (const void *)((const uint8_t *)command + command->cmdsize))
        if (command->cmd == LC_UUID) return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
    return @"unknown";
}

NSString *DPDylibUUID(void) {
    const char *override = getenv("DIAPATCH_DYLIB_UUID");
    if (override && *override) return @(override);
    static NSString *uuid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        unsigned long size = 0;
        const uint8_t *headers = getsectiondata(&__dso_handle, "__TEXT", "__dp_headers", &size);
        uuid = headers ? DPLocalDigest([NSData dataWithBytesNoCopy:(void *)headers length:size freeWhenDone:NO]) : DPLocalImageUUID();
    });
    return uuid;
}

static BOOL DPLocalTake(const uint8_t **cursor, const uint8_t *end, void *value, size_t length) {
    if ((size_t)(end - *cursor) < length) return NO;
    if (value) memcpy(value, *cursor, length);
    *cursor += length;
    return YES;
}

NSString *DPLocalHeaders(NSString **error) {
    NSString *folder = [DPLocalCacheFolder() stringByAppendingPathComponent:[@"headers" stringByAppendingPathComponent:DPDylibUUID()]];
    NSString *marker = [folder stringByAppendingPathComponent:@".done"];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:marker]) return folder;
    unsigned long size = 0;
    const uint8_t *cursor = getsectiondata(&__dso_handle, "__TEXT", "__dp_headers", &size);
    uint32_t count = 0;
    if (!cursor || size < sizeof count) {
        *error = @"This DiaPatches has no headers inside it, so it can’t compile .m tweaks. Reinstall DiaTweaks.";
        return nil;
    }
    const uint8_t *end = cursor + size;
    DPLocalTake(&cursor, end, &count, sizeof count);
    [files removeItemAtPath:folder error:NULL];
    BOOL ok = YES;
    for (uint32_t i = 0; ok && i < count; i++) {
        uint16_t pathLength = 0;
        uint32_t contentLength = 0;
        ok = DPLocalTake(&cursor, end, &pathLength, sizeof pathLength);
        const uint8_t *name = cursor;
        ok = ok && DPLocalTake(&cursor, end, NULL, pathLength) && DPLocalTake(&cursor, end, &contentLength, sizeof contentLength)
             && (size_t)(end - cursor) >= contentLength;
        NSString *relative = ok ? [[NSString alloc] initWithBytes:name length:pathLength encoding:NSUTF8StringEncoding] : nil;
        NSString *path = [folder stringByAppendingPathComponent:relative ?: @""];
        ok = relative && [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]
             && [[NSData dataWithBytesNoCopy:(void *)cursor length:contentLength freeWhenDone:NO] writeToFile:path atomically:NO];
        cursor += ok ? contentLength : 0;
    }
    if (ok && [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:NULL]) return folder;
    [files removeItemAtPath:folder error:NULL];
    *error = @"Couldn’t write DiaTweaks’ headers into ~/Library/Caches/DiaPatches. Free some space or fix its permissions, then try again.";
    return nil;
}

static NSDictionary *DPLocalToolchainCache;

NSDictionary *DPLocalToolchainSaved(void) { return DPLocalToolchainCache; }

static NSArray<NSString *> *DPLocalSelectedToolchain(void) {
    char developer[PATH_MAX];
    if (getenv("DEVELOPER_DIR") || !realpath("/var/db/xcode_select_link", developer)) return nil;
    NSString *root = @(developer);
    BOOL tools = [root hasSuffix:@"/CommandLineTools"];
    return @[
        [root stringByAppendingPathComponent:tools ? @"usr/bin/clang" : @"Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"],
        [root stringByAppendingPathComponent:tools ? @"SDKs/MacOSX.sdk" : @"Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"],
    ];
}

NSDictionary *DPLocalToolchain(NSString **error) {
    if (DPLocalToolchainCache) return DPLocalToolchainCache;
    NSFileManager *files = NSFileManager.defaultManager;
    const char *override = getenv("DIAPATCH_CLANG");
    NSDictionary *saved = DPLocalSavedValue(@"toolchain");
    if (![saved isKindOfClass:NSDictionary.class]) saved = @{};
    NSString *clang = override && *override ? @(override) : nil, *sdk = nil;
    if (!clang && [saved[@"clang"] isKindOfClass:NSString.class] && [files isExecutableFileAtPath:saved[@"clang"]]) clang = saved[@"clang"];
    if ([saved[@"sdk"] isKindOfClass:NSString.class] && [files fileExistsAtPath:saved[@"sdk"]]) sdk = saved[@"sdk"];
    NSArray<NSString *> *selected = clang && sdk ? nil : DPLocalSelectedToolchain();
    if (!clang && selected && [files isExecutableFileAtPath:selected[0]]) clang = selected[0];
    if (!sdk && selected && [files fileExistsAtPath:selected[1]]) sdk = selected[1];
    if (!clang) clang = DPLocalRun(@[ @"/usr/bin/xcrun", @"--find", @"clang" ]);
    if (!sdk) sdk = DPLocalRun(@[ @"/usr/bin/xcrun", @"--show-sdk-path" ]);
    if (!clang.length || !sdk.length) {
        *error = @"Install Xcode Command Line Tools (xcode-select --install) to compile .m tweaks, or use a prebuilt .dylib.";
        return nil;
    }
    DPLocalToolchainCache = @{ @"clang" : clang, @"sdk" : sdk };
    return DPLocalToolchainCache;
}

static NSMutableArray<NSString *> *DPLocalClang(NSDictionary *toolchain, NSString *headers) {
    return [@[
        toolchain[@"clang"], @"-arch", @"arm64", @"-mmacosx-version-min=14.0", @"-fobjc-arc", @"-O2", @"-Wall", @"-Wno-unused-parameter",
        @"-DDP_LOCAL_TWEAK=1", @"-isysroot", toolchain[@"sdk"], @"-I", headers,
    ] mutableCopy];
}

NSString *DPLocalEnsurePCH(BOOL buildIfMissing) {
    NSString *error = nil;
    NSDictionary *toolchain = DPLocalToolchain(&error);
    NSString *headers = toolchain ? DPLocalHeaders(&error) : nil;
    if (!headers) return nil;
    NSString *key = [@[ toolchain[@"clang"], DPLocalStamp(toolchain[@"clang"]), toolchain[@"sdk"], DPLocalStamp(toolchain[@"sdk"]) ] componentsJoinedByString:@"\n"];
    NSString *pch = [headers stringByAppendingPathComponent:[NSString stringWithFormat:@"dp-%@.pch", DPLocalDigest([key dataUsingEncoding:NSUTF8StringEncoding])]];
    if (access(pch.fileSystemRepresentation, F_OK) == 0) return pch;
    if (!buildIfMissing) return nil;
    NSString *temporary = [pch stringByAppendingFormat:@".tmp.%d", getpid()], *output = nil;
    NSMutableArray<NSString *> *arguments = DPLocalClang(toolchain, headers);
    [arguments addObjectsFromArray:@[ @"-x", @"objective-c-header", [headers stringByAppendingPathComponent:@"StdPatch/StdPatch.h"], @"-o", temporary ]];
    if (DPLocalExec(arguments, &output) == 0 && rename(temporary.fileSystemRepresentation, pch.fileSystemRepresentation) == 0) return pch;
    unlink(temporary.fileSystemRepresentation);
    return nil;
}

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

BOOL DPLocalCompile(NSArray<NSString *> *sources, NSArray<NSString *> *includeDirs, NSString *defines, NSString *pch, NSString *output, NSString **error) {
    NSDictionary *toolchain = DPLocalToolchain(error);
    NSString *headers = toolchain ? DPLocalHeaders(error) : nil;
    if (!headers) return NO;
    NSMutableArray<NSString *> *arguments = DPLocalClang(toolchain, headers);
    for (NSString *folder in includeDirs) [arguments addObjectsFromArray:@[ @"-I", folder ]];
    if (defines.length) [arguments addObjectsFromArray:@[ @"-include", defines ]];
    else if (pch.length) [arguments addObjectsFromArray:@[ @"-include-pch", pch ]];
    [arguments addObjectsFromArray:@[
        @"-dynamiclib", @"-undefined", @"dynamic_lookup", @"-Wl,-dead_strip_dylibs",
        @"-framework", @"Foundation", @"-framework", @"AppKit", @"-framework", @"QuartzCore",
        @"-framework", @"Metal", @"-framework", @"Carbon",
        @"-o", output,
    ]];
    [arguments addObjectsFromArray:sources];
    NSString *text = nil;
    int status = DPLocalExec(arguments, &text);
    if (status == 0) return YES;
    if (status > 0 && !defines.length && pch.length && [text containsString:pch]) {
        unlink(pch.fileSystemRepresentation);
        return DPLocalCompile(sources, includeDirs, defines, nil, output, error);
    }
    *error = status < 0 ? @"Couldn’t run clang." : DPLocalDiagnostics(text ?: @"", sources, includeDirs);
    return NO;
}
