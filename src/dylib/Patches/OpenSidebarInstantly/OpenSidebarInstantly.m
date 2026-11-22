#import "StdPatch/StdPatch.h"
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <libkern/OSCacheControl.h>

extern DPPatch DPOpenSidebarInstantly;

// WindowController opens a hidden sidebar or top tab bar only once an edge region reaches .hasLingered (2) or
// .hasStopped (3). Lowering those two hidden-state edge checks to > .none (0) opens on first touch without touching
// ARCUI.MouseListener's shared 0.08 s wait, which also drives pinned-tab cards and folder popovers.
static const uint32_t DPWaitInner = 0x7100051f;
static const uint32_t DPInstantInner = 0x7100011f;
static const uint32_t DPWaitOuter = 0x7a419922;
static const uint32_t DPInstantOuter = 0x7a409922;
static const NSUInteger DPSiteIndex = 9;
static uint32_t *DPSite;

static const struct { uint32_t value, mask; } DPSignature[] = {
    {0x8b080288, 0xffffffff},
    {0x39401509, 0xffffffff},
    {0x7100055f, 0xffffffff},
    {0x54000001, 0xff00001f},
    {0x7100053f, 0xffffffff},
    {0x54000008, 0xff00001f},
    {0x39401109, 0xffffffff},
    {0x39400d08, 0xffffffff},
    {0x12001d08, 0xffffffff},
    {0x00000000, 0x00000000},
    {0x00000000, 0x00000000},
    {0x52800028, 0xffffffff},
    {0x1a889500, 0xffffffff},
    {0x14000000, 0xfc000000},
    {0x35000009, 0xff00001f},
    {0x39400509, 0xffffffff},
    {0x39400108, 0xffffffff},
    {0x14000000, 0xfc000000},
    {0x35000009, 0xff00001f},
    {0x39401109, 0xffffffff},
    {0x39400d08, 0xffffffff},
    {0x12001d08, 0xffffffff},
    {0x2a080128, 0xffffffff},
    {0x7100011f, 0xffffffff},
    {0x52800028, 0xffffffff},
    {0x1a880500, 0xffffffff},
    {0x14000000, 0xfc000000},
};

static const NSUInteger DPSignatureCount = sizeof DPSignature / sizeof *DPSignature;

static BOOL DPMatchesAt(const uint32_t *code) {
    for (NSUInteger i = 0; i < DPSignatureCount; i++)
        if ((code[i] & DPSignature[i].mask) != DPSignature[i].value) return NO;
    return (code[DPSiteIndex] == DPWaitInner && code[DPSiteIndex + 1] == DPWaitOuter)
        || (code[DPSiteIndex] == DPInstantInner && code[DPSiteIndex + 1] == DPInstantOuter);
}

static NSUInteger DPSearch(const uint32_t *text, NSUInteger first, NSUInteger end, uint32_t **found) {
    NSUInteger count = 0;
    for (NSUInteger i = first; i < end; i++)
        if (DPMatchesAt(text + i)) count++, *found = (uint32_t *)(text + i + DPSiteIndex);
    return count;
}

static uint32_t *DPFindSiteIn(const uint32_t *text, NSUInteger words) {
    if (!text || words < DPSignatureCount) return NULL;
    NSUInteger limit = words - DPSignatureCount + 1, near = 0x18f0000, reach = 0x40000;
    uint32_t *found = NULL;
    if (near >= reach && reach <= limit && near <= limit - reach && DPSearch(text, near - reach, near + reach, &found) == 1) return found;
    return DPSearch(text, 0, limit, &found) == 1 ? found : NULL;
}

static uint32_t *DPFindSite(void) {
    const struct mach_header_64 *header = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *image = _dyld_get_image_header(i);
        if (image && image->filetype == MH_EXECUTE) {
            header = (const struct mach_header_64 *)image;
            break;
        }
    }
    if (!header) return NULL;
    unsigned long size = 0;
    const uint32_t *text = (const uint32_t *)getsectiondata(header, "__TEXT", "__text", &size);
    return DPFindSiteIn(text, size / 4);
}

static BOOL DPRewrite(uint32_t expected0, uint32_t expected1, uint32_t value0, uint32_t value1) {
    if (!DPSite || DPSite[0] != expected0 || DPSite[1] != expected1) return NO;
    mach_vm_address_t mask = (mach_vm_address_t)vm_page_size - 1;
    mach_vm_address_t start = (mach_vm_address_t)DPSite & ~mask;
    mach_vm_size_t len = (((mach_vm_address_t)(DPSite + 2) + mask) & ~mask) - start;
    if (mach_vm_protect(mach_task_self(), start, len, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return NO;
    DPSite[0] = value0;
    DPSite[1] = value1;
    sys_icache_invalidate(DPSite, 2 * sizeof *DPSite);
    if (mach_vm_protect(mach_task_self(), start, len, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) return YES;
    DPSite[0] = expected0;
    DPSite[1] = expected1;
    sys_icache_invalidate(DPSite, 2 * sizeof *DPSite);
    mach_vm_protect(mach_task_self(), start, len, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return NO;
}

static BOOL DPSearched;

static uint32_t *DPLocate(void) {
    if (!DPSearched) DPSite = DPFindSite(), DPSearched = YES;
    return DPSite;
}

static void DPApplyOpenSidebarInstantly(DPPatch *patch) {
    if (!patch->on) return (void)DPRewrite(DPInstantInner, DPInstantOuter, DPWaitInner, DPWaitOuter);
    if (DPLocate()) return (void)DPRewrite(DPWaitInner, DPWaitOuter, DPInstantInner, DPInstantOuter);
    patch->unavailable = YES;
    DPSetPatch(patch, NO, !DPTesting);
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil]; });
}

static void DPInstallOpenSidebarInstantly(void) {
    if (!DPOpenSidebarInstantly.on) return;
    if (DPLocate()) return DPApplyOpenSidebarInstantly(&DPOpenSidebarInstantly);
    DPOpenSidebarInstantly.unavailable = YES;
    DPOpenSidebarInstantly.on = NO;
    NSLog(@"DiaPatches: Open Sidebar Instantly doesn't know this Dia's sidebar code, so it stays off");
}

static NSString *DPVerifyOpenSidebarInstantly(DPPatch *patch) {
    if (!patch->on && !DPSite) return nil;
    if (!DPSite) return @"the sidebar hover check isn't where it was";
    BOOL fine = patch->on
        ? (DPSite[0] == DPInstantInner && DPSite[1] == DPInstantOuter)
        : (DPSite[0] == DPWaitInner && DPSite[1] == DPWaitOuter);
    return fine ? nil : patch->on ? @"the wait is still there" : @"the wait is gone";
}

DP_PATCH(DPOpenSidebarInstantly) {
    .key = @"openSidebarInstantly",
    .order = 116,
    .title = @"Open Sidebar Instantly",
    .detail = @"With the sidebar hidden, open it the moment the pointer reaches the left edge instead of after Dia's short wait. A hidden tab bar at the top shows sooner too. Dia's animation and how it closes stay as they are. May need an update after some Dia releases.",
    .symbol = @"arrow.right.to.line.circle.fill arrow.right.to.line",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .install = DPInstallOpenSidebarInstantly,
    .apply = DPApplyOpenSidebarInstantly,
    .verify = DPVerifyOpenSidebarInstantly,
};
