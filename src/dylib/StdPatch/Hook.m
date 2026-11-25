#import "StdPatch/StdPatch.h"
#import <os/lock.h>
#import <stdatomic.h>

typedef struct { Class cls; SEL sel; IMP replacement; _Atomic(IMP) original; } DPHookRecord;
// Writers serialize on DPHookLock while any thread reads lock-free; the table never moves and a record counts only once whole.
// DPHookSlots holds each record's index + 1, found by (cls, sel, replacement) so a lookup never scans the table.
static DPHookRecord DPHooks[1024];
static _Atomic(uint16_t) DPHookSlots[4096];
static _Atomic size_t DPHookCount;
static os_unfair_lock DPHookLock = OS_UNFAIR_LOCK_INIT;
static _Thread_local DPHookFrame *DPActiveFrame;

static BOOL DPInherits(Class cls, Class ancestor) {
    for (Class c = cls; c; c = class_getSuperclass(c))
        if (c == ancestor) return YES;
    return NO;
}

static size_t DPSlotOf(Class cls, SEL sel, IMP replacement) {
    uint64_t h = (uintptr_t)(__bridge void *)cls * 0x9E3779B97F4A7C15u ^ (uintptr_t)(const void *)sel * 0xC2B2AE3D27D4EB4Fu ^ (uintptr_t)replacement * 0x165667B19E3779F9u;
    return h >> 52;
}

static DPHookRecord *DPRecordAt(Class cls, SEL sel, IMP replacement) {
    for (size_t i = DPSlotOf(cls, sel, replacement);; i = (i + 1) % (sizeof DPHookSlots / sizeof *DPHookSlots)) {
        uint16_t entry = atomic_load_explicit(&DPHookSlots[i], memory_order_acquire);
        if (!entry) return NULL;
        DPHookRecord *record = &DPHooks[entry - 1];
        if (record->cls == cls && record->sel == sel && record->replacement == replacement) return record;
    }
}

// Records only ever join the table, so an answer holds until the count moves.
static DPHookRecord *DPNearestRecord(Class start, SEL sel, IMP replacement) {
    static _Thread_local struct { Class start; SEL sel; IMP replacement; DPHookRecord *record; size_t count; } memo[32];
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    __typeof__(*memo) *entry = &memo[DPSlotOf(start, sel, replacement) % (sizeof memo / sizeof *memo)];
    if (entry->count == count && entry->start == start && entry->sel == sel && entry->replacement == replacement) return entry->record;
    DPHookRecord *record = NULL;
    for (Class c = start; c && !record; c = class_getSuperclass(c)) record = DPRecordAt(c, sel, replacement);
    *entry = (__typeof__(*entry)){start, sel, replacement, record, count};
    return record;
}

void DPHookClass(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement || DPNearestRecord(cls, sel, replacement)) return;
    os_unfair_lock_lock(&DPHookLock);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return os_unfair_lock_unlock(&DPHookLock);
    IMP original = method_getImplementation(method);
    // Already hooked here or in a superclass: a second copy would double-run or recurse.
    if (original == replacement || DPNearestRecord(cls, sel, replacement)) return os_unfair_lock_unlock(&DPHookLock);
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_relaxed);
    if (count == sizeof DPHooks / sizeof *DPHooks) {
        os_unfair_lock_unlock(&DPHookLock);
        return NSLog(@"DiaPatches: hook table is full; not hooking -[%s %@]", class_getName(cls), NSStringFromSelector(sel));
    }
    // The record goes in first: once the replacement is live, any thread that reaches it must find it.
    DPHookRecord *added = &DPHooks[count];
    added->cls = cls;
    added->sel = sel;
    added->replacement = replacement;
    atomic_store_explicit(&added->original, original, memory_order_relaxed);
    size_t slot = DPSlotOf(cls, sel, replacement);
    while (atomic_load_explicit(&DPHookSlots[slot], memory_order_relaxed)) slot = (slot + 1) % (sizeof DPHookSlots / sizeof *DPHookSlots);
    atomic_store_explicit(&DPHookSlots[slot], (uint16_t)(count + 1), memory_order_release);
    atomic_store_explicit(&DPHookCount, count + 1, memory_order_release);
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(method, replacement);
    // Re-chain any subclass that copied cls's inherited IMP earlier so it still calls through this hook,
    // unless that subclass (or an intermediate below cls) already hooks the same replacement.
    for (size_t i = 0; i < count; i++) {
        Class sub = DPHooks[i].cls;
        if (DPHooks[i].sel != sel || DPHooks[i].replacement == replacement || sub == cls || !DPInherits(sub, cls)) continue;
        if (atomic_load_explicit(&DPHooks[i].original, memory_order_relaxed) != original) continue;
        if (DPNearestRecord(sub, sel, replacement) == added) atomic_store_explicit(&DPHooks[i].original, replacement, memory_order_release);
    }
    os_unfair_lock_unlock(&DPHookLock);
}

void DPHook(const char *className, SEL sel, IMP replacement) {
    Class cls = className ? objc_getClass(className) : Nil;
    if (!class_getInstanceMethod(cls, sel)) NSLog(@"DiaPatches: can't hook -[%s %@]; Dia may have renamed it", className ?: "(null)", NSStringFromSelector(sel));
    else DPHookClass(cls, sel, replacement);
}

static IMP DPFindOriginal(Class start, SEL sel, IMP replacement, Class *matched) {
    DPHookRecord *record = DPNearestRecord(start, sel, replacement);
    if (matched) *matched = record ? record->cls : Nil;
    return record ? atomic_load_explicit(&record->original, memory_order_acquire) : NULL;
}

IMP DPOriginalIMP(id object, SEL sel, IMP replacement) {
    IMP imp = DPFindOriginal(object_getClass(object), sel, replacement, NULL);
    if (imp) return imp;
    abort();
}

IMP DPPushOriginalIMP(id object, SEL sel, IMP replacement, DPHookFrame *frame) {
    const void *target = (__bridge const void *)object;
    Class start = object_getClass(object), matched = Nil;
    IMP imp = NULL;
    // When a subclass hooked before its superclass calls [super sel], step above the active class instead of recursing.
    for (DPHookFrame *active = DPActiveFrame; active; active = active->previous) {
        if (active->object == target && active->sel == sel && active->replacement == replacement) {
            Class super = class_getSuperclass(active->cls);
            if (super) imp = DPFindOriginal(super, sel, replacement, &matched);
            break;
        }
    }
    if (!imp) imp = DPFindOriginal(start, sel, replacement, &matched);
    if (!imp) abort();
    *frame = (DPHookFrame){target, sel, replacement, matched, DPActiveFrame};
    DPActiveFrame = frame;
    return imp;
}

void DPPopOriginalIMP(DPHookFrame *frame) {
    DPActiveFrame = frame->previous;
}

BOOL DPIsHooked(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement) return NO;
    IMP current = class_getMethodImplementation(cls, sel);
    if (current == replacement) return YES;
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    for (size_t hops = 0; hops < count && current; hops++) {
        IMP next = DPFindOriginal(cls, sel, current, NULL);
        if (!next) break;
        if (next == replacement) return YES;
        current = next;
    }
    return NO;
}

IMP DPDiaIMP(Class cls, SEL sel) {
    if (!cls || !sel) return NULL;
    size_t count = atomic_load_explicit(&DPHookCount, memory_order_acquire);
    IMP imp = NULL;
    for (Class c = cls; c && !imp; c = class_getSuperclass(c)) {
        for (size_t i = 0; i < count; i++)
            if (DPHooks[i].cls == c && DPHooks[i].sel == sel) {
                imp = atomic_load_explicit(&DPHooks[i].original, memory_order_acquire);
                break;
            }
        if (imp) break;
        Method own = class_getInstanceMethod(c, sel);
        Class super = class_getSuperclass(c);
        if (own && (!super || own != class_getInstanceMethod(super, sel)))
            return method_getImplementation(own);
    }
    if (!imp) return class_getMethodImplementation(cls, sel);
    for (size_t hops = 0; hops < count; hops++) {
        IMP next = NULL;
        for (size_t i = 0; i < count && !next; i++)
            if (DPHooks[i].sel == sel && DPHooks[i].replacement == imp && DPInherits(cls, DPHooks[i].cls))
                next = atomic_load_explicit(&DPHooks[i].original, memory_order_acquire);
        if (!next) break;
        imp = next;
    }
    return imp;
}
