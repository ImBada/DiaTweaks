#import "Local/Local.h"
#import <sys/stat.h>

static BOOL DPLocalIsPlumbing(NSString *path) {
    for (NSString *prefix in @[ @"Makefile", @".github/", @"tests/", @"docs/", @"README.md", @"CONTRIBUTING.md", @"cli/", @"scripts/", @"tweaks/index.json", @"tweaks/README.md" ])
        if ([path isEqual:prefix] || [path hasPrefix:prefix]) return YES;
    return NO;
}

static BOOL DPLocalIsSafePath(NSString *path) {
    if (!path.length || [path hasPrefix:@"/"]) return NO;
    for (NSString *part in [path componentsSeparatedByString:@"/"])
        if ([part isEqual:@".."]) return NO;
    return YES;
}

static BOOL DPLocalIsInside(NSString *path, NSString *folder) {
    NSString *root = folder.stringByStandardizingPath;
    return [path.stringByStandardizingPath hasPrefix:[root stringByAppendingString:@"/"]];
}

static BOOL DPLocalIsIdentifier(NSString *name) {
    if (!name.length) return NO;
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        BOOL letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
        if (!letter && (i == 0 || c < '0' || c > '9')) return NO;
    }
    return YES;
}

void DPLocalExtractPatch(NSString *patch, NSString *folder, NSString **error) {
    NSString *text = [NSString stringWithContentsOfFile:patch encoding:NSUTF8StringEncoding error:NULL];
    if (!text) {
        *error = @"Couldn’t read the patch.";
        return;
    }
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *defines = [NSMutableArray new];
    NSMutableArray<NSString *> *ignored = [NSMutableArray new];
    NSMutableArray<NSString *> *builtIn = [NSMutableArray new];
    NSUInteger written = 0, index = 0;
    while (index < lines.count) {
        if (![lines[index] hasPrefix:@"diff --git "]) {
            index++;
            continue;
        }
        NSString *header = [lines[index] substringFromIndex:11];
        NSRange split = [header rangeOfString:@" b/"];
        NSString *path = split.location == NSNotFound ? @"" : [header substringFromIndex:split.location + 3];
        NSMutableArray<NSString *> *block = [NSMutableArray new];
        index++;
        while (index < lines.count && ![lines[index] hasPrefix:@"diff --git "]) [block addObject:lines[index++]];
        if (!path.length) continue;
        BOOL isNew = NO;
        for (NSString *line in block)
            if ([line hasPrefix:@"new file mode"]) isNew = YES;
        if (DPLocalIsPlumbing(path) || !DPLocalIsSafePath(path)) {
            [ignored addObject:path];
            continue;
        }
        if ([path isEqual:@"src/dylib/StdPatch/Dia.h"]) {
            for (NSString *line in block) {
                if (![line hasPrefix:@"+#define "]) continue;
                NSString *define = [line substringFromIndex:1];
                if (![defines containsObject:define]) [defines addObject:define];
            }
            continue;
        }
        NSString *extension = path.pathExtension.lowercaseString;
        if (isNew && ([extension isEqual:@"m"] || [extension isEqual:@"h"])) {
            NSString *relative = [path hasPrefix:@"src/dylib/"] ? [path substringFromIndex:10]
                                 : [path hasPrefix:@"tweaks/"] ? [path substringFromIndex:7] : path.lastPathComponent;
            NSString *destination = [folder stringByAppendingPathComponent:relative];
            if (!DPLocalIsSafePath(relative) || !DPLocalIsInside(destination, folder)) {
                [ignored addObject:path];
                continue;
            }
            [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
            NSMutableString *content = [NSMutableString new];
            for (NSString *line in block) {
                if ([line hasPrefix:@"+++"] || [line hasPrefix:@"---"] || [line hasPrefix:@"@@"]) continue;
                if ([line hasPrefix:@"+"]) [content appendFormat:@"%@\n", [line substringFromIndex:1]];
            }
            [content writeToFile:destination atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            if ([extension isEqual:@"m"]) written++;
            continue;
        }
        if (!isNew && [@[ @"m", @"c", @"swift" ] containsObject:extension] && [path hasPrefix:@"src/dylib/"]) {
            [builtIn addObject:path.lastPathComponent];
            continue;
        }
        [ignored addObject:path];
    }
    if (defines.count) {
        NSMutableString *content = [NSMutableString stringWithString:@"// Constants this patch adds to Dia.h, so it compiles against the installed DiaTweaks.\n"];
        for (NSString *define in defines) {
            NSArray<NSString *> *parts = [define componentsSeparatedByString:@" "];
            NSString *name = parts.count > 1 ? parts[1] : @"";
            if (!DPLocalIsIdentifier(name)) continue;
            [content appendFormat:@"#ifndef %@\n%@\n#endif\n", name, define];
        }
        [content writeToFile:[folder stringByAppendingPathComponent:@"_dp_patch_defines.h"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    if (builtIn.count) {
        *error = [NSString stringWithFormat:@"Modifies built-in file %@ — changes to existing tweaks need a full DiaTweaks build.",
                                            [builtIn componentsJoinedByString:@", "]];
        return;
    }
    if (!written)
        *error = ignored.count ? [NSString stringWithFormat:@"This patch only changes DiaTweaks itself (%@), so it can’t run as a local tweak.",
                                                            [ignored componentsJoinedByString:@", "]]
                               : @"This patch has no new tweak files in it.";
}

void DPLocalExtractArchive(NSString *archive, NSString *folder, NSString **error) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:archive];
    BOOL zip = [[handle readDataOfLength:2] isEqual:[@"PK" dataUsingEncoding:NSASCIIStringEncoding]];
    [handle closeFile];
    NSString *output = nil;
    int status = zip ? DPLocalExec(@[ @"/usr/bin/tar", @"-xvf", archive, @"-C", folder ], &output) : -1;
    NSArray<NSString *> *entries = [[output componentsSeparatedByString:@"\n"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH 'x '"]];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([output containsString:@"leading '/'"] || [[entries componentsJoinedByString:@"\n"] containsString:@".."]) {
        [files removeItemAtPath:folder error:NULL];
        *error = @"That archive has a path that would escape the folder, so it wasn’t unpacked.";
        return;
    }
    if (status != 0) {
        *error = entries.count ? @"Couldn’t unpack the archive." : @"Couldn’t read the archive.";
        return;
    }
    // tar refuses to write through a symlink but still unpacks one, which could point the compiler outside the folder.
    for (NSString *relative in [files enumeratorAtPath:folder]) {
        struct stat info;
        if (lstat([folder stringByAppendingPathComponent:relative].fileSystemRepresentation, &info) != 0 || !S_ISLNK(info.st_mode)) continue;
        [files removeItemAtPath:folder error:NULL];
        *error = @"That archive contains a symbolic link, so it wasn’t unpacked.";
        return;
    }
}
