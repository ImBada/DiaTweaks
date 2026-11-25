#import "StdPatch/StdPatch.h"

extern DPPatch DPDeleteProfileMenu;

// YES while Dia opens Settings for a delete: its window is hidden before AppKit orders it on screen.
extern BOOL DPOpeningHiddenSettings;

// DeleteProfileMenu.m: the window's profiles as Dia's scripting lists them, or nil in a private window.
NSArray *DPProfilesOf(NSWindow *window);

// Delete.m: runs Dia's own Delete Profile… from Settings › Profiles, with Settings kept out of sight.
void DPDeleteProfile(NSWindow *window, NSString *name, NSUInteger index, NSMenuItem *settings);
BOOL DPDeletingProfile(void);
void DPEndProfileDelete(void);
void DPFinishProfileDelete(BOOL closeSettings);

// Settings.m: the Settings window, hidden while a delete runs.
NSWindow *DPSettingsWindow(BOOL visibleOnly);
void DPHideSettings(NSWindow *settings);
void DPShowSettings(NSWindow *settings);
BOOL DPSettingsHidden(NSWindow *settings);
void DPInstallSettingsHooks(void);
