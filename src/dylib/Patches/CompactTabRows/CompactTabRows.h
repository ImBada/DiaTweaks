#import "StdPatch/StdPatch.h"

CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y);
id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location);
void DPPlaceDraggedTab(void);
void DPClearDraggedTab(void);
CGFloat DPCompactRowHeight(void);
CGFloat DPModalItemHeight(NSArray<NSCollectionViewLayoutAttributes *> *attributes, CGFloat minimum);
NSArray *DPEveryView(const char *className);
