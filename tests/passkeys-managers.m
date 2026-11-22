#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

// Runs the real passkeys page.js against a mock Chromium WebAuthn surface, one fresh
// JavaScriptCore context per scenario, so both extension injection orders are covered.

static NSString *DPRead(NSString *path) {
    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!text) fprintf(stderr, "cannot read %s: %s\n", path.UTF8String, error.localizedDescription.UTF8String);
    return text;
}

static NSString *DPString(JSContextRef ctx, JSValueRef value) {
    if (!value) return @"";
    JSStringRef string = JSValueToStringCopy(ctx, value, NULL);
    if (!string) return @"";
    size_t size = JSStringGetMaximumUTF8CStringSize(string);
    char *buffer = malloc(size);
    JSStringGetUTF8CString(string, buffer, size);
    NSString *result = @(buffer);
    free(buffer);
    JSStringRelease(string);
    return result;
}

static BOOL DPEvaluate(JSGlobalContextRef ctx, NSString *source, NSString *label, NSString **failure) {
    JSStringRef script = JSStringCreateWithCFString((__bridge CFStringRef)source);
    JSValueRef exception = NULL;
    JSEvaluateScript(ctx, script, NULL, NULL, 1, &exception);
    JSStringRelease(script);
    if (!exception) return YES;
    *failure = [NSString stringWithFormat:@"%@ threw: %@", label, DPString(ctx, exception)];
    return NO;
}

static JSValueRef DPEvaluateValue(JSGlobalContextRef ctx, NSString *source) {
    JSStringRef script = JSStringCreateWithCFString((__bridge CFStringRef)source);
    JSValueRef value = JSEvaluateScript(ctx, script, NULL, NULL, 1, NULL);
    JSStringRelease(script);
    return value;
}

static NSArray<NSString *> *DPScenarioNames(NSString *harness) {
    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    NSString *failure = nil;
    NSArray *names = nil;
    if (DPEvaluate(ctx, harness, @"harness", &failure)) {
        NSString *joined = DPString(ctx, DPEvaluateValue(ctx, @"__harness.names()"));
        names = [joined componentsSeparatedByString:@","];
    } else {
        fprintf(stderr, "%s\n", failure.UTF8String);
    }
    JSGlobalContextRelease(ctx);
    return names;
}

static BOOL DPRunScenario(NSString *name, NSString *harness, NSString *page, NSString **failure) {
    JSGlobalContextRef ctx = JSGlobalContextCreate(NULL);
    BOOL ok = DPEvaluate(ctx, harness, @"harness", failure);
    if (ok) {
        JSValueRef repeat = DPEvaluateValue(ctx, [NSString stringWithFormat:@"__harness.setup('%@')", name]);
        int extra = repeat ? (int)JSValueToNumber(ctx, repeat, NULL) : 0;
        for (int i = 0; i <= extra && ok; i++) ok = DPEvaluate(ctx, page, @"page.js", failure);
    }
    if (ok) ok = DPEvaluate(ctx, [NSString stringWithFormat:@"__harness.run('%@')", name], @"run", failure);
    if (ok) {
        NSString *json = DPString(ctx, DPEvaluateValue(ctx, @"__harness.result()"));
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        ok = [result[@"ok"] boolValue];
        if (!ok) *failure = result[@"error"] ?: @"no result";
    }
    JSGlobalContextRelease(ctx);
    return ok;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *root = NSFileManager.defaultManager.currentDirectoryPath;
        NSString *pagePath = argc > 1 ? @(argv[1]) : [root stringByAppendingPathComponent:@"src/dylib/Patches/Passkeys/extension/page.js"];
        NSString *harnessPath = argc > 2 ? @(argv[2]) : [root stringByAppendingPathComponent:@"tests/passkeys-managers.js"];
        NSString *page = DPRead(pagePath);
        NSString *harness = DPRead(harnessPath);
        if (!page || !harness) return 1;

        NSArray<NSString *> *names = DPScenarioNames(harness);
        if (!names.count) return 1;

        int failed = 0;
        for (NSString *name in names) {
            NSString *failure = nil;
            if (DPRunScenario(name, harness, page, &failure)) {
                printf("ok   %s\n", name.UTF8String);
            } else {
                printf("FAIL %s: %s\n", name.UTF8String, failure.UTF8String);
                failed++;
            }
        }
        if (failed) {
            printf("FAIL: %d of %lu passkey manager scenarios\n", failed, (unsigned long)names.count);
            return 1;
        }
        printf("PASS: %lu passkey manager scenarios\n", (unsigned long)names.count);
    }
    return 0;
}
