#import "Local/Local.h"

NSDictionary *DPLocalReadState(void) {
    NSData *data = [NSData dataWithContentsOfFile:DPLocalStatePath()];
    id state = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [state isKindOfClass:NSDictionary.class] ? state : @{};
}

static NSDictionary *DPLocalStateOf(NSArray<NSDictionary *> *items) {
    NSMutableDictionary *state = [@{ @"version" : @1, @"dylibUUID" : DPDylibUUID(), @"items" : items.copy ?: @[] } mutableCopy];
    id toolchain = DPLocalToolchainSaved() ?: DPLocalSavedValue(@"toolchain");
    if ([toolchain isKindOfClass:NSDictionary.class]) state[@"toolchain"] = toolchain;
    return state;
}

static BOOL DPLocalStore(NSDictionary *state) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    NSString *path = DPLocalStatePath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    return [json writeToFile:path atomically:YES];
}

BOOL DPLocalWriteState(NSArray<NSDictionary *> *items) { return DPLocalStore(DPLocalStateOf(items)); }

NSDictionary *DPLocalUpdateState(NSArray<NSDictionary *> *items, NSDictionary *saved) {
    NSDictionary *state = DPLocalStateOf(items);
    return [state isEqual:saved] || DPLocalStore(state) ? state : saved;
}
