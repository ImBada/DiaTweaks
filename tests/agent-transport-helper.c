#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    alarm(15);
    const char *keep = getenv("KEEP");
    if (!keep || strcmp(keep, "preserved")) return 10;
#ifdef CONFIGURED_AGENT
    const char *overlay = getenv("AGENTS_DIR");
    if (!overlay || strcmp(overlay, "/synthetic/agents") || argc != 3 || strcmp(argv[2], overlay)) return 11;
#endif
    const char *path = getenv("AGENT_SERVER_SOCKET_PATH");
    if (!path) return 12;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    strlcpy(address.sun_path, path, sizeof address.sun_path);
    if (bind(fd, (struct sockaddr *)&address, SUN_LEN(&address)) || listen(fd, 2)) return 13;
    int client = accept(fd, NULL, NULL);
    if (client < 0) return 14;
    char buffer[512];
    ssize_t length;
    while ((length = read(client, buffer, sizeof buffer)) > 0)
        if (write(client, buffer, length) != length) return 15;
    close(client);
    close(fd);
    unlink(path);
    return 0;
}
