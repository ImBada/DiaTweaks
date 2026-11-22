#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>

@interface DPNativeChatModelCatalog : NSObject
+ (NSArray<NSString *> *)modelsInType:(NSUInteger)metadata;
@end

// Swift ABI nominal descriptors and blocking-complete metadata requests:
// https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst
// Dia's release types aren't available through Swift's name lookup.
typedef struct { uint32_t flags; int32_t parent, name, accessor, fields; } DPModelDescriptor;
typedef struct { const void *value; uintptr_t state; } DPModelMetadata;
typedef DPModelMetadata (__attribute__((swiftcall)) *DPModelAccessor)(uintptr_t request);

static const void *DPModelRelative(const int32_t *field) {
    return *field ? (const char *)field + *field : NULL;
}

static NSArray<NSString *> *DPScanChatModels(void) {
    for (uint32_t image = 0; image < _dyld_image_count(); image++) {
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(image);
        if (header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE) continue;
        unsigned long size = 0;
        const int32_t *types = (const void *)getsectiondata(header, "__TEXT", "__swift5_types", &size);
        for (NSUInteger index = 0; index < size / sizeof *types; index++) {
            const DPModelDescriptor *type = DPModelRelative(&types[index]);
            if (!type || ((uintptr_t)type & 3)) continue;
            // Enum, non-generic, descriptor version zero. Unknown layouts stay native.
            if ((type->flags & 0x1f) != 18 || (type->flags & 0xff80)) continue;
            const char *name = DPModelRelative(&type->name);
            if (!name || strcmp(name, "ChatResponseModel")) continue;
            DPModelAccessor accessor = (DPModelAccessor)DPModelRelative(&type->accessor);
            if (!accessor) continue;
            DPModelMetadata metadata = accessor(0);
            if (!metadata.value || metadata.state) continue;
            NSArray *models = [DPNativeChatModelCatalog modelsInType:(NSUInteger)metadata.value];
            if (models.count) return models;
        }
    }
    return @[];
}

// Dia's catalog is fixed for a build, so a found list is kept. An empty one is looked for again a few times before it's trusted.
NSArray<NSString *> *DPInstalledChatModels(void) {
    static NSArray<NSString *> *found;
    static NSUInteger misses;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    @synchronized (lock) {
        if (found && (found.count || misses >= 3)) return found;
        found = DPScanChatModels();
        if (!found.count) misses++;
        return found;
    }
}
