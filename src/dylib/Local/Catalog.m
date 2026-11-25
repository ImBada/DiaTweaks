#import "Local/Local.h"

static NSURL *DPCatalogBase(void) {
    const char *override = getenv("DIAPATCH_CATALOG_URL");
    if (!override || !*override) return [NSURL URLWithString:@"https://raw.githubusercontent.com/JaceThings/DiaTweaks/main/tweaks/"];
    NSString *text = @(override);
    if (![text hasPrefix:@"http://"] && ![text hasPrefix:@"https://"] && ![text hasPrefix:@"file://"]) return [NSURL fileURLWithPath:text isDirectory:YES];
    return [NSURL URLWithString:[text hasSuffix:@"/"] ? text : [text stringByAppendingString:@"/"]];
}

static NSURL *DPCatalogURL(NSString *path) {
    NSURL *url = DPCatalogBase();
    for (NSString *part in [path componentsSeparatedByString:@"/"]) url = [url URLByAppendingPathComponent:part];
    return url;
}

static NSString *DPCatalogPath(void) { return [DPLocalCacheFolder() stringByAppendingPathComponent:@"catalog.json"]; }

static NSURLSession *DPCatalogSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.HTTPMaximumConnectionsPerHost = 6;
        configuration.timeoutIntervalForRequest = 15;
        configuration.URLCache = nil;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

static NSData *DPCatalogGet(NSURL *url, NSString *etag, NSInteger *status, NSString **tag) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    if (etag) [request setValue:etag forHTTPHeaderField:@"If-None-Match"];
    __block NSData *body = nil;
    __block NSInteger code = 0;
    __block NSString *received = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [DPCatalogSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if ([response isKindOfClass:NSHTTPURLResponse.class]) {
            code = ((NSHTTPURLResponse *)response).statusCode;
            received = [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"ETag"];
        } else if (!error) code = 200;
        else if (error.code == NSURLErrorFileDoesNotExist) code = 404;
        body = error ? nil : data;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) != 0) {
        [task cancel];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        code = 0;
        body = nil;
    }
    *status = code;
    if (tag) *tag = received;
    return body;
}

static BOOL DPCatalogIsText(id value) { return [value isKindOfClass:NSString.class] && [value length]; }

static BOOL DPCatalogIsSingle(NSArray<NSString *> *files) { return files.count == 1 && ![files[0] containsString:@"/"]; }

static BOOL DPCatalogValidID(id identifier) {
    if (!DPCatalogIsText(identifier)) return NO;
    for (NSString *bad in @[ @"/", @"\\", @".." ])
        if ([identifier containsString:bad]) return NO;
    return ![identifier hasPrefix:@"."] && ![identifier isEqual:@"README"] && ![identifier isEqual:@"index"];
}

static BOOL DPCatalogValidFile(id path) {
    if (!DPCatalogIsText(path) || [path hasPrefix:@"/"] || [path containsString:@"\\"] || [path containsString:@".."]) return NO;
    for (NSString *part in [path componentsSeparatedByString:@"/"])
        if (!part.length || [part hasPrefix:@"."]) return NO;
    NSString *extension = [path pathExtension];
    return [extension isEqual:@"m"] || [extension isEqual:@"h"];
}

static BOOL DPCatalogValidFiles(NSString *identifier, id files) {
    if (![files isKindOfClass:NSArray.class] || ![files count]) return NO;
    BOOL source = NO;
    for (NSString *path in files) {
        if (!DPCatalogValidFile(path)) return NO;
        source |= [path.pathExtension isEqual:@"m"];
    }
    if (DPCatalogIsSingle(files)) return [files[0] isEqual:[identifier stringByAppendingString:@".m"]];
    for (NSString *path in files)
        if (![path hasPrefix:[identifier stringByAppendingString:@"/"]]) return NO;
    return source;
}

static BOOL DPCatalogValidPatches(id patches) {
    if (![patches isKindOfClass:NSArray.class] || ![patches count]) return NO;
    for (NSDictionary *patch in patches) {
        if (![patch isKindOfClass:NSDictionary.class] || !DPCatalogIsText(patch[@"key"]) || !DPCatalogIsText(patch[@"title"])) return NO;
        for (NSString *field in @[ @"detail", @"symbol", @"tint" ])
            if (patch[field] && ![patch[field] isKindOfClass:NSString.class]) return NO;
        id section = patch[@"section"];
        if (section && section != NSNull.null && ![section isKindOfClass:NSString.class]) return NO;
    }
    return YES;
}

static BOOL DPCatalogValidEntry(id entry) {
    return [entry isKindOfClass:NSDictionary.class] && DPCatalogValidID(entry[@"id"]) && DPCatalogValidFiles(entry[@"id"], entry[@"files"])
           && DPCatalogValidPatches(entry[@"patches"]);
}

static NSArray<NSDictionary *> *DPCatalogValidated(id tweaks) {
    if (![tweaks isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSDictionary *> *valid = [NSMutableArray new];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    for (NSDictionary *entry in tweaks) {
        if (!DPCatalogValidEntry(entry) || [seen containsObject:entry[@"id"]]) continue;
        [seen addObject:entry[@"id"]];
        [valid addObject:entry];
    }
    return valid;
}

static void DPCatalogSave(NSArray<NSDictionary *> *tweaks, NSString *etag) {
    NSMutableDictionary *catalog = [NSMutableDictionary dictionaryWithObject:tweaks forKey:@"tweaks"];
    catalog[@"etag"] = etag;
    NSData *json = [NSJSONSerialization dataWithJSONObject:catalog options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    NSString *path = DPCatalogPath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    [json writeToFile:path atomically:YES];
}

static NSDictionary *DPCatalogCached(void) {
    NSData *data = [NSData dataWithContentsOfFile:DPCatalogPath()];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}

NSArray<NSDictionary *> *DPLocalCachedCatalog(void) { return DPCatalogValidated(DPCatalogCached()[@"tweaks"]); }

NSArray<NSDictionary *> *DPLocalFetchCatalog(NSString **error) {
    NSDictionary *cached = DPCatalogCached();
    NSArray<NSDictionary *> *previous = DPCatalogValidated(cached[@"tweaks"]);
    NSString *etag = previous && DPCatalogIsText(cached[@"etag"]) ? cached[@"etag"] : nil, *tag = nil;
    NSInteger status = 0;
    NSData *data = DPCatalogGet(DPCatalogURL(@"index.json"), etag, &status, &tag);
    if (error) *error = nil;
    if (status == 304 && etag) return previous;
    if (status == 404) {
        DPCatalogSave(@[], nil);
        return @[];
    }
    if (status != 200 || !data) {
        if (error) *error = status ? [NSString stringWithFormat:@"GitHub answered %ld while loading optional tweaks.", (long)status] : @"Couldn’t reach GitHub to load optional tweaks.";
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSArray<NSDictionary *> *catalog = [json isKindOfClass:NSDictionary.class] ? DPCatalogValidated(json[@"tweaks"]) : nil;
    if (!catalog) {
        if (error) *error = @"The list of optional tweaks on GitHub isn’t readable.";
        return nil;
    }
    DPCatalogSave(catalog, tag);
    return catalog;
}

NSDictionary *DPLocalPrimaryPatch(NSDictionary *entry) {
    for (NSDictionary *patch in entry[@"patches"]) {
        id requires = patch[@"requires"];
        if (![requires isKindOfClass:NSString.class] || ![requires length]) return patch;
    }
    return [entry[@"patches"] firstObject];
}

BOOL DPLocalIsBuiltIn(NSDictionary *entry) {
    NSSet<NSString *> *official = DPLocalOfficialKeySet();
    for (NSDictionary *patch in entry[@"patches"])
        if (![official containsObject:patch[@"key"]]) return NO;
    return YES;
}

NSArray<NSDictionary *> *DPLocalAvailableCatalog(NSArray<NSDictionary *> *catalog) { return DPLocalAvailableCatalogForItems(catalog, DPLocalItems()); }

NSArray<NSDictionary *> *DPLocalAvailableCatalogForItems(NSArray<NSDictionary *> *catalog, NSArray<NSDictionary *> *items) {
    NSSet<NSString *> *folderIDs = [NSSet setWithArray:[items valueForKey:@"id"]];
    NSUserDefaults *defaults = DPSettingsDefaults();
    NSMutableArray<NSDictionary *> *previouslyOn = [NSMutableArray new], *rest = [NSMutableArray new];
    for (NSDictionary *entry in catalog) {
        if ([folderIDs containsObject:entry[@"id"]]) {
            [rest addObject:entry];
            continue;
        }
        if (DPLocalIsBuiltIn(entry)) continue;
        if ([[defaults objectForKey:DPLocalPrimaryPatch(entry)[@"key"]] boolValue]) [previouslyOn addObject:entry];
        else [rest addObject:entry];
    }
    return [previouslyOn arrayByAddingObjectsFromArray:rest];
}

BOOL DPLocalIsCatalogItemInstalled(NSDictionary *entry, NSArray<NSDictionary *> *localItems) {
    NSString *key = DPLocalPrimaryPatch(entry)[@"key"];
    for (NSDictionary *item in localItems) {
        if ([item[@"id"] isEqual:entry[@"id"]]) return YES;
        if (![@[ @"loaded", @"ready" ] containsObject:item[@"status"]]) continue;
        for (NSDictionary *patch in item[@"patches"])
            if ([patch[@"key"] isEqual:key]) return YES;
    }
    return NO;
}

static BOOL DPCatalogDownload(NSString *path, NSString *staging, NSString **error) {
    NSInteger status = 0;
    NSData *data = DPCatalogGet(DPCatalogURL(path), nil, &status, NULL);
    NSString *name = path.lastPathComponent;
    if (!status) {
        *error = [NSString stringWithFormat:@"Couldn’t download %@ from GitHub.", name];
        return NO;
    }
    if (status != 200) {
        *error = [NSString stringWithFormat:@"GitHub answered %ld for %@.", (long)status, name];
        return NO;
    }
    if (!data.length) {
        *error = [NSString stringWithFormat:@"%@ came down empty.", name];
        return NO;
    }
    NSString *destination = [staging stringByAppendingPathComponent:path];
    NSFileManager *files = NSFileManager.defaultManager;
    if (![destination.stringByStandardizingPath hasPrefix:[staging.stringByStandardizingPath stringByAppendingString:@"/"]]
        || ![files createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]
        || ![data writeToFile:destination atomically:YES]) {
        *error = [NSString stringWithFormat:@"Couldn’t save %@.", name];
        return NO;
    }
    return YES;
}

static BOOL DPCatalogPlace(NSString *identifier, BOOL single, NSString *staging) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *folder = DPLocalFolder(), *backup = [staging stringByAppendingPathComponent:@".backup"];
    NSMutableArray<NSString *> *moved = [NSMutableArray new];
    [files createDirectoryAtPath:backup withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSString *name in @[ identifier, [identifier stringByAppendingString:@".m"] ]) {
        NSString *existing = [folder stringByAppendingPathComponent:name];
        if (![files fileExistsAtPath:existing]) continue;
        if (![files moveItemAtPath:existing toPath:[backup stringByAppendingPathComponent:name] error:NULL]) break;
        [moved addObject:name];
    }
    NSString *incoming = single ? [identifier stringByAppendingString:@".m"] : identifier;
    BOOL placed = [files moveItemAtPath:[staging stringByAppendingPathComponent:incoming] toPath:[folder stringByAppendingPathComponent:incoming] error:NULL];
    if (!placed)
        for (NSString *name in moved) [files moveItemAtPath:[backup stringByAppendingPathComponent:name] toPath:[folder stringByAppendingPathComponent:name] error:NULL];
    return placed;
}

BOOL DPLocalInstallCatalogItems(NSArray<NSDictionary *> *entries, NSString **error) {
    BOOL valid = entries.count > 0;
    for (NSDictionary *entry in entries) valid = valid && DPCatalogValidEntry(entry);
    if (!valid) {
        *error = @"That tweak’s listing isn’t valid, so it wasn’t downloaded.";
        return NO;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *stagings = [NSMutableArray new];
    NSMutableArray<NSMutableDictionary *> *downloads = [NSMutableArray new];
    for (NSDictionary *entry in entries) {
        NSString *staging = [[DPLocalCacheFolder() stringByAppendingPathComponent:@"staging"] stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [stagings addObject:staging];
        for (NSString *path in entry[@"files"]) [downloads addObject:[@{ @"path" : path, @"staging" : staging } mutableCopy]];
    }
    dispatch_apply(downloads.count, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
        @autoreleasepool {
            NSString *problem = nil;
            if (!DPCatalogDownload(downloads[i][@"path"], downloads[i][@"staging"], &problem)) downloads[i][@"error"] = problem;
        }
    });
    NSString *failure = nil;
    for (NSDictionary *download in downloads) failure = failure ?: download[@"error"];
    if (!failure) {
        DPLocalWriteReadme();
        for (NSUInteger i = 0; i < entries.count && !failure; i++)
            if (!DPCatalogPlace(entries[i][@"id"], DPCatalogIsSingle(entries[i][@"files"]), stagings[i]))
                failure = [NSString stringWithFormat:@"Couldn’t put %@ in your local folder.", entries[i][@"id"]];
    }
    for (NSString *staging in stagings) [files removeItemAtPath:staging error:NULL];
    if (failure) {
        *error = failure;
        return NO;
    }

    NSString *report = nil;
    DPLocalBuildNames([entries valueForKey:@"id"], NO, &report);
    NSMutableDictionary<NSString *, NSDictionary *> *records = [NSMutableDictionary new];
    for (NSDictionary *item in DPLocalReadState()[@"items"])
        if (item[@"id"]) records[item[@"id"]] = item;
    NSUserDefaults *defaults = DPSettingsDefaults();
    for (NSDictionary *entry in entries) {
        NSDictionary *record = records[entry[@"id"]];
        if (![@[ @"loaded", @"ready" ] containsObject:record[@"status"]]) {
            *error = record[@"error"] ?: report ?: @"It didn’t build.";
            return NO;
        }
        NSString *key = DPLocalPrimaryPatch(entry)[@"key"];
        if (![defaults objectForKey:key]) [defaults setBool:YES forKey:key];
    }
    return YES;
}

BOOL DPLocalInstallCatalogItem(NSDictionary *entry, NSString **error) { return DPLocalInstallCatalogItems(entry ? @[ entry ] : @[], error); }
