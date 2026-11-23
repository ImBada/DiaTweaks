#import "StdPatch/StdPatch.h"

// Local tweaks are DPPatch entries built from DiaPatches/local/ against the headers inside the installed dylib,
// so a DiaTweaks update recompiles them and the updater never touches them.

NSUInteger DPLocalLoad(void);  // 0 when the folder is missing, empty, or Local Tweaks is off
DPPatch **DPLocalPatches(void);
void DPLocalRepairLinks(void);  // drops requires/disabledBy/coveredBy that dangle or loop
BOOL DPLocalTweaksEnabled(void);
void DPLocalReset(void);  // forget the cached load, for tests and Rebuild All

NSString *DPLocalFolder(void);
NSString *DPLocalCacheFolder(void);
NSString *DPLocalStatePath(void);

NSArray<NSDictionary *> *DPLocalItems(void);
NSString *DPLocalAdd(NSString *path, NSString **error);
void DPLocalWriteReadme(void);
BOOL DPLocalBuildAll(NSArray<NSString *> *names, NSString **report);
BOOL DPLocalBuildMain(NSArray<NSString *> *arguments);  // `diapatch local …`
int DPLocalBuildCommand(int argc, const char *const *argv);  // the C entry point `diapatch` looks up
NSArray<NSView *> *DPLocalRows(void);

NSArray<NSDictionary *> *DPLocalFileStamps(NSArray<NSString *> *sources);
BOOL DPLocalFilesMatch(NSArray<NSDictionary *> *saved, NSArray<NSString *> *sources);
NSDictionary *DPLocalSavedItem(NSString *identifier);
id DPLocalSavedValue(NSString *key);
NSString *DPLocalRun(NSArray<NSString *> *argv);

NSString *DPDylibUUID(void);
NSString *DPLocalHeaders(NSString **error);
NSDictionary *DPLocalToolchain(NSString **error);
NSDictionary *DPLocalToolchainSaved(void);
BOOL DPLocalCompile(NSArray<NSString *> *sources, NSArray<NSString *> *includeDirs, NSString *defines, NSString *output, NSString **error);

void DPLocalExtractPatch(NSString *patch, NSString *folder, NSString **error);
void DPLocalExtractArchive(NSString *archive, NSString *folder, NSString **error);

NSDictionary *DPLocalReadState(void);
BOOL DPLocalWriteState(NSArray<NSDictionary *> *items);
