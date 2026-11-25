#import "StdPatch/StdPatch.h"

NSUInteger DPLocalLoad(void);
DPPatch **DPLocalPatches(void);
void DPLocalRepairLinks(void);
BOOL DPLocalTweaksEnabled(void);
void DPLocalReset(void);

NSSet<NSString *> *DPLocalOfficialKeySet(void);

NSString *DPLocalFolder(void);
NSString *DPLocalCacheFolder(void);
NSString *DPLocalStatePath(void);
NSString *DPLocalStamp(NSString *path);

NSArray<NSDictionary *> *DPLocalItems(void);
NSString *DPLocalAdd(NSString *path, NSString **error);
void DPLocalWriteReadme(void);
BOOL DPLocalBuildAll(NSArray<NSString *> *names, NSString **report);
BOOL DPLocalBuildAllForced(NSArray<NSString *> *names, BOOL force, NSString **report);
BOOL DPLocalBuild(BOOL force, NSString **report);
BOOL DPLocalBuildNames(NSArray<NSString *> *names, BOOL force, NSString **report);  // in the installed diapatch, so a fresh build never loads into Dia
BOOL DPLocalBuildMain(NSArray<NSString *> *arguments);
int DPLocalBuildCommand(int argc, const char *const *argv);
NSArray<NSView *> *DPLocalRows(void);

NSArray<NSDictionary *> *DPLocalFileStamps(NSArray<NSString *> *sources);
BOOL DPLocalFilesMatch(NSArray<NSDictionary *> *saved, NSArray<NSString *> *sources);
NSDictionary *DPLocalSavedItem(NSString *identifier);
id DPLocalSavedValue(NSString *key);
NSString *DPLocalRun(NSArray<NSString *> *argv);
int DPLocalExec(NSArray<NSString *> *argv, NSString **output);

NSString *DPLocalDigest(NSData *data);
NSString *DPDylibUUID(void);
NSString *DPLocalHeaders(NSString **error);
NSDictionary *DPLocalToolchain(NSString **error);
NSDictionary *DPLocalToolchainSaved(void);
NSString *DPLocalEnsurePCH(BOOL buildIfMissing);
BOOL DPLocalCompile(NSArray<NSString *> *sources, NSArray<NSString *> *includeDirs, NSString *defines, NSString *pch, NSString *output, NSString **error);

void DPLocalExtractPatch(NSString *patch, NSString *folder, NSString **error);
void DPLocalExtractArchive(NSString *archive, NSString *folder, NSString **error);

NSDictionary *DPLocalReadState(void);
BOOL DPLocalWriteState(NSArray<NSDictionary *> *items);
NSDictionary *DPLocalUpdateState(NSArray<NSDictionary *> *items, NSDictionary *saved);

NSArray<NSDictionary *> *DPLocalCachedCatalog(void);
NSArray<NSDictionary *> *DPLocalFetchCatalog(NSString **error);  // a missing index is an empty catalog; any other failure is nil and keeps the cache
NSArray<NSDictionary *> *DPLocalAvailableCatalog(NSArray<NSDictionary *> *catalog);
NSArray<NSDictionary *> *DPLocalAvailableCatalogForItems(NSArray<NSDictionary *> *catalog, NSArray<NSDictionary *> *items);
NSDictionary *DPLocalPrimaryPatch(NSDictionary *entry);
BOOL DPLocalIsBuiltIn(NSDictionary *entry);
BOOL DPLocalIsCatalogItemInstalled(NSDictionary *entry, NSArray<NSDictionary *> *localItems);
BOOL DPLocalInstallCatalogItem(NSDictionary *entry, NSString **error);
BOOL DPLocalInstallCatalogItems(NSArray<NSDictionary *> *entries, NSString **error);
