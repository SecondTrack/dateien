#import "FMShell.h"
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>

#define MOBILE_UID  501
#define MOBILE_GID  501
#define RING_MAX    (256 * 1024)        // so viel Ausgabe hält der Puffer vor
#define READ_MAX    (64 * 1024)         // höchstens so viel pro Abholung

@implementation FMShell {
    int _master;
    pid_t _pid;
    dev_t _tty;
    NSCondition *_cond;                 // schützt alles Folgende
    NSMutableData *_out;
    unsigned long long _base;           // Cursor-Position von _out[0]
    BOOL _stop;
}

@synthesize ended = _ended;

static void *readerMain(void *arg) {
    @autoreleasepool {
        FMShell *s = (__bridge_transfer FMShell *)arg;
        [s readLoop];
    }
    return NULL;
}

+ (instancetype)spawnWithError:(NSString **)err {
    FMShell *s = [[FMShell alloc] init];
    NSString *e = [s start];
    if (e) { if (err) *err = e; return nil; }
    return s;
}

- (NSString *)start {
    _cond = [[NSCondition alloc] init];
    _out = [NSMutableData data];
    _master = posix_openpt(O_RDWR | O_NOCTTY);
    if (_master < 0) return @"pty";
    if (grantpt(_master) != 0 || unlockpt(_master) != 0) { close(_master); return @"pty"; }
    const char *sn = ptsname(_master);
    int slave = sn ? open(sn, O_RDWR | O_NOCTTY) : -1;
    if (slave < 0) { close(_master); return @"pty"; }
    fcntl(_master, F_SETFD, FD_CLOEXEC);

    // Zeilenmodus ohne Echo: der Browser zeigt die Eingabe selbst an; ^C bleibt ein Signal
    struct termios t;
    tcgetattr(slave, &t);
    t.c_lflag &= ~(tcflag_t)(ECHO | ECHOE | ECHOK | ECHONL);
    t.c_lflag |= ICANON | ISIG;
    t.c_oflag |= OPOST | ONLCR;
    tcsetattr(slave, TCSANOW, &t);
    struct winsize ws = { 30, 100, 0, 0 };
    ioctl(slave, TIOCSWINSZ, &ws);
    struct stat st;
    _tty = fstat(slave, &st) == 0 ? st.st_rdev : 0;

    // alles für das Kind VOR fork() vorbereiten: danach sind nur async-signal-sichere Aufrufe erlaubt
    char *argv[] = { "bash", "--noediting", "--noprofile", "--norc", "-i", NULL };
    char *envp[] = { "HOME=/var/mobile", "USER=mobile", "LOGNAME=mobile", "SHELL=/bin/bash", "TERM=dumb",
                     "LANG=en_US.UTF-8", "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                     "PS1=mobile@ipod:\\w\\$ ", NULL };
    int maxfd = getdtablesize();
    sigset_t none; sigemptyset(&none);

    pid_t pid = fork();
    if (pid < 0) { close(slave); close(_master); return @"fork"; }
    if (pid == 0) {
        setsid();
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, 0); dup2(slave, 1); dup2(slave, 2);
        for (int fd = 3; fd < maxfd; fd++) close(fd);
        // niemals als root: Gruppe+Benutzer fest auf mobile, danach prüfen
        if (setgid(MOBILE_GID) != 0 || setuid(MOBILE_UID) != 0) _exit(126);
        if (getuid() == 0 || geteuid() == 0 || getgid() == 0 || getegid() == 0) _exit(126);
        if (chdir("/var/mobile") != 0) chdir("/");
        struct sigaction sa; memset(&sa, 0, sizeof sa); sa.sa_handler = SIG_DFL;
        for (int sig = 1; sig < NSIG; sig++) sigaction(sig, &sa, NULL);
        sigprocmask(SIG_SETMASK, &none, NULL);
        execve("/bin/bash", argv, envp);
        _exit(127);
    }
    close(slave);
    _pid = pid;

    pthread_t th; pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    void *arg = (__bridge_retained void *)self;
    int r = pthread_create(&th, &at, readerMain, arg);
    pthread_attr_destroy(&at);
    if (r != 0) {
        CFRelease(arg);
        kill(pid, SIGKILL); waitpid(pid, NULL, 0); close(_master);
        return @"thread";
    }
    return nil;
}

- (void)readLoop {
    char buf[8192];
    for (;;) {
        [_cond lock]; BOOL stop = _stop; [_cond unlock];
        if (stop) break;
        struct pollfd p = { _master, POLLIN, 0 };
        int n = poll(&p, 1, 500);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) break;
        if (n == 0) continue;
        ssize_t got = read(_master, buf, sizeof buf);
        if (got < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (got <= 0) break;                                   // EIO: alle haben das Terminal geschlossen
        [_cond lock];
        [_out appendBytes:buf length:(NSUInteger)got];
        if (_out.length > RING_MAX) {
            NSUInteger drop = _out.length - RING_MAX;
            [_out replaceBytesInRange:NSMakeRange(0, drop) withBytes:NULL length:0];
            _base += drop;
        }
        [_cond broadcast];
        [_cond unlock];
    }
    close(_master);                                            // = auflegen: Vordergrund-Gruppe bekommt SIGHUP
    [self killTerminalProcesses:SIGHUP];
    for (int i = 0; i < 20 && waitpid(_pid, NULL, WNOHANG) == 0; i++) usleep(100 * 1000);
    [self killTerminalProcesses:SIGKILL];
    kill(_pid, SIGKILL);
    waitpid(_pid, NULL, 0);
    [_cond lock];
    _ended = YES;
    [_cond broadcast];
    [_cond unlock];
}

// alle Prozesse, die dieses Terminal als Steuerterminal haben (auch Hintergrund-Jobs) – nur eigene (mobile)
- (void)killTerminalProcesses:(int)sig {
    if (_pid > 0) kill(-_pid, sig);
    if (!_tty) return;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_TTY, (int)_tty };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || !len) return;
    len += 16 * sizeof(struct kinfo_proc);
    struct kinfo_proc *kp = malloc(len);
    if (kp && sysctl(mib, 4, kp, &len, NULL, 0) == 0) {
        for (size_t i = 0; i < len / sizeof(struct kinfo_proc); i++) {
            pid_t p = kp[i].kp_proc.p_pid;
            if (p > 1 && kp[i].kp_eproc.e_ucred.cr_uid == MOBILE_UID && p != getpid()) kill(p, sig);
        }
    }
    free(kp);
}

- (BOOL)write:(NSData *)data {
    [_cond lock]; BOOL dead = _stop || _ended; [_cond unlock];
    if (dead) return NO;
    const char *p = data.bytes; size_t left = data.length;
    while (left > 0) {
        ssize_t n = write(_master, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n; left -= (size_t)n;
    }
    return YES;
}

- (NSData *)readFrom:(unsigned long long *)cursor wait:(NSTimeInterval)wait ended:(BOOL *)ended {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:wait];
    [_cond lock];
    while (*cursor >= _base + _out.length && !_ended && !_stop) {
        if (![_cond waitUntilDate:until]) break;
    }
    if (*cursor < _base) *cursor = _base;                     // zu alt: ab dem ältesten Rest
    if (*cursor > _base + _out.length) *cursor = _base + _out.length;
    NSUInteger off = (NSUInteger)(*cursor - _base);
    NSUInteger n = MIN((NSUInteger)READ_MAX, _out.length - off);
    NSData *d = [_out subdataWithRange:NSMakeRange(off, n)];
    *cursor += n;
    *ended = (_ended || _stop) && *cursor >= _base + _out.length;
    [_cond unlock];
    return d;
}

- (void)terminate {
    [_cond lock];
    _stop = YES;
    [_cond broadcast];
    [_cond unlock];
    // Lese-Thread bemerkt _stop spätestens nach 500 ms, legt auf und räumt die Prozesse ab
}
@end
