#import "SidebarAddressBar.h"
#import "NativeSlot.h"

enum { DPAddressGridDividerPadding = 14 };

@interface DPAddressNativeControls : NSObject
@property(weak) NSView *toolbar;
@property DPAddressNativeSlot *more, *extensions;
@property NSScrollView *scroll;
@property NSButton *extensionsButton;
@property NSBox *gridDivider;
@property(weak) NSCollectionView *gridCollection;
@property NSCollectionViewLayout *nativeGridLayout;
@property NSView *nativeGridBackground;
@property NSRect nativeGridFrame;
@property CGFloat gridHeight;
@end

DPAddressNativeControls *DPAddressControlsFor(NSView *row, BOOL create);
void DPCreateAddressExtensionsHost(DPAddressNativeControls *controls);
extern DPPatch DPSidebarExtensionsOnHover;

extern DPPatch DPSidebarExtensionTiles, DPSidebarExtensionsMenuOnly, DPSidebarExtensionDivider;
CGFloat DPAddressLayoutGrid(DPAddressNativeControls *, DPSidebarAddressRow *, NSUInteger);
void DPAddressRestoreGrid(DPAddressNativeControls *);


void DPAddressInstallSiteMenuHooks(NSView *);
void DPAddressAddPageMenuItems(NSMenu *, DPSidebarAddressRow *, NSInteger);
