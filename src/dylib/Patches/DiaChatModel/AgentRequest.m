#import <Foundation/Foundation.h>

BOOL DPValidChatModel(NSString *model) {
    if (![model isKindOfClass:NSString.class] || !model.length || model.length > 256) return NO;
    static NSCharacterSet *blocked;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
        [set formUnionWithCharacterSet:NSCharacterSet.controlCharacterSet];
        blocked = set;
    });
    return [model rangeOfCharacterFromSet:blocked].location == NSNotFound;
}

NSString *DPSelectedDiaChatModel(NSString *choice, NSArray<NSString *> *models, BOOL fallback) {
    if (!choice.length || [choice isEqual:@"dia-default"] || !DPValidChatModel(choice)) return nil;
    return !fallback || [models containsObject:choice] ? choice : nil;
}

static BOOL DPMayBeChatRun(NSData *line) {
    static const char *const needles[] = { "\"RUN\"", "\"spec_override\"", "\"model\"" };
    for (size_t i = 0; i < sizeof needles / sizeof *needles; i++)
        if (!memmem(line.bytes, line.length, needles[i], strlen(needles[i]))) return NO;
    return YES;
}

// Only Dia's own chat run is rewritten; any other frame, or a run of a different shape, passes through untouched.
NSData *DPChatAgentRequest(NSData *line, NSString *model) {
    if (!model || !DPMayBeChatRun(line) || !DPValidChatModel(model)) return line;
    id parsed = [NSJSONSerialization JSONObjectWithData:line options:NSJSONReadingMutableContainers error:nil];
    NSMutableDictionary *message = [parsed isKindOfClass:NSMutableDictionary.class] ? parsed : nil;
    if (![message[@"type"] isEqual:@"RUN"]) return line;
    NSMutableDictionary *run = message[@"payload"] ?: message;
    if (![run isKindOfClass:NSMutableDictionary.class] || ![run[@"agent"] isEqual:@"default"] ||
        ![run[@"prompt"] isKindOfClass:NSString.class]) return line;
    NSMutableDictionary *spec = run[@"spec_override"];
    if (![spec isKindOfClass:NSMutableDictionary.class]) return line;
    NSMutableDictionary *settings = spec[@"settings"];
    if (![settings isKindOfClass:NSMutableDictionary.class] || ![settings[@"model"] isKindOfClass:NSString.class]) return line;
    NSMutableDictionary *env = settings[@"env"];
    if (env && ![env isKindOfClass:NSMutableDictionary.class]) return line;
    settings[@"model"] = model;
    settings[@"env"] = env ?: (env = [NSMutableDictionary new]);
    env[@"DIA_EXPLICIT_MODEL_SELECTION"] = @"true";
    if (![NSJSONSerialization isValidJSONObject:message]) return line;
    return [NSJSONSerialization dataWithJSONObject:message options:0 error:nil] ?: line;
}
