#import "AgentSocket.h"
#import "AgentRelay.h"
#include <libproc.h>
#include <poll.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/socket.h>
#include <sys/stat.h>

static void DPConfigureAgentSocket(int fd) {
    struct timeval timeout = { .tv_sec = 15 };
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof timeout);
}

int DPAgentSocket(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd >= 0) DPConfigureAgentSocket(fd);
    return fd;
}

struct sockaddr_un DPAgentAddress(const char *path) {
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    strlcpy(address.sun_path, path, sizeof address.sun_path);
    address.sun_len = SUN_LEN(&address);
    return address;
}

static BOOL DPPeer(int fd, pid_t expected) {
    uid_t uid;
    gid_t gid;
    pid_t pid;
    socklen_t size = sizeof pid;
    return !getpeereid(fd, &uid, &gid) && uid == getuid() &&
        !getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) && pid == expected;
}

static int DPConnectAgent(NSString *path, pid_t child) {
    struct sockaddr_un address = DPAgentAddress(path.fileSystemRepresentation);
    for (int attempt = 0; attempt < 200 && !kill(child, 0); attempt++) {
        int fd = DPAgentSocket();
        if (fd < 0) break;
        if (!connect(fd, (struct sockaddr *)&address, address.sun_len) && DPPeer(fd, child)) return fd;
        close(fd);
        usleep(25000);
    }
    return -1;
}

static _Atomic NSUInteger DPActiveRelays;

BOOL DPAgentRelayRunning(void) { return atomic_load(&DPActiveRelays) != 0; }

BOOL DPAgentServerRunning(void) {
    static const char tail[] = "/agent-server-resources/dist/agent-server";
    pid_t children[512];
    int bytes = proc_listpids(PROC_PPID_ONLY, (uint32_t)getpid(), children, sizeof children);
    for (int i = 0; i < bytes / (int)sizeof *children; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        size_t length = proc_pidpath(children[i], path, sizeof path) > 0 ? strlen(path) : 0;
        if (length >= sizeof tail - 1 && !strcmp(path + length - (sizeof tail - 1), tail)) return YES;
    }
    return NO;
}

// Each connection is relayed on its own, so a chat that is still streaming never holds up the next one.
// Once the agent is gone nothing new is accepted, and its private folder goes when the last relay ends.
void DPRelayChatAgent(int listener, NSString *socket, NSString *directory, pid_t child, DPAgentConnected connected) {
    struct stat identity = {0};
    lstat(socket.fileSystemRepresentation, &identity);
    NSString *path = [directory stringByAppendingPathComponent:@"agent.sock"];
    atomic_fetch_add(&DPActiveRelays, 1);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_group_t connections = dispatch_group_create();
        struct pollfd event = { .fd = listener, .events = POLLIN };
        while (!kill(child, 0)) {
            int ready = poll(&event, 1, 500);
            if (ready < 0 && errno == EINTR) continue;
            if (ready < 0 || (event.revents & (POLLERR | POLLHUP | POLLNVAL))) break;
            if (!(event.revents & POLLIN)) continue;
            int client = accept(listener, NULL, NULL);
            if (client < 0) continue;
            DPConfigureAgentSocket(client);
            if (!DPPeer(client, getpid())) {
                close(client);
                continue;
            }
            dispatch_group_async(connections, queue, ^{
                int backend = DPConnectAgent(path, child);
                if (backend >= 0) {
                    if (connected) connected(directory);
                    DPRelayAgentConnection(client, backend);
                    close(backend);
                }
                close(client);
            });
        }
        struct stat current;
        if (!lstat(socket.fileSystemRepresentation, &current) &&
            current.st_dev == identity.st_dev && current.st_ino == identity.st_ino)
            unlink(socket.fileSystemRepresentation);
        close(listener);
        dispatch_group_wait(connections, DISPATCH_TIME_FOREVER);
        unlink(path.fileSystemRepresentation);
        rmdir(directory.fileSystemRepresentation);
        atomic_fetch_sub(&DPActiveRelays, 1);
    });
}
