#import "UBlockOrigin.h"
#import <CommonCrypto/CommonDigest.h>

// uBlock Origin's own release page, where its author publishes each version for every browser.
static NSString *const kLatest = @"https://api.github.com/repos/gorhill/uBlock/releases/latest";

NSString *DPUBlockFolder(void) { return DPAppSupport(@"DiaPatches/ublock-origin"); }
NSString *DPUBlockStaged(void) { return DPAppSupport(@"DiaPatches/ublock-origin.next"); }

NSString *DPUBlockVersion(NSString *folder) {
    NSData *data = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"manifest.json"]];
    NSDictionary *manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"manifest_version"] isEqual:@2]) return nil;
    return [manifest[@"version"] isKindOfClass:NSString.class] ? manifest[@"version"] : nil;
}

static NSString *DPSHA256(NSURL *file) {
    NSData *data = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithString:@"sha256:"];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

// Off the main queue: checks the zip against GitHub's digest and unpacks it into DPUBlockStaged.
static NSString *DPStage(NSURL *zip, NSString *digest, NSString *version) {
    if (![DPSHA256(zip) isEqualToString:digest]) return @"The download didn’t match the checksum GitHub gave for it.";
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *partial = [DPUBlockStaged() stringByAppendingString:@".partial"];
    [files removeItemAtPath:partial error:nil];
    NSTask *ditto = [NSTask new];
    ditto.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    ditto.arguments = @[ @"-x", @"-k", zip.path, partial ];
    NSError *error;
    if (![ditto launchAndReturnError:&error]) return error.localizedDescription;
    [ditto waitUntilExit];
    NSString *root = [partial stringByAppendingPathComponent:@"uBlock0.chromium"];  // the zip holds one folder
    if (ditto.terminationStatus != 0 || ![DPUBlockVersion(root) isEqualToString:version]) {
        [files removeItemAtPath:partial error:nil];
        return @"The download isn’t a uBlock Origin for Chromium.";
    }
    [files removeItemAtPath:DPUBlockStaged() error:nil];
    BOOL moved = [files moveItemAtPath:root toPath:DPUBlockStaged() error:&error];
    [files removeItemAtPath:partial error:nil];
    return moved ? nil : error.localizedDescription;
}

static void DPFinish(void (^done)(NSString *), NSString *problem) {
    dispatch_async(dispatch_get_main_queue(), ^{ done(problem); });
}

void DPFetchUBlock(void (^done)(NSString *problem)) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLatest]];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"DiaTweaks" forHTTPHeaderField:@"User-Agent"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *release = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (error || [(NSHTTPURLResponse *)response statusCode] != 200 || ![release isKindOfClass:NSDictionary.class])
            return DPFinish(done, error.localizedDescription ?: @"GitHub didn’t say which version is the latest.");
        NSString *version = release[@"tag_name"];
        NSArray *assets = [release[@"assets"] isKindOfClass:NSArray.class] ? release[@"assets"] : @[];
        NSDictionary *asset;
        for (NSDictionary *each in assets)
            if ([each isKindOfClass:NSDictionary.class] && [each[@"name"] isKindOfClass:NSString.class] && [each[@"name"] hasSuffix:@".chromium.zip"]) asset = each;
        NSString *digest = asset[@"digest"], *link = asset[@"browser_download_url"];
        NSURL *url = [link isKindOfClass:NSString.class] ? [NSURL URLWithString:link] : nil;
        if (![version isKindOfClass:NSString.class] || ![digest isKindOfClass:NSString.class] || ![url.scheme isEqual:@"https"])
            return DPFinish(done, @"The latest release has no Chromium download.");
        if ([version isEqual:DPUBlockVersion(DPUBlockFolder())] || [version isEqual:DPUBlockVersion(DPUBlockStaged())]) return DPFinish(done, nil);
        [[NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *zip, NSURLResponse *response, NSError *error) {
            if (error || [(NSHTTPURLResponse *)response statusCode] != 200) return DPFinish(done, error.localizedDescription ?: @"GitHub didn’t send the download.");
            DPFinish(done, DPStage(zip, digest, version));  // the zip is deleted once this returns
        }] resume];
    }] resume];
}
