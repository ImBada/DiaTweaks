#import "BriefLanguage.h"
#import "TweakPrefs.h"

// The dylib reads this heading back to see which language the installed Dia writes in: keep the two in step.
static NSString *const DPBriefHeading = @"## Output language: ";
static NSString *const DPBriefPrompt = @"Contents/Resources/agent-server-resources/dist/prompts/skills/morning-brief/SKILL.md";

static NSArray<NSArray<NSString *> *> *DPLanguages(void) {
    return @[
        @[ @"English", @"en" ], @[ @"Japanese", @"ja" ], @[ @"Chinese (Simplified)", @"zh-Hans" ], @[ @"Chinese (Traditional)", @"zh-Hant" ],
        @[ @"Korean", @"ko" ], @[ @"Spanish", @"es" ], @[ @"French", @"fr" ], @[ @"German", @"de" ], @[ @"Italian", @"it" ],
        @[ @"Portuguese", @"pt" ], @[ @"Dutch", @"nl" ], @[ @"Russian", @"ru" ], @[ @"Turkish", @"tr" ], @[ @"Indonesian", @"id" ],
        @[ @"Vietnamese", @"vi" ], @[ @"Thai", @"th" ], @[ @"Hindi", @"hi" ], @[ @"Arabic", @"ar" ],
    ];
}

static NSString *DPSystemLanguage(void) {
    for (NSString *preferred in NSLocale.preferredLanguages)
        for (NSArray<NSString *> *language in DPLanguages())
            if ([preferred isEqual:language[1]] || [preferred hasPrefix:[language[1] stringByAppendingString:@"-"]]) return language[0];
    return @"English";
}

static BOOL DPKnownLanguage(NSString *name) {
    for (NSArray<NSString *> *language in DPLanguages())
        if ([language[0] isEqual:name]) return YES;
    return NO;
}

static NSString *DPChosenLanguage(NSString *home) {
    if (!DPTweakOn(home, @"briefLanguage")) return nil;
    id language = DPPref(@"briefLanguageChoice");
    if (!language) return DPSystemLanguage();
    return [language isKindOfClass:NSString.class] ? language : @"";
}

NSString *DPPrepareBriefLanguage(NSString *app, NSString *home) {
    NSString *language = DPChosenLanguage(home);
    if (!language) return nil;
    if (!DPKnownLanguage(language)) return @"kept the Morning Brief's language: the saved choice isn't one of its languages";
    NSString *path = [app stringByAppendingPathComponent:DPBriefPrompt];
    NSString *prompt = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!prompt) return @"kept the Morning Brief's language: this Dia has no brief prompt";
    NSRange existing = [prompt rangeOfString:[@"\n\n" stringByAppendingString:DPBriefHeading] options:NSBackwardsSearch];
    if (existing.location != NSNotFound) prompt = [prompt substringToIndex:existing.location];
    NSString *rule = [NSString stringWithFormat:
        @"\n\n%@%@\n"
        @"Write every piece of text the user reads in %@: titles, bodies, labels, notes, blurbs, greetings, and each cta_label and cta_prompt. "
        @"This overrides the language of the examples above and of the sources you read. "
        @"Keep the field names, source_name, label_style, URLs and date formats exactly as specified, and keep names of people, companies, products, "
        @"channels and files as they are written in the source. Quote a source in its own language only when the exact wording matters.\n",
        DPBriefHeading, language, language];
    return [[prompt stringByAppendingString:rule] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]
        ? [@"set the Morning Brief's language to " stringByAppendingString:language]
        : @"kept the Morning Brief's language: couldn't write the brief prompt";
}
