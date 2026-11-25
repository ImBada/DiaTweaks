#import <Foundation/Foundation.h>
#import <spawn.h>

// Spawns a Dia copy that macOS holds responsible for itself, so privacy prompts name the copy, not Dia.
// Each "NAME=value" in overrides replaces the inherited NAME.
pid_t DPSpawnDisclaimed(const char *const argv[], NSArray<NSString *> *overrides, const posix_spawn_file_actions_t *files);
