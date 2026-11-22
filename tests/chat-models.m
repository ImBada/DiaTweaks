#import <Foundation/Foundation.h>

NSArray<NSString *> *DPInstalledChatModels(void);
uintptr_t DPKeepFixtureMetadata(void);
NSString *DPSelectedDiaChatModel(NSString *choice, NSArray<NSString *> *models, BOOL fallback);
NSData *DPChatAgentRequest(NSData *line, NSString *model);

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSCAssert(DPKeepFixtureMetadata(), @"fixture metadata missing");
    NSArray *models = DPInstalledChatModels();
    if (argc > 1 && !strcmp(argv[1], "empty")) {
        NSCAssert(!models.count, @"unsupported catalog must stay native: %@", models);
    } else {
        NSArray *expected = @[ @"future-provider-model", @"another-model-v99", @"another-model-v99[huge]" ];
        NSCAssert([models isEqual:expected], @"menu must use the native catalog in order: %@", models);
    }
    NSString *saved = @"removed-model-v42";
    NSCAssert(!DPSelectedDiaChatModel(saved, models, YES), @"missing model must fall back when enabled");
    NSCAssert([DPSelectedDiaChatModel(saved, models, NO) isEqual:saved], @"disabled fallback must retain the saved model");
    NSCAssert(!DPSelectedDiaChatModel(saved, @[], YES), @"missing catalog must fall back when enabled");
    NSCAssert([DPSelectedDiaChatModel(saved, @[], NO) isEqual:saved], @"missing catalog must not silently override the saved model");
    NSCAssert(!DPSelectedDiaChatModel(@"dia-default", models, NO), @"Dia Default must stay native");
    NSCAssert(!DPSelectedDiaChatModel(nil, models, NO), @"unset choice must stay native");
    if (models.count) NSCAssert([DPSelectedDiaChatModel(models[0], models, YES) isEqual:models[0]], @"available selection must be retained");
    NSDictionary *run = @{ @"type": @"RUN", @"agent": @"default", @"prompt": @"Synthetic fallback test",
        @"spec_override": @{ @"settings": @{ @"model": @"native-model", @"env": @{ @"KEEP": @"yes" } } } };
    NSData *original = [NSJSONSerialization dataWithJSONObject:run options:0 error:nil];
    NSData *fallback = DPChatAgentRequest(original, DPSelectedDiaChatModel(saved, models, YES));
    NSCAssert([fallback isEqual:original], @"fallback must preserve Dia's complete original request");
    NSData *explicit = DPChatAgentRequest(original, DPSelectedDiaChatModel(saved, models, NO));
    NSDictionary *sent = [NSJSONSerialization JSONObjectWithData:explicit options:0 error:nil];
    NSCAssert([sent[@"spec_override"][@"settings"][@"model"] isEqual:saved], @"disabled fallback must send the saved choice to Dia");
    NSCAssert([sent[@"spec_override"][@"settings"][@"env"][@"KEEP"] isEqual:@"yes"], @"model selection must preserve other request settings");
    puts("native model catalog and fallback policy passed");
}}
