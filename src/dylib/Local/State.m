#import "Local/Local.h"

NSDictionary *DPLocalReadState(void) {
    // The file is JSON, which dictionaryWithContentsOfFile: (a plist reader) can't parse.
    NSData *data = [NSData dataWithContentsOfFile:DPLocalStatePath()];
    if (!data) return @{};
    id state = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [state isKindOfClass:NSDictionary.class] ? state : @{};
}

BOOL DPLocalWriteState(NSArray<NSDictionary *> *items) {
    NSMutableDictionary *state = [@{ @"version" : @1, @"dylibUUID" : DPDylibUUID(), @"items" : items ?: @[] } mutableCopy];
    if (DPLocalToolchainSaved()) state[@"toolchain"] = DPLocalToolchainSaved();
    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:NULL];
    if (!json) return NO;
    NSString *path = DPLocalStatePath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *temporary = [path stringByAppendingString:@".tmp"];
    if (![json writeToFile:temporary atomically:YES]) return NO;
    return rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
}
