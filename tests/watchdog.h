#import <Foundation/Foundation.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

// A test that blocks (a tracking loop, a modal wait) would hold up CI for hours. This turns it into a failure that names the stage.
static const char *volatile DPTestStage = "startup";

#define DPStage(name) (DPTestStage = (name))
#define DPRunTest(test) do { DPTestStage = #test; test(); } while (0)

// _exit skips atexit, so scratch state a test must not leave behind is registered here to run on a normal exit and on a timeout.
#define DPMaxTestCleanups 8
static void (*DPTestCleanups[DPMaxTestCleanups])(void);

static void DPRunTestCleanups(void) {
    for (int i = DPMaxTestCleanups - 1; i >= 0; i--) {
        void (*cleanup)(void) = DPTestCleanups[i];
        DPTestCleanups[i] = NULL;
        if (cleanup) cleanup();
    }
}

static inline void DPOnTestCleanup(void (*cleanup)(void)) {
    static BOOL armed;
    if (!armed) {
        armed = YES;
        atexit(DPRunTestCleanups);
    }
    for (int i = 0; i < DPMaxTestCleanups; i++)
        if (!DPTestCleanups[i]) {
            DPTestCleanups[i] = cleanup;
            return;
        }
}

static void DPTestForceExit(int sig) { _exit(1); }

static void DPTestTimedOut(int sig) {
    static const char head[] = "FAIL: timed out during ";
    write(STDOUT_FILENO, head, sizeof head - 1);
    write(STDOUT_FILENO, DPTestStage, strlen(DPTestStage));
    write(STDOUT_FILENO, "\n", 1);
    // A cleanup can wait on a lock the interrupted code holds, so a second alarm ends the test regardless.
    signal(SIGALRM, DPTestForceExit);
    sigset_t alarmSignal;
    sigemptyset(&alarmSignal);
    sigaddset(&alarmSignal, SIGALRM);
    sigprocmask(SIG_UNBLOCK, &alarmSignal, NULL);
    alarm(5);
    DPRunTestCleanups();
    _exit(1);
}

static void DPArmTestWatchdog(unsigned seconds) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    signal(SIGALRM, DPTestTimedOut);
    alarm(seconds);
}
