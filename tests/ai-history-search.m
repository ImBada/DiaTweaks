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

DPPatch DPTurnOffAI;

#import "Patches/AIHistorySearch/AIHistorySearch.m"

// HistorySearchPrivacyController's site preference, in the order Dia stores it.
enum { DPHonorCacheControl = 0, DPAlwaysScrape = 1, DPNeverScrape = 2, DPInaccessible = 3, DPNoEntry = 4 };

// Mirrors the absent-site arm of the mapping the patch rewrites: a site with no memory_key_value_store entry
// resolves to .automatic/.include while the tweak is off and to .exclude while it is on. A stored entry always wins.
static uint32_t DPSitePreference(uint32_t stored, BOOL contentSafe, BOOL excluded) {
    if (stored != DPNoEntry) return stored;
    return excluded ? DPNeverScrape : (contentSafe ? DPAlwaysScrape : DPHonorCacheControl);
}

// Mirrors the address-bar site menu's toggle: 0 = included, 2 = excluded.
static uint32_t DPToggleState(uint32_t preference, BOOL contentSafe) {
    if (preference == DPAlwaysScrape) return 0;
    if (preference == DPHonorCacheControl) return contentSafe ? 0 : 2;
    return 2;
}

static NSUInteger DPBuildStub(uint32_t *buf, NSUInteger *syncStart, NSUInteger *asyncStart) {
    NSUInteger n = 0;
    *syncStart = n;
    for (NSUInteger i = 0; i < DPSyncSignatureCount; i++) buf[n++] = DPSyncSignature[i].value;
    while (n < 24) buf[n++] = 0xd503201f; // nop
    *asyncStart = n;
    for (NSUInteger copy = 0; copy < DPAsyncSites; copy++) {
        for (NSUInteger i = 0; i < DPAsyncSignatureCount; i++) buf[n++] = DPAsyncSignature[i].value;
        while (n % 24) buf[n++] = 0xd503201f;
    }
    while (n < 128) buf[n++] = 0xd503201f;
    return n;
}

static int failures;

static void check(const char *what, BOOL ok) {
    if (!ok) printf("FAIL: %s\n", what), failures++;
}

int main(void) {
    @autoreleasepool {
        mach_vm_address_t page = 0;
        kern_return_t kr = mach_vm_allocate(mach_task_self(), &page, vm_page_size, VM_FLAGS_ANYWHERE);
        check("allocate executable test page", kr == KERN_SUCCESS);
        uint32_t *code = (uint32_t *)(uintptr_t)page;
        NSUInteger syncStart = 0, asyncStart = 0;
        NSUInteger stubWords = DPBuildStub(code, &syncStart, &asyncStart);
        kr = mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        check("protect test page RX", kr == KERN_SUCCESS);
        sys_icache_invalidate(code, vm_page_size);

        // 1. Signature search: one sync site, two async sites, and rejection of short, NULL and ambiguous buffers.
        uint32_t *syncSites[1] = {NULL}, *asyncSites[DPAsyncSites] = {NULL, NULL};
        check("DPFindSitesIn finds the sync site", DPFindSitesIn(code, stubWords, DPSyncSignature, DPSyncSignatureCount, syncSites, DPSyncSiteIndex, 1) == 1);
        check("sync site is the absent-site immediate", syncSites[0] == code + syncStart + DPSyncSiteIndex && syncSites[0][0] == DPIncludedSync);
        check("DPFindSitesIn finds both async sites", DPFindSitesIn(code, stubWords, DPAsyncSignature, DPAsyncSignatureCount, asyncSites, DPAsyncSiteIndex, DPAsyncSites) == DPAsyncSites);
        check("async sites are the absent-site immediate", asyncSites[0] == code + asyncStart + DPAsyncSiteIndex && asyncSites[1] == code + asyncStart + 24 + DPAsyncSiteIndex);
        check("async sites both hold the included immediate", asyncSites[0][0] == DPIncludedAsync && asyncSites[1][0] == DPIncludedAsync);
        check("DPFindSitesIn rejects a short buffer", DPFindSitesIn(code, DPSyncSignatureCount - 1, DPSyncSignature, DPSyncSignatureCount, syncSites, DPSyncSiteIndex, 1) == 0);
        check("DPFindSitesIn rejects a NULL buffer", DPFindSitesIn(NULL, 64, DPSyncSignature, DPSyncSignatureCount, syncSites, DPSyncSiteIndex, 1) == 0);
        check("DPFindSitesIn rejects a NULL signature", DPFindSitesIn(code, stubWords, NULL, 0, syncSites, DPSyncSiteIndex, 1) == 0);

        uint32_t dupBuf[128] = {0};
        memcpy(dupBuf, code + syncStart, DPSyncSignatureCount * sizeof(uint32_t));
        memcpy(dupBuf + 64, code + syncStart, DPSyncSignatureCount * sizeof(uint32_t));
        check("DPFindSitesIn reports an ambiguous duplicate sync match", DPFindSitesIn(dupBuf, 128, DPSyncSignature, DPSyncSignatureCount, syncSites, DPSyncSiteIndex, 1) == 2);

        // 2. Baseline OFF: an unconfigured site is included, which is the bug the tweak fixes.
        DPSyncSite = NULL;
        DPAsyncSiteCount = 0;
        DPSearched = NO;
        DPExcludeSitesFromAIHistory.on = NO;
        check("verify off before locate returns nil", DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);
        DPInstallExcludeSitesFromAIHistory();
        check("install when off does not search or rewrite", !DPSearched && !DPSyncSite && code[syncStart + DPSyncSiteIndex] == DPIncludedSync);
        check("off: unconfigured safe site is included", DPToggleState(DPSitePreference(DPNoEntry, YES, NO), YES) == 0);
        check("off: unconfigured unsafe site is excluded", DPToggleState(DPSitePreference(DPNoEntry, NO, NO), NO) == 2);

        // 3. Turn ON: the sync and both async immediates become .exclude, and an unconfigured site is left out.
        check("re-find the sync site", DPFindSitesIn(code, stubWords, DPSyncSignature, DPSyncSignatureCount, syncSites, DPSyncSiteIndex, 1) == 1);
        check("re-find both async sites", DPFindSitesIn(code, stubWords, DPAsyncSignature, DPAsyncSignatureCount, asyncSites, DPAsyncSiteIndex, DPAsyncSites) == DPAsyncSites);
        DPSyncSite = syncSites[0];
        DPAsyncSite[0] = asyncSites[0];
        DPAsyncSite[1] = asyncSites[1];
        DPAsyncSiteCount = DPAsyncSites;
        DPSearched = YES;
        DPExcludeSitesFromAIHistory.on = YES;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("on: verify succeeds", DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);
        check("on: sync immediate is .exclude", code[syncStart + DPSyncSiteIndex] == DPExcludedSync);
        check("on: both async immediates are .exclude", code[asyncStart + DPAsyncSiteIndex] == DPExcludedAsync && code[asyncStart + 24 + DPAsyncSiteIndex] == DPExcludedAsync);
        check("on: unconfigured safe site is excluded", DPToggleState(DPSitePreference(DPNoEntry, YES, YES), YES) == 2);
        check("on: unconfigured unsafe site is excluded", DPToggleState(DPSitePreference(DPNoEntry, NO, YES), NO) == 2);

        // 4. Stored preferences are untouched, so manual per-site opt-in still works.
        check("on: stored honorCacheControl stays included", DPToggleState(DPSitePreference(DPHonorCacheControl, YES, YES), YES) == 0);
        check("on: stored alwaysScrape stays included", DPToggleState(DPSitePreference(DPAlwaysScrape, YES, YES), YES) == 0);
        check("on: stored neverScrape stays excluded", DPToggleState(DPSitePreference(DPNeverScrape, YES, YES), YES) == 2);
        check("on: stored inaccessible stays excluded", DPToggleState(DPSitePreference(DPInaccessible, YES, YES), YES) == 2);
        check("on: toggling a site on writes a stored entry that reads back included", DPToggleState(DPSitePreference(DPAlwaysScrape, YES, YES), YES) == 0);

        // 5. Idempotent re-apply, then off / DPPaused() restoration.
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("on: repeated apply is idempotent", DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil && code[syncStart + DPSyncSiteIndex] == DPExcludedSync);

        DPExcludeSitesFromAIHistory.on = NO;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("paused/off: restores the sync immediate", code[syncStart + DPSyncSiteIndex] == DPIncludedSync);
        check("paused/off: restores both async immediates", code[asyncStart + DPAsyncSiteIndex] == DPIncludedAsync && code[asyncStart + 24 + DPAsyncSiteIndex] == DPIncludedAsync);
        check("paused/off: verify succeeds", DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);
        check("paused/off: unconfigured safe site is included again", DPToggleState(DPSitePreference(DPNoEntry, YES, NO), YES) == 0);
        check("paused/off: repeated off apply is idempotent", (DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory), DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil));

        DPExcludeSitesFromAIHistory.on = YES;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("unpaused: excludes unconfigured sites again", DPToggleState(DPSitePreference(DPNoEntry, YES, YES), YES) == 2 && DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);
        DPExcludeSitesFromAIHistory.on = NO;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);

        // 6. Turn Off AI covers this tweak: it reaches the same instructions while its own switch is off.
        DPTurnOffAI.on = YES;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("turn off AI: excludes unconfigured sites with this switch off", !DPExcludeSitesFromAIHistory.on && code[syncStart + DPSyncSiteIndex] == DPExcludedSync && DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);
        DPTurnOffAI.on = NO;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("turn off AI off: restores Dia's default", code[syncStart + DPSyncSiteIndex] == DPIncludedSync && DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);

        // 7. A half-applied state is reported rather than silently accepted.
        check("half-apply the second async site", DPWrite(DPAsyncSite[1], DPIncludedAsync, DPExcludedAsync));
        check("verify reports disagreeing checks", [DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) isEqualToString:@"Dia's AI history search checks disagree"]);
        check("restore the second async site", DPWrite(DPAsyncSite[1], DPExcludedAsync, DPIncludedAsync));
        check("verify recovers once the checks agree", DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory) == nil);

        // 8. Page-boundary rewrite safety: put the sync site at the last 4 bytes of page 0.
        mach_vm_address_t twoPages = 0;
        kr = mach_vm_allocate(mach_task_self(), &twoPages, 2 * vm_page_size, VM_FLAGS_ANYWHERE);
        check("allocate 2-page boundary buffer", kr == KERN_SUCCESS);
        uint32_t *boundary = (uint32_t *)(uintptr_t)(twoPages + vm_page_size - sizeof(uint32_t));
        boundary[0] = DPIncludedSync;
        kr = mach_vm_protect(mach_task_self(), twoPages, 2 * vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        check("protect 2-page buffer RX", kr == KERN_SUCCESS);
        DPSyncSite = boundary;
        DPExcludeSitesFromAIHistory.on = YES;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("cross-page rewrite patches the site", boundary[0] == DPExcludedSync && !DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory));
        DPExcludeSitesFromAIHistory.on = NO;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("cross-page restore restores the site", boundary[0] == DPIncludedSync && !DPVerifyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory));
        mach_vm_deallocate(mach_task_self(), twoPages, 2 * vm_page_size);

        // 9. Unavailable fallback when Dia's binary doesn't match the signature.
        DPSyncSite = NULL;
        DPAsyncSiteCount = 0;
        DPSearched = YES;
        DPExcludeSitesFromAIHistory.unavailable = NO;
        DPExcludeSitesFromAIHistory.on = YES;
        setPatchCalls = 0;
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
        check("missing site marks unavailable and turns off", DPExcludeSitesFromAIHistory.unavailable && !DPExcludeSitesFromAIHistory.on && setPatchCalls == 1 && !lastSetOn);

        mach_vm_deallocate(mach_task_self(), page, vm_page_size);
        printf("%s\n", failures ? "FAIL" : "PASS");
        return failures ? 1 : 0;
    }
}
