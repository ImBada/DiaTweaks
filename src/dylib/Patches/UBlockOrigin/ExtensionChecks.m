#import "UBlockOrigin.h"
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <libkern/OSCacheControl.h>

// Two checks in Chromium keep uBlock Origin from running, and Dia's build has neither's test-only switch, so each
// inlined copy's deciding branch is made unconditional in memory, as Helium does in source.
//
// Manifest V2: since Chromium 139, manifest_v2_util::IsExtensionAffected says an MV2 extension that isn't part of the
// browser is affected, and each caller disables it, refuses to load it or won't enable it again. A copy reads the
// version from the Extension, compares it with 2 and branches if greater; within a dozen instructions it reads a flag
// from the same Extension and compares the location with kExternalComponent (10):
//     ldr wV, [xE, #0x50]   cmp wV, #2   b.gt unaffected   ...   ldrb wT, [xE, #0x208]   ...   cmp/ccmp wL, #0xa
// That branch becomes b: every extension is unaffected.
//
// Developer mode: ExtensionManagement::IsAllowedByUnpackedDeveloperModePolicy disables unpacked extensions while
// developer mode is off. A --load-extension extension isn't unpacked until it reloads, which uBlock Origin does
// itself the first time it runs; Chromium then loads it again as unpacked and turns it off. A copy skips the
// preference when the extension came from DevTools, then reads the 28-character "extensions.ui.developer_mode":
//     ldrb wF, [xE, #0x24d]   tbnz wF, #7, allowed   ...   mov w2, #0x1c
// That branch becomes b: unpacked extensions run without developer mode, as they did before Chromium 136.

static NSString *const kCache = @"uBlockOriginExtensionChecks";  // @{uuid, offsets} so a launch needn't search again

static const uint32_t *gText;
static unsigned long gTextWords;
static NSArray<NSNumber *> *gSites;  // word offsets of each branch in gText

static BOOL DPIsManifestV2Branch(const uint32_t *code) {
    if ((code[0] & 0xFF00001F) != 0x5400000C || (code[-2] & 0xFFFFFC00) != 0xB9405000) return NO;  // b.gt; ldr wV, [xE, #0x50]
    uint32_t version = code[-2] & 31, extension = (code[-2] >> 5) & 31;
    if (code[-1] != (0x7100081F | version << 5)) return NO;  // cmp wV, #2
    BOOL flag = NO, location = NO;
    for (int i = 1; i < 13; i++) {
        flag |= (code[i] & 0xFFFFFFE0) == (0x39482000 | extension << 5);  // ldrb wT, [xE, #0x208]
        location |= (code[i] & 0xFFFFFC1F) == 0x7100281F || (code[i] & 0xFFFF0C10) == 0x7A4A0800;  // cmp/ccmp wL, #0xa
    }
    return flag && location;
}

static BOOL DPIsDeveloperModeBranch(const uint32_t *code) {
    if ((code[0] & 0xFFF80000) != 0x37380000 || (code[-1] & 0xFFFFFC00) != 0x39493400) return NO;  // tbnz wF, #7; ldrb [xE, #0x24d]
    if ((code[0] & 31) != (code[-1] & 31)) return NO;
    for (int i = 1; i < 13; i++)
        if (code[i] == 0x52800382) return YES;  // mov w2, #0x1c
    return NO;
}

static BOOL DPIsBranch(const uint32_t *code) { return DPIsManifestV2Branch(code) || DPIsDeveloperModeBranch(code); }

static NSString *DPImageUUID(const struct mach_header_64 *header) {
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize))
        if (command->cmd == LC_UUID) return [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
    return nil;
}

static BOOL DPHasBoth(NSArray<NSNumber *> *sites) {
    BOOL manifest = NO, developer = NO;
    for (NSNumber *site in sites) manifest |= DPIsManifestV2Branch(gText + site.unsignedLongValue), developer |= DPIsDeveloperModeBranch(gText + site.unsignedLongValue);
    return manifest && developer;
}

BOOL DPFindExtensionChecks(void) {
    if (gSites) return gSites.count > 0;
    gSites = @[];
    const struct mach_header_64 *arcCore = NULL;
    for (uint32_t i = 0; i < _dyld_image_count() && !arcCore; i++)
        if ([@(_dyld_get_image_name(i)) hasSuffix:@"/ArcCore.framework/Versions/A/ArcCore"]) arcCore = (const void *)_dyld_get_image_header(i);
    unsigned long size = 0;
    if (!arcCore || !(gText = (const uint32_t *)getsectiondata(arcCore, "__TEXT", "__text", &size)) || size < 64 * 4) return NO;
    gTextWords = size / 4 - 13;

    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"];
    NSDictionary *cache = [settings dictionaryForKey:kCache];
    NSString *uuid = DPImageUUID(arcCore);
    if ([cache[@"uuid"] isEqual:uuid] && [cache[@"offsets"] isKindOfClass:NSArray.class]) {
        BOOL valid = YES;
        for (NSNumber *offset in cache[@"offsets"])
            valid &= [offset isKindOfClass:NSNumber.class] && offset.unsignedLongValue >= 2 && offset.unsignedLongValue < gTextWords
                     && DPIsBranch(gText + offset.unsignedLongValue);
        if (valid && DPHasBoth(cache[@"offsets"])) return (gSites = cache[@"offsets"]).count > 0;
    }
    NSMutableArray<NSNumber *> *sites = [NSMutableArray array];
    for (unsigned long i = 2; i < gTextWords; i++)
        if (DPIsBranch(gText + i)) [sites addObject:@(i)];
    if (sites.count > 24 || !DPHasBoth(sites)) [sites removeAllObjects];  // missing one, or matched what it shouldn't
    if (uuid) [settings setObject:@{ @"uuid" : uuid, @"offsets" : sites } forKey:kCache];
    return (gSites = sites).count > 0;
}

static BOOL DPWrite(uint32_t *site, uint32_t value) {
    mach_vm_address_t page = (mach_vm_address_t)site & ~((mach_vm_address_t)vm_page_size - 1);
    if (mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)) return NO;
    *site = value;
    BOOL executable = mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS;
    sys_icache_invalidate(site, sizeof *site);
    return executable;
}

// The same branch as an unconditional b, or 0 if it isn't one of the two kinds.
static uint32_t DPUnconditional(uint32_t branch) {
    int32_t words;
    if ((branch & 0xFF000010) == 0x54000000) words = (int32_t)(branch << 8) >> 13;  // b.cond: signed imm19
    else if ((branch & 0x7E000000) == 0x36000000) words = (int32_t)(branch << 13) >> 18;  // tbnz: signed imm14
    else return 0;
    return 0x14000000 | ((uint32_t)words & 0x3FFFFFF);
}

// All of them or none: with only some lifted, other extensions would run while uBlock Origin doesn't load.
BOOL DPLiftExtensionChecks(void) {
    if (!DPFindExtensionChecks()) return NO;
    NSUInteger count = gSites.count, done = 0;
    uint32_t original[count];
    for (; done < count; done++) {
        uint32_t *site = (uint32_t *)gText + gSites[done].unsignedLongValue, branch = DPUnconditional(*site);
        original[done] = *site;
        if (!branch || !DPWrite(site, branch)) break;
    }
    if (done == count) return YES;
    NSLog(@"DiaPatches: couldn’t lift Chromium’s extension checks; leaving them as they were");
    for (NSUInteger i = 0; i <= done; i++) {  // the one that failed too, in case only its protection did
        uint32_t *site = (uint32_t *)gText + gSites[i].unsignedLongValue;
        if (*site != original[i]) DPWrite(site, original[i]);
    }
    return NO;
}
