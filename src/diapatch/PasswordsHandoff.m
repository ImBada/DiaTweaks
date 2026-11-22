#import <sys/socket.h>
#import <sys/un.h>
#import "Passwords.h"
#import "PasswordsParts.h"

BOOL DPIsPasswordsHandoff(int argc, const char *argv[]) { return getenv(DPHandoffVariable) && argc > 1 && !strncmp(argv[1], "--type=", 7); }

static const uint32_t kMaxHandoffPayload = 16 * 1024 * 1024;

static NSDictionary *readLaunch(int host, uint32_t length) {
    if (!length || length > kMaxHandoffPayload) return nil;
    NSMutableData *payload = [NSMutableData dataWithLength:length];
    if (!payload) return nil;
    for (uint32_t got = 0; got < length;) {
        ssize_t n = read(host, (char *)payload.mutableBytes + got, length - got);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return nil;
        got += (uint32_t)n;
    }
    NSDictionary *launch = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
    return [launch isKindOfClass:NSDictionary.class] && [launch[@"arguments"] isKindOfClass:NSArray.class]
            && [launch[@"environment"] isKindOfClass:NSArray.class] ? launch : nil;
}

static char *const *cStrings(NSArray *strings) {
    const char **list = calloc(strings.count + 1, sizeof *list);
    for (NSUInteger i = 0; i < strings.count; i++) list[i] = [strings[i] isKindOfClass:NSString.class] ? [strings[i] UTF8String] : "";
    return (char *const *)list;
}

// Keep the handoff socket above 0-2 so dup2() below cannot overwrite it or mark helper stdio FD_CLOEXEC.
static int moveAboveStdio(int fd) {
    if (fd < 0) return -1;
    if (fd < 3) {
        int moved = fcntl(fd, F_DUPFD_CLOEXEC, 3);
        close(fd);
        return moved;
    }
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    return fd;
}

int DPRunPasswordsHandoff(void) {
    const char *path = getenv(DPHandoffVariable);
    if (!path || !*path) return 0;
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    int host = moveAboveStdio(socket(AF_UNIX, SOCK_STREAM, 0));
    if (host < 0 || strlcpy(address.sun_path, path, sizeof address.sun_path) >= sizeof address.sun_path
        || connect(host, (struct sockaddr *)&address, sizeof address) != 0) {
        if (host >= 0) close(host);
        return 0;
    }
    uint32_t length = 0;
    int fds[3];
    char control[CMSG_SPACE(sizeof fds)];
    struct iovec iov = { &length, sizeof length };
    struct msghdr message = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = control, .msg_controllen = sizeof control };
    ssize_t received;
    do {
        received = recvmsg(host, &message, MSG_WAITALL);
    } while (received < 0 && errno == EINTR);
    if (received != sizeof length) return close(host), 0;
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    if (!header || header->cmsg_type != SCM_RIGHTS || header->cmsg_len != CMSG_LEN(sizeof fds)) return close(host), 0;
    memcpy(fds, CMSG_DATA(header), sizeof fds);
    NSDictionary *launch = readLaunch(host, length);
    NSString *helper = launch[@"helper"];
    if (![helper isKindOfClass:NSString.class]) {
        for (int i = 0; i < 3; i++) close(fds[i]);
        return close(host), 0;
    }

    // Chromium may start this without some of 0-2 open, so what came over the socket can sit where it goes.
    int moved[3] = { -1, -1, -1 };
    for (int i = 0; i < 3; i++) {
        moved[i] = fcntl(fds[i], F_DUPFD, 3);
        close(fds[i]);
        if (moved[i] < 0) {
            for (int j = 0; j < i; j++) close(moved[j]);
            for (int j = i + 1; j < 3; j++) close(fds[j]);
            return close(host), 1;
        }
    }
    for (int i = 0; i < 3; i++) dup2(moved[i], i), close(moved[i]);
    execve(helper.fileSystemRepresentation, cStrings([@[ helper ] arrayByAddingObjectsFromArray:launch[@"arguments"]]), cStrings(launch[@"environment"]));
    return 1;
}
