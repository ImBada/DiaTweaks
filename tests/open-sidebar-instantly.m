#import <objc/runtime.h>
#import "StdPatch/StdPatch.h"

BOOL DPTesting = YES;
NSNotificationName const DPPatchesDidChangeNotification = @"DPPatchesDidChange";
static int setPatchCalls;
static BOOL lastSetOn;
void DPSetPatch(DPPatch *patch, BOOL on, BOOL persist) {
    setPatchCalls++;
    lastSetOn = on;
    patch->on = on;
    (void)persist;
}

static int monitorCalls;
static id (*origAddLocalMonitor)(id, SEL, NSEventMask, NSEvent *(^)(NSEvent *));
static id DPTrackLocalMonitor(id self, SEL sel, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    monitorCalls++;
    return origAddLocalMonitor(self, sel, mask, handler);
}

#import "Patches/OpenSidebarInstantly/OpenSidebarInstantly.m"

// Executable ARM64 mirror of WindowController's hover visibility decision (1.58.0 @ 0x1063b1580, 1.59.0 @ 0x1064026d8)
// whose 27-instruction tail matches DPSignature verbatim:
//   x0 = const uint8_t hoverInfo[7], w1 = currentVisibility (1=hidden, 2=hovering), w2 = isSidebar (0/1).
// Returns 1 (hidden) or 2 (hovering).
typedef uint32_t (*DPHoverDecisionFn)(const uint8_t *hoverInfo, uint32_t currentVisibility, uint32_t isSidebar);

static NSUInteger DPBuildHoverStub(uint32_t *buf, NSUInteger *sigStartOut) {
    NSUInteger n = 0;
    // Indices 0..4: prologue
    buf[n++] = 0xf81f0ff4; //  0: str  x20, [sp, #-0x10]!
    buf[n++] = 0xaa0003f4; //  1: mov  x20, x0
    buf[n++] = 0xd2800008; //  2: mov  x8, #0
    buf[n++] = 0x2a0103ea; //  3: mov  w10, w1
    buf[n++] = 0x340001c2; //  4: cbz  w2, +0x38 -> 18 (top tab strip = sig[0])
    // Indices 5..13: sidebar branch
    buf[n++] = 0x8b080288; //  5: add  x8, x20, x8
    buf[n++] = 0x39400909; //  6: ldrb w9, [x8, #2]       ; sidebarHoverState
    buf[n++] = 0x7100055f; //  7: cmp  w10, #1
    buf[n++] = 0x54000301; //  8: b.ne +0x60 -> 32        ; sidebar open (sig[14])
    buf[n++] = 0x7100053f; //  9: cmp  w9, #1
    buf[n++] = 0x540000a8; // 10: b.hi +0x14 -> 15        ; return_2
    buf[n++] = 0x39400509; // 11: ldrb w9, [x8, #1]       ; outerLeftEdgeHoverState
    buf[n++] = 0x39400108; // 12: ldrb w8, [x8]           ; innerLeftEdgeHoverState
    buf[n++] = 0x1400000d; // 13: b    +0x34 -> 26        ; shared edge check (sig[8])
    // Index 14: padding nop
    buf[n++] = 0xd503201f; // 14: nop
    // Indices 15..17: return_2 / epilogue
    buf[n++] = 0x52800040; // 15: mov  w0, #2
    buf[n++] = 0xf84107f4; // 16: ldr  x20, [sp], #0x10
    buf[n++] = 0xd65f03c0; // 17: ret
    // Indices 18..44: exact 27-word DPSignature
    *sigStartOut = n;
    buf[n++] = 0x8b080288; // 18 (sig  0): add  x8, x20, x8
    buf[n++] = 0x39401509; // 19 (sig  1): ldrb w9, [x8, #5]       ; tabStripHoverState
    buf[n++] = 0x7100055f; // 20 (sig  2): cmp  w10, #1
    buf[n++] = 0x540001e1; // 21 (sig  3): b.ne +0x3c -> 36        ; tabStrip open (sig[18])
    buf[n++] = 0x7100053f; // 22 (sig  4): cmp  w9, #1
    buf[n++] = 0x54ffff08; // 23 (sig  5): b.hi -0x20 -> 15        ; return_2
    buf[n++] = 0x39401109; // 24 (sig  6): ldrb w9, [x8, #4]       ; outerTopEdgeHoverState
    buf[n++] = 0x39400d08; // 25 (sig  7): ldrb w8, [x8, #3]       ; innerTopEdgeHoverState
    buf[n++] = 0x12001d08; // 26 (sig  8): and  w8, w8, #0xff
    buf[n++] = DPWaitInner; // 27 (sig  9): cmp  w8, #1
    buf[n++] = DPWaitOuter; // 28 (sig 10): ccmp w9, #1, #2, ls
    buf[n++] = 0x52800028; // 29 (sig 11): mov  w8, #1
    buf[n++] = 0x1a889500; // 30 (sig 12): cinc w0, w8, hi
    buf[n++] = 0x17fffff1; // 31 (sig 13): b    -0x3c -> 16        ; epilogue
    buf[n++] = 0x35fffde9; // 32 (sig 14): cbnz w9, -0x44 -> 15    ; sidebar open -> return_2
    buf[n++] = 0x39400509; // 33 (sig 15): ldrb w9, [x8, #1]       ; outerLeftEdgeHoverState
    buf[n++] = 0x39400108; // 34 (sig 16): ldrb w8, [x8]           ; innerLeftEdgeHoverState
    buf[n++] = 0x14000004; // 35 (sig 17): b    +0x10 -> 39        ; open edge check
    buf[n++] = 0x35fffd69; // 36 (sig 18): cbnz w9, -0x54 -> 15    ; tabStrip open -> return_2
    buf[n++] = 0x39401109; // 37 (sig 19): ldrb w9, [x8, #4]       ; outerTopEdgeHoverState
    buf[n++] = 0x39400d08; // 38 (sig 20): ldrb w8, [x8, #3]       ; innerTopEdgeHoverState
    buf[n++] = 0x12001d08; // 39 (sig 21): and  w8, w8, #0xff
    buf[n++] = 0x2a080128; // 40 (sig 22): orr  w8, w9, w8
    buf[n++] = 0x7100011f; // 41 (sig 23): cmp  w8, #0
    buf[n++] = 0x52800028; // 42 (sig 24): mov  w8, #1
    buf[n++] = 0x1a880500; // 43 (sig 25): cinc w0, w8, ne
    buf[n++] = 0x17ffffe4; // 44 (sig 26): b    -0x70 -> 16        ; epilogue
    return n;
}

// Mirror of ARCUI.MouseListener's shared 0.08 s wait (used by TabHoverMenuController for pinned-tab cards and
// collapsed tab-group popovers). Must remain completely untouched when OpenSidebarInstantly is on.
static const uint32_t DPMouseListenerLoadDelay = 0x9e670100; // fmov d0, x8 (0.08 s)
static const uint32_t DPMouseListenerNoDelay = 0x9e6703e0;   // fmov d0, xzr (0.0 s)

static double DPMouseListenerStopDelay(uint32_t insn) {
    return insn == DPMouseListenerNoDelay ? 0.0 : 0.08;
}

// Models TabHoverMenuController's presentation & crossing decision driven by MouseListener's stop timer.
static BOOL DPSweepOpensImmediately(uint32_t mouseListenerInsn, double frameInterval, double hoverDelay) {
    double stopDelay = DPMouseListenerStopDelay(mouseListenerInsn);
    // While sweeping, mouseStopped fires only if stopDelay < frameInterval; otherwise hoverDelay governs.
    return stopDelay < frameInterval || hoverDelay <= frameInterval;
}

static BOOL DPCrossingDismissesCard(uint32_t mouseListenerInsn, double gapFrameInterval) {
    // Crossing the gap between a pinned tab / folder and its card/popover dismisses immediately only if mouseStopped
    // fires between frames while pointer is in the gap.
    return DPMouseListenerStopDelay(mouseListenerInsn) < gapFrameInterval;
}

static int failures;

static void check(const char *what, BOOL ok) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

static uint8_t *makeInfo(uint8_t out[7], uint8_t il, uint8_t ol, uint8_t sb, uint8_t it, uint8_t ot, uint8_t ts, uint8_t win) {
    out[0] = il; out[1] = ol; out[2] = sb; out[3] = it; out[4] = ot; out[5] = ts; out[6] = win;
    return out;
}

int main(void) {
    @autoreleasepool {
        Method addMonitor = class_getClassMethod(NSEvent.class, @selector(addLocalMonitorForEventsMatchingMask:handler:));
        origAddLocalMonitor = (void *)method_getImplementation(addMonitor);
        method_setImplementation(addMonitor, (IMP)DPTrackLocalMonitor);

        // Allocate an executable page holding both WindowController's hover stub and MouseListener's delay word.
        mach_vm_address_t page = 0;
        kern_return_t kr = mach_vm_allocate(mach_task_self(), &page, vm_page_size, VM_FLAGS_ANYWHERE);
        check("allocate executable test page", kr == KERN_SUCCESS);
        uint32_t *code = (uint32_t *)(uintptr_t)page;
        NSUInteger sigStart = 0;
        NSUInteger stubWords = DPBuildHoverStub(code, &sigStart);
        NSUInteger mlOffset = stubWords + 8;
        code[mlOffset] = DPMouseListenerLoadDelay;

        kr = mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        check("protect test page RX", kr == KERN_SUCCESS);
        sys_icache_invalidate(code, vm_page_size);

        uint32_t *found = DPFindSiteIn(code, mlOffset + 4);
        check("DPFindSiteIn finds exact hidden-edge check site", found == code + sigStart + DPSiteIndex);
        check("DPFindSiteIn rejects short buffer", DPFindSiteIn(code, DPSignatureCount - 1) == NULL);
        check("DPFindSiteIn rejects NULL buffer", DPFindSiteIn(NULL, 64) == NULL);

        uint32_t dupBuf[128] = {0};
        memcpy(dupBuf, code + sigStart, DPSignatureCount * sizeof(uint32_t));
        memcpy(dupBuf + 64, code + sigStart, DPSignatureCount * sizeof(uint32_t));
        check("DPFindSiteIn rejects ambiguous duplicate match", DPFindSiteIn(dupBuf, 128) == NULL);

        uint32_t exactBuf[sizeof DPSignature / sizeof *DPSignature];
        memcpy(exactBuf, code + sigStart, sizeof exactBuf);
        check("DPFindSiteIn matches exact-length buffer at index 0", DPFindSiteIn(exactBuf, DPSignatureCount) == exactBuf + DPSiteIndex);

        DPHoverDecisionFn decide = (DPHoverDecisionFn)(void *)code;
        uint8_t info[7];

        DPSite = NULL;
        DPSearched = NO;
        DPOpenSidebarInstantly.on = NO;
        check("verify off before locate returns nil", DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly) == nil);
        DPInstallOpenSidebarInstantly();
        check("install when off does not search or rewrite", !DPSearched && !DPSite && monitorCalls == 0);

        check("off: sidebar hidden + none -> hidden", decide(makeInfo(info, 0, 0, 0, 0, 0, 0, 1), 1, 1) == 1);
        check("off: sidebar hidden + innerLeft inside(1) -> stays hidden", decide(makeInfo(info, 1, 0, 0, 0, 0, 0, 1), 1, 1) == 1);
        check("off: sidebar hidden + outerLeft inside(1) -> stays hidden", decide(makeInfo(info, 0, 1, 0, 0, 0, 0, 0), 1, 1) == 1);
        check("off: sidebar hidden + innerLeft lingered(2) -> opens", decide(makeInfo(info, 2, 0, 0, 0, 0, 0, 1), 1, 1) == 2);
        check("off: sidebar hidden + outerLeft stopped(3) -> opens", decide(makeInfo(info, 0, 3, 0, 0, 0, 0, 0), 1, 1) == 2);
        check("off: top tab bar hidden + innerTop inside(1) -> stays hidden", decide(makeInfo(info, 0, 0, 0, 1, 0, 0, 1), 1, 0) == 1);
        check("off: top tab bar hidden + outerTop inside(1) -> stays hidden", decide(makeInfo(info, 0, 0, 0, 0, 1, 0, 0), 1, 0) == 1);

        DPSite = found;
        DPSearched = YES;
        DPOpenSidebarInstantly.on = YES;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("on: verify succeeds", DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly) == nil);
        check("on: installs zero NSEvent monitors", monitorCalls == 0);
        check("on: signature still uniquely matches patched instructions", DPFindSiteIn(code, mlOffset + 4) == found);

        check("on: sidebar hidden + none -> stays hidden", decide(makeInfo(info, 0, 0, 0, 0, 0, 0, 1), 1, 1) == 1);
        check("on: sidebar hidden + innerLeft inside(1) -> opens instantly", decide(makeInfo(info, 1, 0, 0, 0, 0, 0, 1), 1, 1) == 2);
        check("on: sidebar hidden + outerLeft inside(1) -> opens instantly", decide(makeInfo(info, 0, 1, 0, 0, 0, 0, 0), 1, 1) == 2);
        check("on: sidebar hidden + innerLeft lingered(2) -> opens", decide(makeInfo(info, 2, 0, 0, 0, 0, 0, 1), 1, 1) == 2);
        check("on: sidebar hidden + outerLeft stopped(3) -> opens", decide(makeInfo(info, 0, 3, 0, 0, 0, 0, 0), 1, 1) == 2);
        check("on: top tab bar hidden + none -> stays hidden", decide(makeInfo(info, 0, 0, 0, 0, 0, 0, 1), 1, 0) == 1);
        check("on: top tab bar hidden + innerTop inside(1) -> opens instantly", decide(makeInfo(info, 0, 0, 0, 1, 0, 0, 1), 1, 0) == 2);
        check("on: top tab bar hidden + outerTop inside(1) -> opens instantly", decide(makeInfo(info, 0, 0, 0, 0, 1, 0, 0), 1, 0) == 2);

        check("on: ARCUI.MouseListener 0.08 s delay instruction untouched", code[mlOffset] == DPMouseListenerLoadDelay);
        check("on: sweeping pinned tabs does not open hover card immediately", !DPSweepOpensImmediately(code[mlOffset], 0.016, 0.35));
        check("on: sweeping collapsed tab groups does not open folder popover immediately", !DPSweepOpensImmediately(code[mlOffset], 0.016, 0.35));
        // Contrast: the old MouseListener patch (0.0 s) WOULD have opened both mid-sweep.
        check("control: zeroing MouseListener caused #541 mid-sweep opens", DPSweepOpensImmediately(DPMouseListenerNoDelay, 0.016, 0.35));

        check("on: crossing gap into open card/popover does not trigger premature dismiss", !DPCrossingDismissesCard(code[mlOffset], 0.016));
        check("control: zeroing MouseListener caused #495 mid-crossing dismiss", DPCrossingDismissesCard(DPMouseListenerNoDelay, 0.016));
        check("on: revealed sidebar stays open while pointer inside sidebar(1)", decide(makeInfo(info, 0, 0, 1, 0, 0, 0, 1), 2, 1) == 2);
        check("on: revealed sidebar stays open while pointer in edge(1)", decide(makeInfo(info, 1, 0, 0, 0, 0, 0, 1), 2, 1) == 2);
        check("on: revealed sidebar closes once pointer leaves sidebar and edges", decide(makeInfo(info, 0, 0, 0, 0, 0, 0, 1), 2, 1) == 1);
        check("on: revealed top tab bar stays open while pointer inside tabStrip(1)", decide(makeInfo(info, 0, 0, 0, 0, 0, 1, 1), 2, 0) == 2);
        check("on: revealed top tab bar closes once pointer leaves tabStrip and edges", decide(makeInfo(info, 0, 0, 0, 0, 0, 0, 1), 2, 0) == 1);

        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("on: repeated apply is idempotent", DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly) == nil && found[0] == DPInstantInner && found[1] == DPInstantOuter);

        DPOpenSidebarInstantly.on = NO;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("paused/off: restores original instructions", found[0] == DPWaitInner && found[1] == DPWaitOuter);
        check("paused/off: verify succeeds", DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly) == nil);
        check("paused/off: innerLeft inside(1) waits again", decide(makeInfo(info, 1, 0, 0, 0, 0, 0, 1), 1, 1) == 1);
        check("paused/off: outerLeft inside(1) waits again", decide(makeInfo(info, 0, 1, 0, 0, 0, 0, 0), 1, 1) == 1);
        check("paused/off: innerTop inside(1) waits again", decide(makeInfo(info, 0, 0, 0, 1, 0, 0, 1), 1, 0) == 1);
        check("paused/off: repeated off apply is idempotent", (DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly), DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly) == nil));

        DPOpenSidebarInstantly.on = YES;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("unpaused: re-enables instant open", decide(makeInfo(info, 1, 0, 0, 0, 0, 0, 1), 1, 1) == 2 && DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly) == nil);
        DPOpenSidebarInstantly.on = NO;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);

        // Page-boundary rewrite safety: place DPSite at the last 4 bytes of page 0 so DPSite[1] is on page 1.
        mach_vm_address_t twoPages = 0;
        kr = mach_vm_allocate(mach_task_self(), &twoPages, 2 * vm_page_size, VM_FLAGS_ANYWHERE);
        check("allocate 2-page boundary buffer", kr == KERN_SUCCESS);
        uint32_t *boundarySite = (uint32_t *)(uintptr_t)(twoPages + vm_page_size - sizeof(uint32_t));
        boundarySite[0] = DPWaitInner;
        boundarySite[1] = DPWaitOuter;
        kr = mach_vm_protect(mach_task_self(), twoPages, 2 * vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        check("protect 2-page buffer RX", kr == KERN_SUCCESS);
        DPSite = boundarySite;
        DPOpenSidebarInstantly.on = YES;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("cross-page rewrite patches both words", boundarySite[0] == DPInstantInner && boundarySite[1] == DPInstantOuter && !DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly));
        DPOpenSidebarInstantly.on = NO;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("cross-page restore restores both words", boundarySite[0] == DPWaitInner && boundarySite[1] == DPWaitOuter && !DPVerifyOpenSidebarInstantly(&DPOpenSidebarInstantly));
        mach_vm_deallocate(mach_task_self(), twoPages, 2 * vm_page_size);

        DPSite = NULL;
        DPSearched = YES;
        DPOpenSidebarInstantly.unavailable = NO;
        DPOpenSidebarInstantly.on = YES;
        setPatchCalls = 0;
        DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
        check("missing site marks unavailable and turns off", DPOpenSidebarInstantly.unavailable && !DPOpenSidebarInstantly.on && setPatchCalls == 1 && !lastSetOn);

        mach_vm_deallocate(mach_task_self(), page, vm_page_size);
        printf("%s\n", failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
