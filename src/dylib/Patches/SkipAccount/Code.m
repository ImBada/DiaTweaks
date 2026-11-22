#import "Startup.h"
#import <libkern/OSCacheControl.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach/mach_vm.h>

static BOOL DPMatches(const uint32_t *code, const DPSkipInstruction *signature, NSUInteger length) {
    for (NSUInteger j = 0; j < length; j++)
        if ((code[j] & signature[j].mask) != signature[j].value) return NO;
    return YES;
}

BOOL DPSkipFindPatterns(DPSkipPattern *patterns, NSUInteger count) {
    const struct mach_header_64 *header = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++)
        if (_dyld_get_image_header(i)->filetype == MH_EXECUTE) { header = (const struct mach_header_64 *)_dyld_get_image_header(i); break; }
    if (!header || !count) return NO;
    unsigned long size = 0;
    const uint32_t *text = (const uint32_t *)getsectiondata(header, "__TEXT", "__text", &size);
    if (!text) return NO;
    NSUInteger words = size / sizeof *text;
    for (NSUInteger p = 0; p < count; p++) {
        if (!patterns[p].signature || !patterns[p].length) return NO;
        patterns[p].match = NULL;
    }

    for (NSUInteger i = 0; i < words; i++) {
        uint32_t first = text[i];
        for (NSUInteger p = 0; p < count; p++) {
            DPSkipPattern *pat = &patterns[p];
            if ((first & pat->signature[0].mask) != pat->signature[0].value) continue;
            if (i + pat->length > words || !DPMatches(text + i, pat->signature, pat->length)) continue;
            if (pat->match) return NO;
            pat->match = (uint32_t *)(text + i);
        }
    }
    for (NSUInteger p = 0; p < count; p++) if (!patterns[p].match) return NO;
    return YES;
}

BOOL DPSkipWriteCode(uint32_t *site, uint32_t expected, uint32_t value) {
    if (!site || *site != expected) return NO;
    mach_vm_address_t page = (mach_vm_address_t)site & ~((mach_vm_address_t)vm_page_size - 1);
    if (mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY)) return NO;
    *site = value;
    sys_icache_invalidate(site, sizeof *site);
    if (!mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE)) return YES;
    *site = expected;
    sys_icache_invalidate(site, sizeof *site);
    mach_vm_protect(mach_task_self(), page, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    return NO;
}
