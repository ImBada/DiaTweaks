#import "StdPatch/StdPatch.h"
#import "Patches/TurnOffAI/TurnOffAI.h"
#import <libkern/OSCacheControl.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach/mach_vm.h>

extern DPPatch DPExcludeSitesFromAIHistory;

// HistorySearchPrivacyController reads a site with no stored preference as included. These immediates are that "absent" arm;
// rewriting them to .exclude leaves stored preferences alone.
static const uint32_t DPIncludedSync = 0x120002f6;   // and w22, w23, #0x1
static const uint32_t DPExcludedSync = 0x52800056;   // mov w22, #2
static const uint32_t DPIncludedAsync = 0x120002b4;  // and w20, w21, #0x1
static const uint32_t DPExcludedAsync = 0x52800054;  // mov w20, #2

typedef struct { uint32_t value, mask; } DPWord;

// eligibilitySync(for:) -> HistorySearchPrivacyController.eligibility, the check the address-bar site menu reads.
static const DPWord DPSyncSignature[] = {
    {0x910003e8, 0xffffffff},
    {0xd63f0120, 0xffffffff},
    {0xaa1603e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xa9405bf4, 0xffffffff},
    {0xaa1703e0, 0xffffffff},
    {0xaa1403e1, 0xffffffff},
    {0xaa1603e2, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa0003f7, 0xffffffff},
    {0xaa1603e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {DPIncludedSync, 0xffffffff},
};

// The same arm inlined into the async sitePreference(for:) / eligibility(for:) coroutine, which Dia emits twice.
static const DPWord DPAsyncSignature[] = {
    {0xa940cff4, 0xffffffff},
    {0x910982c0, 0xffffffff},
    {0xaa1403e1, 0xffffffff},
    {0xaa1303e2, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa0003f5, 0xffffffff},
    {0x3dc09ac0, 0xffffffff},
    {0x3d80c6c0, 0xffffffff},
    {0x910c42c0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa1703e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa1403e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {0xaa1303e0, 0xffffffff},
    {0x94000000, 0xfc000000},
    {DPIncludedAsync, 0xffffffff},
};

static const NSUInteger DPSyncSignatureCount = sizeof DPSyncSignature / sizeof *DPSyncSignature;
static const NSUInteger DPAsyncSignatureCount = sizeof DPAsyncSignature / sizeof *DPAsyncSignature;
static const NSUInteger DPSyncSiteIndex = DPSyncSignatureCount - 1;
static const NSUInteger DPAsyncSiteIndex = DPAsyncSignatureCount - 1;
#define DPAsyncSites 2

static uint32_t *DPSyncSite;
static uint32_t *DPAsyncSite[DPAsyncSites];
static NSUInteger DPAsyncSiteCount;
static BOOL DPSearched;

NSUInteger DPFindSitesIn(const uint32_t *text, NSUInteger words, const DPWord *signature, NSUInteger length,
                         uint32_t **sites, NSUInteger siteIndex, NSUInteger capacity) {
    if (!text || !signature || length < 1 || words < length) return 0;
    NSUInteger count = 0;
    for (NSUInteger i = 0; i + length <= words; i++) {
        BOOL match = YES;
        for (NSUInteger j = 0; j < length; j++)
            if ((text[i + j] & signature[j].mask) != signature[j].value) {
                match = NO;
                break;
            }
        if (!match) continue;
        if (count < capacity) sites[count] = (uint32_t *)(text + i + siteIndex);
        count++;
    }
    return count;
}

static BOOL DPLocate(void) {
    if (DPSearched) return DPSyncSite != NULL;
    DPSearched = YES;
    const struct mach_header_64 *header = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *image = _dyld_get_image_header(i);
        if (image && image->filetype == MH_EXECUTE) {
            header = (const struct mach_header_64 *)image;
            break;
        }
    }
    if (!header) return NO;
    unsigned long size = 0;
    const uint32_t *text = (const uint32_t *)getsectiondata(header, "__TEXT", "__text", &size);
    if (!text) return NO;
    NSUInteger words = size / sizeof *text;
    uint32_t *sync = NULL;
    if (DPFindSitesIn(text, words, DPSyncSignature, DPSyncSignatureCount, &sync, DPSyncSiteIndex, 1) != 1) return NO;
    DPAsyncSiteCount = DPFindSitesIn(text, words, DPAsyncSignature, DPAsyncSignatureCount, DPAsyncSite, DPAsyncSiteIndex, DPAsyncSites);
    if (DPAsyncSiteCount != DPAsyncSites) return NO;
    DPSyncSite = sync;
    return YES;
}

static BOOL DPWrite(uint32_t *site, uint32_t expected, uint32_t value) {
    if (!site || *site != expected) return NO;
    mach_vm_address_t page = (mach_vm_address_t)site & ~((mach_vm_address_t)vm_page_size - 1);
    if (mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return NO;
    *site = value;
    sys_icache_invalidate(site, sizeof *site);
    if (mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) return YES;
    *site = expected;
    sys_icache_invalidate(site, sizeof *site);
    mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return NO;
}

static BOOL DPWanted(void) {
    return DPExcludeSitesFromAIHistory.on || DPTurnOffAI.on;
}

static BOOL DPSitesHold(uint32_t sync, uint32_t async) {
    if (!DPSyncSite || *DPSyncSite != sync) return NO;
    for (NSUInteger i = 0; i < DPAsyncSiteCount; i++)
        if (DPAsyncSite[i][0] != async) return NO;
    return YES;
}

static BOOL DPIsExcluded(void) { return DPSitesHold(DPExcludedSync, DPExcludedAsync); }
static BOOL DPIsIncluded(void) { return DPSitesHold(DPIncludedSync, DPIncludedAsync); }

static void DPLogExcludeFailure(void) {
    NSLog(@"DiaPatches: Exclude Sites from AI History couldn't change Dia's history search check");
}

static void DPApplyExcludeSitesFromAIHistory(DPPatch *patch) {
    BOOL want = DPWanted();
    if (!want && !DPSyncSite) return;
    if (!DPLocate()) {
        if (!want) return;
        patch->unavailable = YES;
        if (!patch->on) return;
        DPSetPatch(patch, NO, !DPTesting);
        dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil]; });
        return;
    }
    if (want ? DPIsExcluded() : DPIsIncluded()) return;
    uint32_t from = want ? DPIncludedSync : DPExcludedSync, to = want ? DPExcludedSync : DPIncludedSync;
    uint32_t fromAsync = want ? DPIncludedAsync : DPExcludedAsync, toAsync = want ? DPExcludedAsync : DPIncludedAsync;
    if (!DPWrite(DPSyncSite, from, to)) return DPLogExcludeFailure();
    for (NSUInteger i = 0; i < DPAsyncSiteCount; i++) {
        if (DPWrite(DPAsyncSite[i], fromAsync, toAsync)) continue;
        DPWrite(DPSyncSite, to, from);
        for (NSUInteger j = 0; j < i; j++) DPWrite(DPAsyncSite[j], toAsync, fromAsync);
        return DPLogExcludeFailure();
    }
}

static void DPInstallExcludeSitesFromAIHistory(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:DPPatchesDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
    }];
    if (!DPWanted()) return;
    if (DPLocate()) return DPApplyExcludeSitesFromAIHistory(&DPExcludeSitesFromAIHistory);
    DPExcludeSitesFromAIHistory.unavailable = YES;
    DPExcludeSitesFromAIHistory.on = NO;
    NSLog(@"DiaPatches: Exclude Sites from AI History doesn't know this Dia's history search code, so it stays off");
}

static NSString *DPVerifyExcludeSitesFromAIHistory(DPPatch *patch) {
    BOOL want = DPWanted();
    if (!want && !DPSyncSite) return nil;
    if (!DPSyncSite) return @"Dia's AI history search check isn't where it was";
    BOOL excluded = DPIsExcluded(), included = DPIsIncluded();
    if (!excluded && !included) return @"Dia's AI history search checks disagree";
    if (want != excluded) return want ? @"new sites are still included in AI history search" : @"new sites are still excluded from AI history search";
    return nil;
}

DP_PATCH(DPExcludeSitesFromAIHistory) {
    .key = @"excludeSitesFromAIHistory",
    .order = 250,
    .title = @"Exclude Sites from AI History Search",
    .detail = @"Leave every site out of AI history search until you include it from the address bar. Sites you already included or excluded keep their setting. May need an update after some Dia releases.",
    .symbol = @"eye.slash.fill eye.slash",
    .tint = @"systemPurpleColor",
    .section = @"AI",
    .coveredBy = @"turnOffAI",
    .classes = DPClasses("_TtC13NavigationBar23NavigationBarController"),
    .install = DPInstallExcludeSitesFromAIHistory,
    .apply = DPApplyExcludeSitesFromAIHistory,
    .verify = DPVerifyExcludeSitesFromAIHistory,
};
