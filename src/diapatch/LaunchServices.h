#import <Foundation/Foundation.h>

// Call after launching or moving a Dia copy: Launch Services registers it under the bundle ID they all share.
void DPForgetApp(NSString *app);
// Call after a Dia copy takes the install's place, so Launch Services resolves the bundle ID to it.
void DPRegisterApp(NSString *app);
