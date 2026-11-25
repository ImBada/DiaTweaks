#import "AppIcon.h"
#import "IconCatalog.h"
#import "TweakPrefs.h"
#include <sys/stat.h>

// Dia's own icon isn't always named AppIcon (beta builds use AppIconBeta).
static NSString *const DPIconAlias = @"DiaChosenIcon", *const DPDefaultChoice = @"AppIcon", *const DPOwnIconKey = @"DiaTweaksOwnIcon";

static NSString *DPInfoPath(NSString *app) { return [app stringByAppendingPathComponent:@"Contents/Info.plist"]; }

static NSString *DPCatalogPath(NSString *app) { return [app stringByAppendingPathComponent:@"Contents/Resources/Assets.car"]; }

static NSString *DPBuildOf(NSString *app) { return [NSDictionary dictionaryWithContentsOfFile:DPInfoPath(app)][@"CFBundleVersion"]; }

static NSString *DPRemoving(NSString *path, NSString *problem) {
    [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
    return problem;
}

static BOOL DPIsSymlink(NSString *path) {
    struct stat info;
    return path && lstat(path.fileSystemRepresentation, &info) == 0 && S_ISLNK(info.st_mode);
}

static NSString *DPOwnIcon(NSString *app) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:DPInfoPath(app)];
    NSString *name = info[DPOwnIconKey] ?: info[@"CFBundleIconName"];
    return name && ![name isEqual:DPIconAlias] ? name : DPDefaultChoice;
}

static NSString *DPIconsFolder(NSString *app, NSString *home) {
    NSString *build = DPBuildOf(app);
    return build ? [home stringByAppendingPathComponent:[@"icons/builds" stringByAppendingPathComponent:build]] : nil;
}

static NSString *DPChosenIcon(NSString *app, NSString *base, NSString *home) {
    NSString *own = DPOwnIcon(app);
    if (!DPTweakOn(home, @"appIcon")) return own;
    NSString *icon = DPPref(@"appIconChoice");
    if (![icon isKindOfClass:NSString.class] || [icon isEqual:DPDefaultChoice]) return own;
    return [DPOpenCatalog(base, NO).allRenditionNames containsObject:icon] ? icon : own;
}

static NSString *DPAddAlias(NSString *path, NSString *icon) {
    id<DPAssetStorage> catalog = DPOpenCatalog(path, YES);
    CGPoint hotSpot = CGPointZero;
    const DPKeyToken *key = [catalog renditionKeyForName:icon.UTF8String hotSpot:&hotSpot];
    if (!key) return [@"no icon named " stringByAppendingString:icon];
    DPKeyToken copy[32];
    int count = 0;
    for (; (key[count].attribute || key[count].value) && count < 31; count++) copy[count] = key[count];
    copy[count] = (DPKeyToken){0, 0};
    [catalog setRenditionKey:copy hotSpot:hotSpot forName:DPIconAlias.UTF8String];
    [catalog updateBitmapInfo];
    return [catalog writeToDiskAndCompact:YES] ? nil : @"couldn't write the catalog";
}

// Atomic rename so a running Dia keeps reading the old catalog.
static NSString *DPWriteCurrent(NSString *app, NSString *folder, NSString *home) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *base = [folder stringByAppendingPathComponent:@"base.car"], *current = [folder stringByAppendingPathComponent:@"current.car"];
    NSString *incoming = [current stringByAppendingString:@".new"];
    [files removeItemAtPath:incoming error:NULL];
    if (![files copyItemAtPath:base toPath:incoming error:NULL]) return @"couldn't copy the catalog";
    NSString *problem = DPAddAlias(incoming, DPChosenIcon(app, base, home));
    if (!problem && rename(incoming.fileSystemRepresentation, current.fileSystemRepresentation) != 0) problem = @"couldn't replace the catalog";
    [files removeItemAtPath:incoming error:NULL];
    return problem;
}

static NSArray<NSString *> *DPMissingIcons(NSString *catalog, NSString *home) {
    NSString *icons = [home stringByAppendingPathComponent:@"app-icons"];
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:icons error:NULL];
    if (!entries.count) return @[];
    NSSet<NSString *> *present = [NSSet setWithArray:DPOpenCatalog(catalog, NO).allRenditionNames];
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (NSString *name in [entries sortedArrayUsingSelector:@selector(compare:)])
        if ([name.pathExtension isEqual:@"car"] && ![present containsObject:name.stringByDeletingPathExtension])
            [missing addObject:[icons stringByAppendingPathComponent:name]];
    return missing;
}

static NSString *DPWriteBase(NSString *catalog, NSString *folder, NSString *home) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *base = [folder stringByAppendingPathComponent:@"base.car"], *incoming = [base stringByAppendingString:@".new"];
    [files removeItemAtPath:incoming error:NULL];
    if (![files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL]) return @"couldn't make the icons folder";
    if (![files copyItemAtPath:catalog toPath:incoming error:NULL]) return @"couldn't copy Dia's catalog";
    for (NSString *icon in DPMissingIcons(incoming, home)) {
        NSString *problem = DPMergeCatalog(icon, incoming);
        if (problem) return DPRemoving(incoming, [NSString stringWithFormat:@"%@: %@", icon.lastPathComponent, problem]);
    }
    if (rename(incoming.fileSystemRepresentation, base.fileSystemRepresentation) != 0) return DPRemoving(incoming, @"couldn't save the catalog");
    return nil;
}

static void DPPruneBuilds(NSString *keep, NSString *alsoKeep) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *builds = keep.stringByDeletingLastPathComponent;
    for (NSString *name in [files contentsOfDirectoryAtPath:builds error:NULL]) {
        NSString *path = [builds stringByAppendingPathComponent:name];
        if (![path isEqual:keep] && ![path isEqual:alsoKeep]) [files removeItemAtPath:path error:NULL];
    }
}

static NSString *DPCatalogSource(NSString *app, NSString *folder, NSString *home) {
    NSString *catalog = DPCatalogPath(app);
    if (!DPIsSymlink(catalog)) return [NSFileManager.defaultManager fileExistsAtPath:catalog] ? catalog : nil;
    NSString *pristine = [home stringByAppendingPathComponent:@"pristine/Dia.app"];
    NSString *build = DPBuildOf(app);
    NSString *pristineCatalog = DPCatalogPath(pristine);
    if (build && [build isEqual:DPBuildOf(pristine)] && !DPIsSymlink(pristineCatalog)
        && [NSFileManager.defaultManager fileExistsAtPath:pristineCatalog]) return pristineCatalog;
    NSString *base = [folder stringByAppendingPathComponent:@"base.car"];
    if (folder && !DPIsSymlink(base) && [NSFileManager.defaultManager fileExistsAtPath:base]) return base;
    NSString *resolved = catalog.stringByResolvingSymlinksInPath;
    return !DPIsSymlink(resolved) && [NSFileManager.defaultManager fileExistsAtPath:resolved] ? resolved : nil;
}

static NSString *DPRestoreCatalog(NSString *app, NSString *folder, NSString *home) {
    NSString *catalog = DPCatalogPath(app);
    if (DPIsSymlink(catalog)) {
        NSString *source = DPCatalogSource(app, folder, home);
        if (!source) return @"kept Dia's icons: couldn't find the original catalog";
        NSString *incoming = [catalog stringByAppendingString:@".new"];
        NSFileManager *files = NSFileManager.defaultManager;
        [files removeItemAtPath:incoming error:NULL];
        if (![files copyItemAtPath:source toPath:incoming error:NULL]
            || rename(incoming.fileSystemRepresentation, catalog.fileSystemRepresentation) != 0)
            return DPRemoving(incoming, @"kept Dia's icons: couldn't restore the catalog");
    }
    NSURL *url = [NSURL fileURLWithPath:DPInfoPath(app)];
    NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithContentsOfURL:url error:NULL];
    if (info && ([info[@"CFBundleIconName"] isEqual:DPIconAlias] || info[DPOwnIconKey])) {
        info[@"CFBundleIconName"] = DPOwnIcon(app);
        [info removeObjectForKey:DPOwnIconKey];
        if (![info writeToURL:url error:NULL]) return @"kept Dia's icon name: couldn't restore Info.plist";
    }
    return @"restored Dia's catalog";
}

// Symlinking Assets.car outside the bundle fails codesign --strict (-67003), so only link while App Icon is on.
NSString *DPPrepareIcons(NSString *app, NSString *installed, NSString *home) {
    NSString *folder = DPIconsFolder(app, home);
    NSString *catalog = DPCatalogPath(app);
    if (!DPTweakOn(home, @"appIcon")) {
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:DPInfoPath(app)];
        if (!DPIsSymlink(catalog) && ![info[@"CFBundleIconName"] isEqual:DPIconAlias] && !info[DPOwnIconKey]) return nil;
        return DPRestoreCatalog(app, folder, home);
    }
    if (!folder) return @"kept Dia's icons: no build number";
    NSString *source = DPCatalogSource(app, folder, home);
    if (!source) return @"kept Dia's icons: couldn't find Dia's catalog";
    NSString *problem = DPWriteBase(source, folder, home) ?: DPWriteCurrent(app, folder, home);
    if (problem) return [@"kept Dia's icons: " stringByAppendingString:problem];
    NSString *link = [catalog stringByAppendingString:@".link"];
    NSFileManager *files = NSFileManager.defaultManager;
    [files removeItemAtPath:link error:NULL];
    NSString *current = [folder stringByAppendingPathComponent:@"current.car"];
    if (![files createSymbolicLinkAtPath:link withDestinationPath:current error:NULL] || rename(link.fileSystemRepresentation, catalog.fileSystemRepresentation) != 0)
        return DPRemoving(link, @"kept Dia's icons: couldn't link the catalog");
    NSURL *url = [NSURL fileURLWithPath:DPInfoPath(app)];
    NSMutableDictionary *info = [[NSMutableDictionary alloc] initWithContentsOfURL:url error:NULL];
    info[DPOwnIconKey] = DPOwnIcon(app);
    info[@"CFBundleIconName"] = DPIconAlias;
    if (![info writeToURL:url error:NULL]) return @"kept Dia's icon name: couldn't update Info.plist";
    DPPruneBuilds(folder, DPIconsFolder(installed, home));
    return @"linked Dia's catalog for icon switching";
}

NSString *DPSwitchIcon(NSString *app, NSString *home) {
    NSString *catalog = DPCatalogPath(app);
    NSString *folder = DPIconsFolder(app, home), *base = [folder stringByAppendingPathComponent:@"base.car"];
    if (!folder || !DPIsSymlink(catalog) || ![NSFileManager.defaultManager fileExistsAtPath:base])
        return @"this Dia wasn't built for icon switching; run `diapatch install`";
    NSString *problem = (DPMissingIcons(base, home).count ? DPWriteBase(base, folder, home) : nil) ?: DPWriteCurrent(app, folder, home);
    if (problem) return problem;
    // IconServices caches by the bundle's date.
    [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate : NSDate.date} ofItemAtPath:app error:NULL];
    return nil;
}
