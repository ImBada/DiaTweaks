#import "Disclaim.h"

extern char **environ;
int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim);

static BOOL overridden(const char *entry, const char *const *overrides, NSUInteger count) {
    for (NSUInteger i = 0; i < count; i++)
        if (!strncmp(entry, overrides[i], strcspn(overrides[i], "=") + 1)) return YES;
    return NO;
}

pid_t DPSpawnDisclaimed(const char *const argv[], NSArray<NSString *> *overrides, const posix_spawn_file_actions_t *files) {
    size_t count = 0;
    while (environ[count]) count++;
    const char **envp = calloc(overrides.count + count + 1, sizeof *envp);
    if (!envp) return 0;
    size_t used = 0;
    for (NSString *entry in overrides) envp[used++] = entry.UTF8String;
    for (size_t i = 0; i < count; i++)
        if (!overridden(environ[i], envp, overrides.count)) envp[used++] = environ[i];

    posix_spawnattr_t attrs;
    posix_spawnattr_init(&attrs);
    posix_spawnattr_setflags(&attrs, POSIX_SPAWN_CLOEXEC_DEFAULT);
    responsibility_spawnattrs_setdisclaim(&attrs, 1);
    pid_t pid = 0;
    int status = posix_spawn(&pid, argv[0], files, &attrs, (char *const *)argv, (char *const *)envp);
    posix_spawnattr_destroy(&attrs);
    free(envp);
    return status == 0 ? pid : 0;
}
