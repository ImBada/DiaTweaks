#import "StdPatch/StdPatch.h"
#import <libkern/OSCacheControl.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach/mach_vm.h>

extern DPPatch DPNarrowerSidebar;

// ARM64 mov/movk encoding 190.0 -> 164.0 for Dia's sidebar width clamp.
static const uint32_t DPSidebarClampWide[4] = { 0xd2d80008, 0xf2e80ce8, 0x9e670101, 0x1e616800 };
static const uint32_t DPSidebarClampNarrow[4] = { 0xd2d00008, 0xf2e80c88, 0x9e670101, 0x1e616800 };

static uint32_t *DPSidebarClamp(void) {
    static uint32_t *site;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const struct mach_header_64 *header = NULL;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const struct mach_header *image = _dyld_get_image_header(i);
            if (image && image->filetype == MH_EXECUTE) {
                header = (const struct mach_header_64 *)image;
                break;
            }
        }
        if (!header) return;
        unsigned long size = 0;
        uint32_t *text = (uint32_t *)getsectiondata(header, "__TEXT", "__text", &size);
        NSUInteger found = 0;
        for (NSUInteger i = 0; text && i + 4 <= size / 4; i++)
            if (text[i] == DPSidebarClampWide[0] && !memcmp(text + i, DPSidebarClampWide, sizeof DPSidebarClampWide)) found++, site = text + i;
        if (found != 1) site = NULL;
    });
    return site;
}

static BOOL DPIsSidebarClamp(const uint32_t words[4]) {
    uint32_t *site = DPSidebarClamp();
    return site && memcmp(site, words, 4 * sizeof(uint32_t)) == 0;
}

static BOOL DPWriteSidebarClamp(const uint32_t words[4]) {
    uintptr_t page = vm_page_size, address = (uintptr_t)DPSidebarClamp();
    if (!address) return NO;
    uintptr_t start = address & ~(page - 1), end = (address + 4 * sizeof(uint32_t) + page - 1) & ~(page - 1);
    uint32_t previous[4];
    memcpy(previous, (const void *)address, sizeof previous);
    if (mach_vm_protect(mach_task_self(), start, end - start, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) return NO;
    memcpy((void *)address, words, 4 * sizeof(uint32_t));
    sys_icache_invalidate((void *)address, 4 * sizeof(uint32_t));
    if (mach_vm_protect(mach_task_self(), start, end - start, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS) return YES;
    memcpy((void *)address, previous, sizeof previous);
    sys_icache_invalidate((void *)address, 4 * sizeof(uint32_t));
    mach_vm_protect(mach_task_self(), start, end - start, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return NO;
}

static BOOL DPIsNarrow(void) { return DPIsSidebarClamp(DPSidebarClampNarrow); }

static BOOL DPKnowsSidebarClamp(void) { return DPIsSidebarClamp(DPSidebarClampWide) || DPIsNarrow(); }

static void DPApplyNarrowerSidebar(DPPatch *patch) {
    if (!DPKnowsSidebarClamp()) return (void)NSLog(@"DiaPatches: Narrower Sidebar found no sidebar clamp to change");
    if (patch->on == DPIsNarrow()) return;
    if (!DPWriteSidebarClamp(patch->on ? DPSidebarClampNarrow : DPSidebarClampWide))
        NSLog(@"DiaPatches: Narrower Sidebar couldn't change the sidebar clamp");
}

static void DPInstallNarrowerSidebar(void) {
    if (!DPKnowsSidebarClamp()) {
        DPNarrowerSidebar.unavailable = YES;
        DPNarrowerSidebar.on = NO;
        return (void)NSLog(@"DiaPatches: Narrower Sidebar doesn't know this Dia's resize code, so it stays off");
    }
    DPApplyNarrowerSidebar(&DPNarrowerSidebar);
}

static NSString *DPVerifyNarrowerSidebar(DPPatch *patch) {
    if (!DPKnowsSidebarClamp()) return @"Dia's sidebar clamp isn't where this patch expects it";
    if (patch->on != DPIsNarrow()) return patch->on ? @"the sidebar still stops at 190" : @"the sidebar still stops at 164";
    return nil;
}

DP_PATCH(DPNarrowerSidebar) {
    .key = @"narrowerSidebar",
    .order = 78,
    .title = @"Narrower Sidebar",
    .detail = @"Let the sidebar shrink to 164 points, so favorites sit two to a row.",
    .symbol = @"arrow.left.and.right.square",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaSidebarController),
    .install = DPInstallNarrowerSidebar,
    .apply = DPApplyNarrowerSidebar,
    .verify = DPVerifyNarrowerSidebar,
};
