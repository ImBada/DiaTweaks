#import <Foundation/Foundation.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

// A test that blocks (a tracking loop, a modal wait) would hold up CI for hours. This turns it into a failure that names the stage.
static const char *volatile DPTestStage = "startup";

#define DPStage(name) (DPTestStage = (name))
#define DPRunTest(test) do { DPTestStage = #test; test(); } while (0)

static void DPTestTimedOut(int signal) {
    static const char head[] = "FAIL: timed out during ";
    write(STDOUT_FILENO, head, sizeof head - 1);
    write(STDOUT_FILENO, DPTestStage, strlen(DPTestStage));
    write(STDOUT_FILENO, "\n", 1);
    _exit(1);
}

static void DPArmTestWatchdog(unsigned seconds) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    signal(SIGALRM, DPTestTimedOut);
    alarm(seconds);
}
