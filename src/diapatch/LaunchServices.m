#import "LaunchServices.h"

static void runLSRegister(NSString *flag, NSString *app) {
    if (!app.length) return;
    const char *logPath = getenv("DIAPATCH_LSREGISTER_LOG");
    if (logPath && *logPath) {
        FILE *log = fopen(logPath, "ae");
        if (log) {
            fputs([NSString stringWithFormat:@"%@ %@\n", flag, app].UTF8String, log);
            fclose(log);
        }
        return;
    }
    const char *home = getenv("DIAPATCH_HOME");
    if (home && *home) return;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"];
    task.arguments = @[ flag, app ];
    task.standardInput = task.standardOutput = task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if ([task launchAndReturnError:NULL]) [task waitUntilExit];
}

void DPForgetApp(NSString *app) { runLSRegister(@"-u", app); }

void DPRegisterApp(NSString *app) { runLSRegister(@"-f", app); }
