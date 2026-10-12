#import "FMServer.h"
#import "FMShell.h"
#import "FMApps.h"
#import "FMWeb.h"
#import "MeshL10n.h"
#import <AVFoundation/AVFoundation.h>
#include <sys/utsname.h>
#include <dirent.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#import <ImageIO/ImageIO.h>
#include <ctype.h>
#include <math.h>

#define MAX_HEADER      (16 * 1024)
#define MAX_CLIENTS     24          // gleichzeitige Verbindungen
#define MAX_SESSIONS    16
#define MAX_FAILS       5           // falsche PINs, danach Sperre
#define LOCK_SECONDS    30
#define HEADER_TIMEOUT  15          // s für den kompletten Request-Header
#define IO_TIMEOUT      60          // s Stillstand bei Up-/Download
#define TICKET_SECONDS  600         // Gültigkeit eines Download-Tickets
#define SPACE_RESERVE   (20ULL * 1024 * 1024)
#define CHUNK           (64 * 1024)
#define SHELL_IDLE      (10 * 60)   // s ohne Eingabe -> Kommandozeile schaltet sich ganz ab
#define SHELL_FAILS     5           // falsche Passwörter, danach ganz aus (am iPod neu einschalten)
#define SHELL_POLL      15          // s Long-Polling für die Ausgabe
#define SHELL_IN_MAX    8192        // Byte pro Eingabe

static void sendError(int fd, int code, NSString *err);

@interface FMServer ()
@property (atomic, readwrite) BOOL running;
@property (atomic, readwrite, copy) NSString *pin;
@property (atomic, readwrite) uint16_t port;
@end

@implementation FMServer {
    int _wakeFd[2];                  // Selbst-Pipe: weckt den Accept-Thread beim Stoppen
    dispatch_semaphore_t _acceptDone;
    dispatch_semaphore_t _thumbSem;  // höchstens 2 Vorschaubilder gleichzeitig (256 MB RAM)
    NSCache *_thumbs;
    // alles Folgende nur unter @synchronized(self)
    NSString *_root;                 // realpath der Wurzel, fest während eines Laufs
    NSMutableSet *_tokens;
    NSMutableDictionary *_tickets;   // k -> @[absoluter Pfad, Ablaufzeit]
    NSMutableSet *_clients;          // offene Client-Sockets (NSNumber)
    int _fails;
    NSTimeInterval _lockedUntil;
    NSString *_localHost;            // Bonjour-Name, als Host-Header erlaubt
    BOOL _shellOn;
    NSString *_shellPass;            // normalisiert (klein, ohne Bindestriche)
    NSString *_shellToken, *_shellOwner;
    FMShell *_shell;
    int _shellFails;
    NSTimeInterval _shellLastUse;
    dispatch_source_t _watchdog;
}

- (instancetype)init {
    if ((self = [super init])) {
        _rootPath = @"/var/mobile/Media";
        _wakeFd[0] = _wakeFd[1] = -1;
        _tokens = [NSMutableSet set];
        _tickets = [NSMutableDictionary dictionary];
        _clients = [NSMutableSet set];
        _thumbSem = dispatch_semaphore_create(2);
        _thumbs = [[NSCache alloc] init];
        _thumbs.totalCostLimit = 8 * 1024 * 1024;
        // Auto-Aus der Kommandozeile
        __weak FMServer *ws = self;
        _watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
        dispatch_source_set_timer(_watchdog, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), 20 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_watchdog, ^{ [ws shellWatchdog]; });
        dispatch_resume(_watchdog);
    }
    return self;
}

#pragma mark - Hilfen

static NSString *randomHex(int bytes) {
    uint8_t b[32];
    arc4random_buf(b, (size_t)bytes);
    NSMutableString *s = [NSMutableString stringWithCapacity:bytes * 2];
    for (int i = 0; i < bytes; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

static NSString *fsString(const char *p) {
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:p length:strlen(p)];
}

static NSString *realPath(NSString *p) {
    char b[PATH_MAX];
    if (!realpath(p.fileSystemRepresentation, b)) return nil;
    return fsString(b);
}

static BOOL isUnder(NSString *p, NSString *root) {
    if ([root isEqualToString:@"/"]) return [p hasPrefix:@"/"];
    return [p isEqualToString:root] || [p hasPrefix:[root stringByAppendingString:@"/"]];
}

// Ordner, die nie gelöscht/umbenannt werden dürfen (Wurzel = ganzes System):
// alles direkt unter /, /private/var/* bis Tiefe 3 und die großen Benutzerordner.
static BOOL isProtected(NSString *p) {
    NSArray *c = [p pathComponents];                     // "/" zählt als erste Komponente
    NSUInteger depth = c.count - 1;
    if (depth <= 1) return YES;
    if ([p hasPrefix:@"/private/"] && depth <= 3) return YES;
    static NSSet *keep;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keep = [NSSet setWithObjects:@"/private/var/mobile/Media", @"/private/var/mobile/Library",
                @"/private/var/mobile/Applications", @"/private/var/mobile/Media/DCIM", @"/private/var/stash", nil];
    });
    return [keep containsObject:p];
}

static NSString *sizeText(long long n) {
    Class f = NSClassFromString(@"NSByteCountFormatter");   // erst ab iOS 6
    if (f) return [f stringFromByteCount:n countStyle:NSByteCountFormatterCountStyleFile];
    double v = n; NSArray *u = @[@"Bytes", @"KB", @"MB", @"GB", @"TB"]; NSUInteger i = 0;
    while (v >= 1000 && i + 1 < u.count) { v /= 1000; i++; }
    return i ? [NSString stringWithFormat:@"%.1f %@", v, u[i]] : [NSString stringWithFormat:@"%lld %@", n, u[0]];
}

static void *runBlock(void *arg) {
    @autoreleasepool {
        void (^b)(void) = (__bridge_transfer id)arg;
        b();
    }
    return NULL;
}

// eigener, losgelöster Thread pro Aufgabe (blockierende Socket-I/O gehört nicht in GCD-Pools)
static BOOL spawn(void (^blk)(void)) {
    pthread_t t; pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
    void *arg = (__bridge_retained void *)[blk copy];
    int r = pthread_create(&t, &at, runBlock, arg);
    pthread_attr_destroy(&at);
    if (r != 0) { CFRelease(arg); return NO; }
    return YES;
}

// nur Clients aus dem lokalen Netz (RFC 1918, Link-Local, Loopback)
static BOOL privatePeer(struct in_addr a) {
    uint32_t ip = ntohl(a.s_addr);
    return (ip >> 24) == 10 || (ip >> 20) == 0xAC1 || (ip >> 16) == 0xC0A8
        || (ip >> 16) == 0xA9FE || (ip >> 24) == 127;
}

// Host-Header muss eine IP oder der eigene Bonjour-Name (*.local, nur im lokalen Netz auflösbar) sein
// -> schützt vor DNS-Rebinding fremder Webseiten
- (BOOL)hostOK:(NSString *)h {
    if (!h.length) return NO;
    NSRange c = [h rangeOfString:@":" options:NSBackwardsSearch];
    NSString *host = c.location == NSNotFound ? h : [h substringToIndex:c.location];
    if ([host isEqualToString:@"localhost"]) return YES;
    NSString *local;
    @synchronized (self) { local = _localHost; }
    if (local.length && [host caseInsensitiveCompare:local] == NSOrderedSame) return YES;
    struct in_addr a;
    return inet_pton(AF_INET, host.UTF8String, &a) == 1;
}

// Dateiname (eine Pfadkomponente): nicht leer, kein . / .., kein /, keine Steuerzeichen, max. 255 Byte
static BOOL validName(NSString *n) {
    if (!n.length || [n isEqualToString:@"."] || [n isEqualToString:@".."]) return NO;
    if ([n lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 255) return NO;
    for (NSUInteger i = 0; i < n.length; i++) {
        unichar ch = [n characterAtIndex:i];
        if (ch < 0x20 || ch == 0x7f || ch == '/' || ch == ':') return NO;
    }
    return YES;
}

#pragma mark - Start/Stop

- (BOOL)startOnPort:(uint16_t)port error:(NSString **)err {
    if (self.running) return YES;
    NSString *root = realPath(self.rootPath ?: @"");
    BOOL isDir = NO;
    if (!root || ![[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDir] || !isDir) {
        if (err) *err = L(@"Folder not found"); return NO;
    }
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { if (err) *err = L(@"Cannot open network socket"); return NO; }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_len = sizeof a; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0 || listen(fd, 16) < 0) {
        close(fd); if (err) *err = LF(@"Port %d is in use", port); return NO;
    }
    if (pipe(_wakeFd) != 0) { close(fd); if (err) *err = L(@"Cannot open network socket"); return NO; }

    @synchronized (self) {
        _root = root;
        _localHost = [FMServer bonjourName];
        [_tokens removeAllObjects];
        [_tickets removeAllObjects];
        _fails = 0; _lockedUntil = 0;
    }
    self.port = port;
    self.pin = [NSString stringWithFormat:@"%04u", arc4random_uniform(10000)];
    self.running = YES;

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    _acceptDone = done;
    int wake = _wakeFd[0];
    if (!spawn(^{ [self acceptLoop:fd wake:wake]; dispatch_semaphore_signal(done); })) {
        self.running = NO;
        close(fd); close(_wakeFd[0]); close(_wakeFd[1]); _wakeFd[0] = _wakeFd[1] = -1;
        if (err) *err = L(@"Cannot start server thread"); return NO;
    }
    return YES;
}

- (void)stop {
    if (!self.running) return;
    [self setShellEnabled:NO];
    self.running = NO;
    @synchronized (self) {
        [_tokens removeAllObjects];                       // alle Sitzungen ungültig
        [_tickets removeAllObjects];
        for (NSNumber *c in _clients) shutdown(c.intValue, SHUT_RDWR);   // laufende Übertragungen abbrechen
    }
    char x = 1;
    if (write(_wakeFd[1], &x, 1) != 1) { /* Accept-Thread endet spätestens beim nächsten accept */ }
    dispatch_semaphore_wait(_acceptDone, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    close(_wakeFd[1]); _wakeFd[1] = -1;
}

- (void)acceptLoop:(int)fd wake:(int)wake {
    for (;;) {
        struct pollfd p[2] = { { fd, POLLIN, 0 }, { wake, POLLIN, 0 } };
        if (poll(p, 2, -1) < 0) { if (errno == EINTR) continue; break; }
        if (p[1].revents || !self.running) break;
        if (p[0].revents & (POLLERR | POLLNVAL)) break;
        if (!(p[0].revents & POLLIN)) continue;

        struct sockaddr_in peer; socklen_t pl = sizeof peer;
        int c = accept(fd, (struct sockaddr *)&peer, &pl);
        if (c < 0) continue;
        int on = 1; setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
        struct timeval tv = { HEADER_TIMEOUT, 0 };
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        tv.tv_sec = IO_TIMEOUT;
        setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
        if (!privatePeer(peer.sin_addr)) { close(c); continue; }

        BOOL ok;
        @synchronized (self) {
            ok = self.running && _clients.count < MAX_CLIENTS;
            if (ok) [_clients addObject:@(c)];
        }
        if (!ok) { sendError(c, 503, @"busy"); close(c); continue; }

        char ip[INET_ADDRSTRLEN] = "?";
        inet_ntop(AF_INET, &peer.sin_addr, ip, sizeof ip);
        NSString *peerIP = [NSString stringWithUTF8String:ip];
        if (!spawn(^{ [self handle:c peer:peerIP]; [self dropClient:c]; })) [self dropClient:c];
    }
    close(fd);
    close(wake);
}

// unter dem Lock schließen, damit stop() nie einen schon wiederverwendeten fd trifft
- (void)dropClient:(int)c {
    @synchronized (self) {
        [_clients removeObject:@(c)];
        close(c);
    }
}

+ (NSString *)wifiAddress {
    struct ifaddrs *list = NULL; NSString *res = nil;
    if (getifaddrs(&list) == 0) {
        for (struct ifaddrs *i = list; i; i = i->ifa_next) {
            if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET) continue;
            if (!(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;
            char buf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, buf, sizeof buf);
            NSString *s = [NSString stringWithUTF8String:buf];
            if (strcmp(i->ifa_name, "en0") == 0) { res = s; break; }
            if (!res && strncmp(i->ifa_name, "en", 2) == 0) res = s;   // kein pdp_ip (Mobilfunk)
        }
        freeifaddrs(list);
    }
    return res;
}

+ (NSString *)bonjourName {
    struct utsname u;
    if (uname(&u) != 0 || !u.nodename[0]) return nil;
    NSString *n = [[NSString stringWithUTF8String:u.nodename] componentsSeparatedByString:@"."].firstObject;
    return n.length ? [n stringByAppendingString:@".local"] : nil;
}

- (NSUInteger)sessionCount {
    @synchronized (self) { return _tokens.count; }
}

- (void)log:(NSString *)line {
    void (^cb)(NSString *) = self.onActivity;
    if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(line); });
}

#pragma mark - Socket-Helfer

static BOOL sendAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    while (len > 0) {
        ssize_t n = send(fd, p, len, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n; len -= (size_t)n;
    }
    return YES;
}

static BOOL writeAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    while (len > 0) {
        ssize_t n = write(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n; len -= (size_t)n;
    }
    return YES;
}

static NSString *statusText(int code) {
    switch (code) {
        case 200: return @"OK";
        case 206: return @"Partial Content";
        case 400: return @"Bad Request";
        case 401: return @"Unauthorized";
        case 403: return @"Forbidden";
        case 404: return @"Not Found";
        case 409: return @"Conflict";
        case 411: return @"Length Required";
        case 416: return @"Range Not Satisfiable";
        case 421: return @"Misdirected Request";
        case 429: return @"Too Many Requests";
        case 431: return @"Request Header Fields Too Large";
        case 503: return @"Service Unavailable";
        case 507: return @"Insufficient Storage";
        default:  return code < 500 ? @"Bad Request" : @"Internal Server Error";
    }
}

static NSString *baseHeaders(int code, NSString *type, unsigned long long len) {
    return [NSString stringWithFormat:
        @"HTTP/1.1 %d %@\r\nContent-Type: %@\r\nContent-Length: %llu\r\nConnection: close\r\n"
         "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n",
        code, statusText(code), type, len];
}

static void sendResponse(int fd, int code, NSString *type, const void *body, size_t len, NSString *extra) {
    NSMutableString *h = [baseHeaders(code, type, len) mutableCopy];
    if (extra) [h appendString:extra];
    [h appendString:@"\r\n"];
    NSData *hd = [h dataUsingEncoding:NSUTF8StringEncoding];
    if (sendAll(fd, hd.bytes, hd.length) && len) sendAll(fd, body, len);
}

static void sendJSON(int fd, int code, id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL] ?: [NSData data];
    sendResponse(fd, code, @"application/json; charset=utf-8", d.bytes, d.length, nil);
}

// Fehler als kurzer Code, die Browser-Oberfläche übersetzt ihn
static void sendError(int fd, int code, NSString *err) {
    sendJSON(fd, code, @{ @"error": err ?: @"error" });
}

// Antwort schicken, obwohl der Client noch einen Body sendet: Rest kurz abschöpfen,
// sonst setzt der Abbau der Verbindung die Antwort beim Browser oft zurück.
static void sendErrorAndDrain(int fd, int code, NSString *err, long long pending) {
    sendError(fd, code, err);
    shutdown(fd, SHUT_WR);
    struct timeval tv = { 2, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    char tmp[4096]; long long left = MIN(pending, 8LL * 1024 * 1024);
    while (left > 0) { ssize_t n = recv(fd, tmp, sizeof tmp, 0); if (n <= 0) break; left -= n; }
}

static NSDictionary *parseQuery(NSString *q) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *pair in [q componentsSeparatedByString:@"&"]) {
        if (!pair.length) continue;
        NSRange r = [pair rangeOfString:@"="];
        NSString *k = r.location == NSNotFound ? pair : [pair substringToIndex:r.location];
        NSString *v = r.location == NSNotFound ? @"" : [pair substringFromIndex:r.location + 1];
        v = [[v stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        k = [k stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (k && v) d[k] = v;             // ungültige Kodierung -> Parameter fehlt -> Anfrage scheitert
    }
    return d;
}

// RFC 5987 für Content-Disposition: alles außer unreservierten Zeichen kodieren
static NSString *rfc5987(NSString *s) {
    NSMutableString *o = [NSMutableString string];
    const unsigned char *p = (const unsigned char *)s.UTF8String;
    for (; p && *p; p++) {
        if (isalnum(*p) || strchr("!#$&+-.^_`|~", *p)) [o appendFormat:@"%c", *p];
        else [o appendFormat:@"%%%02X", *p];
    }
    return o;
}

#pragma mark - Pfad-Sicherheit

// Relativer Pfad aus dem Browser -> absoluter Pfad unterhalb der Wurzel, sonst nil.
// Elternordner werden per realpath() aufgelöst und müssen in der Wurzel liegen; die letzte
// Komponente bleibt unaufgelöst (rm/mv betreffen damit den Link selbst), ist sie aber ein
// Symlink, muss auch sein Ziel in der Wurzel liegen. Keine „..“, keine ungültigen Namen.
- (NSString *)resolve:(NSString *)rel mustExist:(BOOL)mustExist {
    NSString *root;
    @synchronized (self) { root = _root; }
    if (!root || !rel) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *c in [rel componentsSeparatedByString:@"/"]) {
        if (!c.length || [c isEqualToString:@"."]) continue;
        if (!validName(c)) return nil;
        [parts addObject:c];
    }
    if (!parts.count) return root;
    NSString *last = parts.lastObject;
    [parts removeLastObject];
    NSString *parent = realPath(parts.count ? [root stringByAppendingPathComponent:[parts componentsJoinedByString:@"/"]] : root);
    if (!parent || !isUnder(parent, root)) return nil;
    NSString *full = [parent stringByAppendingPathComponent:last];
    struct stat st;
    if (lstat(full.fileSystemRepresentation, &st) == 0) {
        if (S_ISLNK(st.st_mode)) {
            NSString *target = realPath(full);
            if (!target || !isUnder(target, root)) return nil;   // auch kaputte Links ablehnen
        }
    } else if (mustExist || errno != ENOENT) {
        return nil;
    }
    return full;
}

- (BOOL)isRoot:(NSString *)p {
    @synchronized (self) { return [p isEqualToString:_root]; }
}

static BOOL isDirectory(NSString *p) {
    struct stat st;
    return stat(p.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode);
}

static unsigned long long freeSpace(NSString *p) {
    struct statfs s;
    if (statfs(p.fileSystemRepresentation, &s) != 0) return 0;
    return (unsigned long long)s.f_bavail * s.f_bsize;
}

#pragma mark - Anfrage verarbeiten

- (BOOL)checkToken:(NSString *)t {
    if (t.length != 32 || !self.running) return NO;
    @synchronized (self) { return [_tokens containsObject:t]; }
}

- (void)handle:(int)fd peer:(NSString *)peer {
    // ---- Header lesen (mit Gesamt-Zeitlimit gegen tröpfelnde Clients) ----
    NSMutableData *buf = [NSMutableData data];
    NSData *crlf2 = [NSData dataWithBytes:"\r\n\r\n" length:4];
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + HEADER_TIMEOUT;
    char tmp[4096]; NSRange end = { NSNotFound, 0 };
    while (buf.length < MAX_HEADER) {
        if ([NSDate timeIntervalSinceReferenceDate] > deadline) return;
        ssize_t n = recv(fd, tmp, sizeof tmp, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return;
        [buf appendBytes:tmp length:(NSUInteger)n];
        end = [buf rangeOfData:crlf2 options:0 range:NSMakeRange(0, buf.length)];
        if (end.location != NSNotFound) break;
    }
    if (end.location == NSNotFound) { sendError(fd, 431, @"header"); return; }
    struct timeval tv = { IO_TIMEOUT, 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    NSString *head = [[NSString alloc] initWithData:[buf subdataWithRange:NSMakeRange(0, end.location)] encoding:NSUTF8StringEncoding];
    NSData *bodyStart = [buf subdataWithRange:NSMakeRange(end.location + 4, buf.length - end.location - 4)];
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *req = [lines.firstObject componentsSeparatedByString:@" "];
    if (req.count != 3 || ![req[1] hasPrefix:@"/"]) { sendError(fd, 400, @"request"); return; }
    NSString *method = req[0], *target = req[1];
    NSMutableDictionary *hdr = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSRange r = [lines[i] rangeOfString:@":"];
        if (r.location == NSNotFound) continue;
        hdr[[[lines[i] substringToIndex:r.location] lowercaseString]] =
            [[lines[i] substringFromIndex:r.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if (![self hostOK:hdr[@"host"]]) { sendError(fd, 421, @"host"); return; }
    NSRange qm = [target rangeOfString:@"?"];
    NSString *path = qm.location == NSNotFound ? target : [target substringToIndex:qm.location];
    NSDictionary *q = parseQuery(qm.location == NSNotFound ? @"" : [target substringFromIndex:qm.location + 1]);
    BOOL get = [method isEqualToString:@"GET"], post = [method isEqualToString:@"POST"];

    // ---- öffentlich: Oberfläche ----
    if (get && ([path isEqualToString:@"/"] || [path isEqualToString:@"/index.html"])) {
        sendResponse(fd, 200, @"text/html; charset=utf-8", index_html, index_html_len,
            @"X-Frame-Options: DENY\r\n"
             "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; "
             "connect-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; manifest-src 'none'; "
             "base-uri 'none'; form-action 'none'; frame-ancestors 'none'\r\n");
        return;
    }
    if (get && [path isEqualToString:@"/icon.png"]) {          // gleiches Logo wie auf dem Home-Bildschirm
        static NSData *icon;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ icon = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Icon@2x" ofType:@"png"]]; });
        if (!icon) { sendError(fd, 404, @"notfound"); return; }
        sendResponse(fd, 200, @"image/png", icon.bytes, icon.length, nil);
        return;
    }
    if (get && [path isEqualToString:@"/app.js"]) {
        sendResponse(fd, 200, @"text/javascript; charset=utf-8", app_js, app_js_len, nil);
        return;
    }

    // ---- Anmeldung: PIN nur im Header (erzwingt CORS-Preflight -> fremde Seiten können nicht raten) ----
    if (post && [path isEqualToString:@"/api/login"]) {
        NSString *pin = hdr[@"x-fm-pin"];
        int status; NSString *tok = nil; int wait = 0; BOOL nowLocked = NO;
        @synchronized (self) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (!self.running) status = 503;
            else if (now < _lockedUntil) { status = 429; wait = (int)ceil(_lockedUntil - now); }
            else if (pin.length == 4 && [pin isEqualToString:self.pin]) {
                _fails = 0; status = 200;
                tok = randomHex(16);
                if (_tokens.count >= MAX_SESSIONS) [_tokens removeObject:[_tokens anyObject]];
                [_tokens addObject:tok];
            } else {
                status = 403;
                if (++_fails >= MAX_FAILS) { _lockedUntil = now + LOCK_SECONDS; _fails = 0; nowLocked = YES; wait = LOCK_SECONDS; }
            }
        }
        if (status == 200) {
            [self log:[@"✓ " stringByAppendingString:LF(@"Login from %@", peer)]];
            sendJSON(fd, 200, @{ @"token": tok });
        } else if (status == 429) {
            sendJSON(fd, 429, @{ @"error": @"locked", @"wait": @(wait) });
        } else if (status == 403) {
            [self log:[@"! " stringByAppendingString:LF(@"Wrong PIN from %@", peer)]];
            if (nowLocked) {
                [self log:[@"! " stringByAppendingString:LF(@"Login locked for %d s", LOCK_SECONDS)]];
                sendJSON(fd, 429, @{ @"error": @"locked", @"wait": @(wait) });
            } else sendError(fd, 403, @"pin");
        } else sendError(fd, 503, @"stopped");
        return;
    }

    // ---- Download per Ticket (Browser-Navigation kann keinen Header setzen) ----
    if (get && [path isEqualToString:@"/dl"]) {
        NSString *file = nil, *k = q[@"k"];
        @synchronized (self) {
            NSArray *t = k ? _tickets[k] : nil;
            if (t && [t[1] doubleValue] > [NSDate timeIntervalSinceReferenceDate]) file = t[0];
            else if (k) [_tickets removeObjectForKey:k];
        }
        if (!file || !self.running) { sendError(fd, 401, @"login"); return; }
        [self download:file fd:fd range:hdr[@"range"] inline:[q[@"inline"] isEqualToString:@"1"]];
        return;
    }

    // ---- ab hier nur mit Sitzungstoken im Header ----
    if (![self checkToken:hdr[@"x-fm-token"]]) { sendError(fd, 401, @"login"); return; }

    if (post && [path isEqualToString:@"/api/logout"]) {
        @synchronized (self) { [_tokens removeObject:hdr[@"x-fm-token"]]; }
        sendJSON(fd, 200, @{ @"ok": @YES });
        return;
    }

    if (get && [path isEqualToString:@"/api/ls"]) {
        NSString *dir = [self resolve:q[@"p"] mustExist:YES], *root;
        if (!dir || !isDirectory(dir)) { sendError(fd, 404, @"notfound"); return; }
        @synchronized (self) { root = _root; }
        NSError *e = nil;
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:&e];
        if (!names) { sendError(fd, 403, @"denied"); return; }
        NSMutableArray *items = [NSMutableArray arrayWithCapacity:names.count];
        for (NSString *name in names) {
            if ([name hasPrefix:@".fmup-"]) continue;           // laufende Uploads
            NSString *full = [dir stringByAppendingPathComponent:name];
            struct stat st;
            if (lstat(full.fileSystemRepresentation, &st) != 0) continue;
            if (S_ISLNK(st.st_mode)) {                           // Links nach draußen gar nicht zeigen
                NSString *t = realPath(full);
                if (!t || !isUnder(t, root) || stat(full.fileSystemRepresentation, &st) != 0) continue;
            }
            [items addObject:@{ @"n": name, @"d": @(S_ISDIR(st.st_mode)),
                                @"s": @((long long)st.st_size), @"m": @((long long)st.st_mtime) }];
        }
        sendJSON(fd, 200, @{ @"root": self.rootPath ?: @"", @"items": items, @"free": @(freeSpace(dir)) });
        return;
    }

    if (post && [path isEqualToString:@"/api/ticket"]) {
        NSString *file = [self resolve:q[@"p"] mustExist:YES];
        struct stat st;
        if (!file || stat(file.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) { sendError(fd, 404, @"notfound"); return; }
        NSString *k = randomHex(16);
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        @synchronized (self) {
            for (NSString *old in _tickets.allKeys) if ([_tickets[old][1] doubleValue] < now) [_tickets removeObjectForKey:old];
            _tickets[k] = @[file, @(now + TICKET_SECONDS)];
        }
        sendJSON(fd, 200, @{ @"k": k });
        return;
    }

    if ([method isEqualToString:@"PUT"] && [path isEqualToString:@"/api/up"]) {
        [self upload:fd query:q headers:hdr bodyStart:bodyStart];
        return;
    }

    if (post && [path isEqualToString:@"/api/mkdir"]) {
        NSString *dir = [self resolve:q[@"p"] mustExist:YES], *name = q[@"n"];
        if (!dir || !isDirectory(dir) || !validName(name)) { sendError(fd, 400, @"badname"); return; }
        NSString *nd = [dir stringByAppendingPathComponent:name];
        if (mkdir(nd.fileSystemRepresentation, 0755) != 0) { sendError(fd, errno == EEXIST ? 409 : 403, errno == EEXIST ? @"exists" : @"denied"); return; }
        [self log:[@"+ " stringByAppendingString:name]];
        sendJSON(fd, 200, @{ @"ok": @YES });
        return;
    }

    if (post && [path isEqualToString:@"/api/mv"]) {
        NSString *src = [self resolve:q[@"p"] mustExist:YES], *name = q[@"n"];
        if (!src || [self isRoot:src] || isProtected(src)) { sendError(fd, 403, @"protected"); return; }
        if (!validName(name)) { sendError(fd, 400, @"badname"); return; }
        NSString *dst = [[src stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(dst.fileSystemRepresentation, &st) == 0) { sendError(fd, 409, @"exists"); return; }
        if (rename(src.fileSystemRepresentation, dst.fileSystemRepresentation) != 0) { sendError(fd, 403, @"denied"); return; }
        [self log:[NSString stringWithFormat:@"→ %@ → %@", src.lastPathComponent, name]];
        sendJSON(fd, 200, @{ @"ok": @YES });
        return;
    }

    if (post && [path isEqualToString:@"/api/rm"]) {
        NSString *t = [self resolve:q[@"p"] mustExist:YES];
        if (!t || [self isRoot:t] || isProtected(t)) { sendError(fd, 403, @"protected"); return; }
        // removeItemAtPath folgt keinen Symlinks: ein Link wird selbst gelöscht, nicht sein Ziel
        if (![[NSFileManager defaultManager] removeItemAtPath:t error:NULL]) { sendError(fd, 403, @"denied"); return; }
        [self log:[@"× " stringByAppendingString:t.lastPathComponent]];
        sendJSON(fd, 200, @{ @"ok": @YES });
        return;
    }

    if (post && [path isEqualToString:@"/api/import"]) {
        [self importFile:fd path:[self resolve:q[@"p"] mustExist:YES]];
        return;
    }

    if (get && [path isEqualToString:@"/api/thumb"]) {
        [self thumb:fd path:[self resolve:q[@"p"] mustExist:YES] size:[q[@"s"] intValue]];
        return;
    }

    if (get && [path isEqualToString:@"/api/info"]) {
        struct statfs sf;
        unsigned long long total = 0, freeB = 0;
        if (statfs("/private/var/mobile", &sf) == 0) {
            total = (unsigned long long)sf.f_blocks * sf.f_bsize;
            freeB = (unsigned long long)sf.f_bavail * sf.f_bsize;
        }
        sendJSON(fd, 200, @{ @"name": self.deviceName ?: @"iPod", @"model": self.deviceModel ?: @"iPod",
                             @"total": @(total), @"free": @(freeB), @"shell": @(self.shellEnabled) });
        return;
    }

    if (get && [path isEqualToString:@"/api/find"]) {
        [self find:fd in:[self resolve:q[@"p"] mustExist:YES] query:q[@"q"] hidden:[q[@"h"] isEqualToString:@"1"]];
        return;
    }

    if (get && [path isEqualToString:@"/api/collect"]) {
        [self collect:fd kind:q[@"k"]];
        return;
    }

    if (get && [path isEqualToString:@"/api/apps"]) {
        sendJSON(fd, 200, @{ @"items": FMAppsList() });
        return;
    }
    if (get && [path isEqualToString:@"/api/appicon"]) {
        NSData *png = FMAppsIcon(q[@"a"]);
        if (!png) { sendError(fd, 404, @"notfound"); return; }
        sendResponse(fd, 200, @"image/png", png.bytes, png.length, nil);
        return;
    }
    if ([method isEqualToString:@"PUT"] && [path isEqualToString:@"/api/pkg"]) {
        [self pkgUpload:fd query:q headers:hdr bodyStart:bodyStart peer:peer];
        return;
    }
    if (post && [path isEqualToString:@"/api/pkgfile"]) {
        NSString *file = [self resolve:q[@"p"] mustExist:YES];
        struct stat st;
        if (!file || stat(file.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) { sendError(fd, 404, @"notfound"); return; }
        [self installPackage:file name:file.lastPathComponent fd:fd peer:peer];
        return;
    }
    if (post && [path isEqualToString:@"/api/appdel"]) {
        [self removeApp:q[@"a"] fd:fd peer:peer];
        return;
    }

    if ([path hasPrefix:@"/api/sh/"]) {
        [self shellRequest:fd path:path method:method headers:hdr bodyStart:bodyStart query:q peer:peer];
        return;
    }

    sendError(fd, 404, @"unknown");
}

#pragma mark - Suchen & Sammlungen (rekursiv, ohne Symlinks zu folgen, mit Grenzen)

typedef struct { int budget; NSTimeInterval deadline; BOOL hidden; BOOL stop; } FMWalk;

// besucht alle Einträge unter dir; visit gibt NO zurück, wenn genug gesammelt ist
static void walk(NSString *dir, int depth, int maxDepth, NSSet *skip, FMWalk *w,
                 BOOL (^visit)(NSString *abs, NSString *name, struct stat *st)) {
    DIR *d = opendir(dir.fileSystemRepresentation);
    if (!d) return;
    struct dirent *e;
    while (!w->stop && (e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        if (!w->hidden && e->d_name[0] == '.') continue;
        if (!strncmp(e->d_name, ".fmup-", 6)) continue;
        if (--w->budget <= 0 || [NSDate timeIntervalSinceReferenceDate] > w->deadline) { w->stop = YES; break; }
        @autoreleasepool {
            NSString *name = fsString(e->d_name);
            NSString *abs = [dir stringByAppendingPathComponent:name];
            struct stat st;
            if (lstat(abs.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode)) continue;
            if (!visit(abs, name, &st)) { w->stop = YES; break; }
            if (S_ISDIR(st.st_mode) && depth < maxDepth && ![skip containsObject:abs])
                walk(abs, depth + 1, maxDepth, skip, w, visit);
        }
    }
    closedir(d);
}

- (NSString *)relative:(NSString *)abs {
    NSString *root;
    @synchronized (self) { root = _root; }
    if ([root isEqualToString:@"/"]) return [abs substringFromIndex:1];
    return abs.length > root.length ? [abs substringFromIndex:root.length + 1] : @"";
}

static NSDictionary *itemFor(NSString *rel, NSString *name, struct stat *st) {
    return @{ @"p": rel, @"n": name, @"d": @(S_ISDIR(st->st_mode)), @"s": @((long long)st->st_size), @"m": @((long long)st->st_mtime) };
}

- (void)find:(int)fd in:(NSString *)dir query:(NSString *)query hidden:(BOOL)hidden {
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!dir || !isDirectory(dir) || query.length < 1 || query.length > 100) { sendError(fd, 400, @"badname"); return; }
    NSMutableArray *found = [NSMutableArray array];
    FMWalk w = { 80000, [NSDate timeIntervalSinceReferenceDate] + 6, hidden, NO };
    walk(dir, 0, 14, nil, &w, ^BOOL(NSString *abs, NSString *name, struct stat *st) {
        if ([name rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound)
            [found addObject:itemFor([self relative:abs], name, st)];
        return found.count < 300;
    });
    sendJSON(fd, 200, @{ @"items": found, @"more": @(w.stop) });
}

// k=photos: Kamerarolle (DCIM); k=music: alle Audiodateien im Medienbereich
- (void)collect:(int)fd kind:(NSString *)kind {
    NSString *root;
    @synchronized (self) { root = _root; }
    BOOL photos = [kind isEqualToString:@"photos"];
    if (!photos && ![kind isEqualToString:@"music"]) { sendError(fd, 400, @"unknown"); return; }
    NSString *base = realPath(photos ? @"/var/mobile/Media/DCIM" : @"/var/mobile/Media");
    NSMutableArray *found = [NSMutableArray array];
    if (base && isUnder(base, root)) {
        static NSSet *img, *aud;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            img = [NSSet setWithObjects:@"jpg", @"jpeg", @"png", @"gif", @"tif", @"tiff", @"bmp", @"heic", @"mov", @"mp4", @"m4v", nil];
            aud = [NSSet setWithObjects:@"mp3", @"m4a", @"m4b", @"m4p", @"m4r", @"aac", @"wav", @"aif", @"aiff", @"caf", @"flac", @"ogg", @"opus", nil];
        });
        NSSet *ext = photos ? img : aud;
        NSMutableSet *skip = [NSMutableSet set];
        if (!photos) for (NSString *n in @[@"DCIM", @"PhotoData", @"Photos", @"PhotoStreamsData", @"Books"])
            [skip addObject:[base stringByAppendingPathComponent:n]];
        FMWalk w = { 100000, [NSDate timeIntervalSinceReferenceDate] + 8, NO, NO };
        walk(base, 0, photos ? 1 : 10, skip, &w, ^BOOL(NSString *abs, NSString *name, struct stat *st) {
            if (S_ISREG(st->st_mode) && [ext containsObject:name.pathExtension.lowercaseString])
                [found addObject:itemFor([self relative:abs], name, st)];
            return found.count < 20000;
        });
    }
    sendJSON(fd, 200, @{ @"items": found });
}

#pragma mark - Apps installieren / entfernen (immer mit Bestätigung am iPod)

static NSLock *pkgLock(void) {
    static NSLock *l; static dispatch_once_t once;
    dispatch_once(&once, ^{ l = [[NSLock alloc] init]; });
    return l;
}

- (BOOL)askOnDevice:(NSString *)title message:(NSString *)msg ok:(NSString *)ok {
    BOOL (^c)(NSString *, NSString *, NSString *) = self.confirm;
    return c ? c(title, msg, ok) : NO;
}

- (void)pkgUpload:(int)fd query:(NSDictionary *)q headers:(NSDictionary *)hdr bodyStart:(NSData *)bodyStart peer:(NSString *)peer {
    NSString *cl = hdr[@"content-length"];
    if (hdr[@"transfer-encoding"] || !cl.length) { sendError(fd, 411, @"length"); return; }
    char *endp = NULL;
    long long clen = strtoll(cl.UTF8String, &endp, 10);
    if (clen < 0 || !endp || *endp) { sendError(fd, 400, @"length"); return; }
    long long pending = clen - (long long)bodyStart.length;
    NSString *name = q[@"n"], *ext = name.pathExtension.lowercaseString;
    if (!validName(name) || !([ext isEqualToString:@"deb"] || [ext isEqualToString:@"ipa"])) { sendErrorAndDrain(fd, 415, @"pkgtype", pending); return; }
    NSString *dir = [[self stagingDir] stringByDeletingLastPathComponent];
    dir = [dir stringByAppendingPathComponent:@"fm-pkg"];
    mkdir(dir.fileSystemRepresentation, 0700);
    if ((unsigned long long)clen + SPACE_RESERVE > freeSpace(dir)) { sendErrorAndDrain(fd, 507, @"space", pending); return; }
    NSString *part = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", randomHex(8), ext]];
    int out = open(part.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (out < 0) { sendErrorAndDrain(fd, 403, @"denied", pending); return; }
    long long got = MIN((long long)bodyStart.length, clen);
    BOOL ok = got == 0 || writeAll(out, bodyStart.bytes, (size_t)got);
    char *chunk = malloc(CHUNK);
    while (ok && got < clen) {
        ssize_t n = recv(fd, chunk, (size_t)MIN((long long)CHUNK, clen - got), 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0 || !self.running || !writeAll(out, chunk, (size_t)n)) { ok = NO; break; }
        got += n;
    }
    free(chunk);
    close(out);
    if (!ok) { unlink(part.fileSystemRepresentation); sendError(fd, 500, @"aborted"); return; }
    [self installPackage:part name:name fd:fd peer:peer];
    unlink(part.fileSystemRepresentation);
}

- (void)installPackage:(NSString *)file name:(NSString *)name fd:(int)fd peer:(NSString *)peer {
    NSString *ext = file.pathExtension.lowercaseString;
    BOOL deb = [ext isEqualToString:@"deb"];
    if (!deb && ![ext isEqualToString:@"ipa"]) { sendError(fd, 415, @"pkgtype"); return; }
    if (![pkgLock() tryLock]) { sendError(fd, 409, @"pkgbusy"); return; }
    NSDictionary *info = FMPkgInfo(file);
    NSString *sha = FMSHA256(file);
    if (!info || !sha) { [pkgLock() unlock]; sendError(fd, 415, deb ? @"notdeb" : @"notipa"); return; }
    struct stat st; stat(file.fileSystemRepresentation, &st);
    NSString *what = info[@"v"] ? [NSString stringWithFormat:@"%@ %@", info[@"n"], info[@"v"]] : info[@"n"];
    NSString *msg = [NSString stringWithFormat:@"%@\n%@ · %@\n%@", what, info[@"pkg"] ?: name, sizeText(st.st_size), LF(@"Requested from %@", peer)];
    [self log:[@"? " stringByAppendingString:LF(@"Install %@?", what)]];
    if (![self askOnDevice:L(@"Install app?") message:msg ok:L(@"Install")]) {
        [pkgLock() unlock];
        sendError(fd, 403, @"declined");
        return;
    }
    NSString *log = nil;
    NSString *code = FMHelperRun(@[deb ? @"install-deb" : @"install-ipa", file, sha], &log);
    [pkgLock() unlock];
    [self log:[NSString stringWithFormat:@"%@ %@ (%@)", [code isEqualToString:@"ok"] ? @"✓" : @"!", what, code]];
    if ([code isEqualToString:@"ok"]) sendJSON(fd, 200, @{ @"ok": @YES, @"name": what, @"log": log ?: @"" });
    else sendJSON(fd, [code isEqualToString:@"caller"] ? 500 : 409, @{ @"error": [@"pkg_" stringByAppendingString:code], @"log": log ?: @"" });
}

- (void)removeApp:(NSString *)appDir fd:(int)fd peer:(NSString *)peer {
    NSDictionary *app = appDir ? FMAppsFind(appDir) : nil;
    if (!app) { sendError(fd, 404, @"notfound"); return; }
    if (![app[@"rm"] boolValue]) { sendError(fd, 403, @"protected"); return; }
    if (![pkgLock() tryLock]) { sendError(fd, 409, @"pkgbusy"); return; }
    NSString *msg = [NSString stringWithFormat:@"%@ %@\n%@", app[@"n"], app[@"v"], LF(@"Requested from %@", peer)];
    if (![self askOnDevice:L(@"Delete app?") message:msg ok:L(@"Delete")]) {
        [pkgLock() unlock];
        sendError(fd, 403, @"declined");
        return;
    }
    NSString *log = nil;
    NSString *code = ![app[@"src"] isEqualToString:@"deb"] ? FMHelperRun(@[@"remove-app", appDir], &log)
                                                          : FMHelperRun(@[@"remove-pkg", app[@"pkg"]], &log);
    [pkgLock() unlock];
    [self log:[NSString stringWithFormat:@"%@ × %@ (%@)", [code isEqualToString:@"ok"] ? @"✓" : @"!", app[@"n"], code]];
    if ([code isEqualToString:@"ok"]) sendJSON(fd, 200, @{ @"ok": @YES });
    else sendJSON(fd, 409, @{ @"error": [@"pkg_" stringByAppendingString:code], @"log": log ?: @"" });
}

#pragma mark - Kommandozeile

static NSString *normPass(NSString *p) {
    return [[[p lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""]
                                 stringByReplacingOccurrencesOfString:@" " withString:@""];
}

static BOOL sameSecret(NSString *a, NSString *b) {      // Vergleich in konstanter Zeit
    NSData *x = [a dataUsingEncoding:NSUTF8StringEncoding], *y = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (!x || !y || x.length != y.length) return NO;
    const uint8_t *p = x.bytes, *q = y.bytes; uint8_t diff = 0;
    for (NSUInteger i = 0; i < x.length; i++) diff |= p[i] ^ q[i];
    return diff == 0;
}

- (BOOL)shellEnabled { @synchronized (self) { return _shellOn; } }
- (BOOL)shellInUse { @synchronized (self) { return _shell && !_shell.ended; } }
- (NSString *)shellPassword {
    @synchronized (self) {
        if (!_shellOn) return nil;
        return [NSString stringWithFormat:@"%@-%@", [_shellPass substringToIndex:4], [_shellPass substringFromIndex:4]];   // xxxx-xxxx
    }
}

- (void)setShellEnabled:(BOOL)on {
    FMShell *old = nil; BOOL changed;
    @synchronized (self) {
        changed = _shellOn != on;
        old = _shell; _shell = nil;
        _shellToken = _shellOwner = nil;
        _shellFails = 0;
        _shellOn = on && self.running;
        if (_shellOn) {
            // 8 Zeichen aus 31 gut unterscheidbaren (~40 Bit), neu bei jedem Einschalten. Reicht, weil nach
            // SHELL_FAILS Fehlversuchen alles aus ist: 5 Versuche gegen 8,5e11 Möglichkeiten.
            static const char abc[] = "abcdefghjkmnpqrstuvwxyz23456789";
            char pw[9];
            for (int i = 0; i < 8; i++) pw[i] = abc[arc4random_uniform((uint32_t)(sizeof abc - 1))];
            pw[8] = 0;
            _shellPass = [NSString stringWithUTF8String:pw];
            _shellLastUse = [NSDate timeIntervalSinceReferenceDate];
        } else _shellPass = nil;
    }
    [old terminate];
    if (changed || old) [self log:on ? @"shell on" : @"shell off"];
}

- (void)shellWatchdog {
    BOOL idle = NO;
    @synchronized (self) {
        idle = _shellOn && [NSDate timeIntervalSinceReferenceDate] - _shellLastUse > SHELL_IDLE;
    }
    if (idle) { [self setShellEnabled:NO]; [self log:@"shell idle"]; }
}

// kleinen Body (Content-Length) komplett lesen
static NSData *readBody(int fd, NSDictionary *hdr, NSData *bodyStart, long long max) {
    NSString *cl = hdr[@"content-length"];
    if (hdr[@"transfer-encoding"] || !cl.length) return nil;
    char *endp = NULL;
    long long n = strtoll(cl.UTF8String, &endp, 10);
    if (n < 0 || n > max || !endp || *endp) return nil;
    NSMutableData *d = [NSMutableData dataWithData:[bodyStart subdataWithRange:NSMakeRange(0, (NSUInteger)MIN((long long)bodyStart.length, n))]];
    char tmp[4096];
    while ((long long)d.length < n) {
        ssize_t r = recv(fd, tmp, (size_t)MIN((long long)sizeof tmp, n - (long long)d.length), 0);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return nil;
        [d appendBytes:tmp length:(NSUInteger)r];
    }
    return d;
}

- (void)shellRequest:(int)fd path:(NSString *)path method:(NSString *)method headers:(NSDictionary *)hdr
           bodyStart:(NSData *)bodyStart query:(NSDictionary *)q peer:(NSString *)peer {
    BOOL post = [method isEqualToString:@"POST"];
    NSString *session = hdr[@"x-fm-token"];

    if (post && [path isEqualToString:@"/api/sh/open"]) {
        NSString *pass = normPass(hdr[@"x-fm-shellpass"] ?: @"");
        int status = 200; BOOL lockout = NO; FMShell *old = nil; NSString *tok = nil;
        @synchronized (self) {
            if (!_shellOn) status = 403;
            else if (!sameSecret(pass, _shellPass)) {
                status = 401;
                if (++_shellFails >= SHELL_FAILS) lockout = YES;
            } else {
                _shellFails = 0;
                old = _shell; _shell = nil;                       // nur eine Sitzung gleichzeitig
                tok = randomHex(16);
                _shellToken = tok; _shellOwner = session;
                _shellLastUse = [NSDate timeIntervalSinceReferenceDate];
            }
        }
        [old terminate];
        if (status == 403) { sendError(fd, 403, @"shelloff"); return; }
        if (status == 401) {
            [self log:[@"! " stringByAppendingString:LF(@"Wrong command line password from %@", peer)]];
            if (lockout) { [self setShellEnabled:NO]; sendError(fd, 403, @"shelllocked"); }
            else sendError(fd, 403, @"shellpass");
            return;
        }
        NSString *err = nil;
        FMShell *sh = [FMShell spawnWithError:&err];
        @synchronized (self) {
            if (sh && [_shellToken isEqualToString:tok] && _shellOn) _shell = sh;
            else { [sh terminate]; sh = nil; }
        }
        if (!sh) { sendError(fd, 500, @"shellfail"); return; }
        [self log:[@"> " stringByAppendingString:LF(@"Command line opened from %@", peer)]];
        sendJSON(fd, 200, @{ @"st": tok });
        return;
    }

    FMShell *sh = nil;
    @synchronized (self) {
        NSString *st = hdr[@"x-fm-shell"];
        if (_shellOn && _shell && st.length == 32 && sameSecret(st, _shellToken ?: @"") && [session isEqualToString:_shellOwner])
            sh = _shell;
    }
    if (!sh) { sendError(fd, 403, self.shellEnabled ? @"shellgone" : @"shelloff"); return; }

    if (post && [path isEqualToString:@"/api/sh/in"]) {
        NSData *d = readBody(fd, hdr, bodyStart, SHELL_IN_MAX);
        if (!d) { sendError(fd, 400, @"length"); return; }
        @synchronized (self) { _shellLastUse = [NSDate timeIntervalSinceReferenceDate]; }
        sendJSON(fd, [sh write:d] ? 200 : 410, @{ @"ok": @YES });
        return;
    }
    if ([method isEqualToString:@"GET"] && [path isEqualToString:@"/api/sh/out"]) {
        unsigned long long cur = strtoull([q[@"c"] ?: @"0" UTF8String], NULL, 10);
        BOOL ended = NO;
        NSData *d = [sh readFrom:&cur wait:SHELL_POLL ended:&ended];
        sendResponse(fd, 200, @"application/octet-stream", d.bytes, d.length,
                     [NSString stringWithFormat:@"X-FM-Cursor: %llu\r\nX-FM-End: %d\r\n", cur, ended ? 1 : 0]);
        return;
    }
    if (post && [path isEqualToString:@"/api/sh/close"]) {
        @synchronized (self) { if (_shell == sh) { _shell = nil; _shellToken = _shellOwner = nil; } }
        [sh terminate];
        [self log:@"shell closed"];
        sendJSON(fd, 200, @{ @"ok": @YES });
        return;
    }
    sendError(fd, 404, @"unknown");
}

#pragma mark - Vorschaubilder (ImageIO, nutzt bei Fotos das eingebettete EXIF-Thumbnail)

- (void)thumb:(int)fd path:(NSString *)file size:(int)size {
    struct stat st;
    if (!file || stat(file.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) { sendError(fd, 404, @"notfound"); return; }
    BOOL video = [@[@"mov", @"mp4", @"m4v", @"3gp"] containsObject:file.pathExtension.lowercaseString];
    if (!video && st.st_size > 80LL * 1024 * 1024) { sendError(fd, 415, @"noimage"); return; }
    size = size < 64 ? 160 : MIN(size, 1280);
    NSString *key = [NSString stringWithFormat:@"%@|%ld|%d", file, (long)st.st_mtime, size];
    NSData *jpg = [_thumbs objectForKey:key];
    if (!jpg) {
        dispatch_semaphore_wait(_thumbSem, DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            CGImageSourceRef src = video ? NULL : CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:file], NULL);
            CGImageRef img = NULL;
            if (video) {                                   // Standbild aus dem Video (bei ~1 s)
                AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:file] options:nil];
                AVAssetImageGenerator *g = [AVAssetImageGenerator assetImageGeneratorWithAsset:a];
                g.appliesPreferredTrackTransform = YES;
                g.maximumSize = CGSizeMake(size, size);
                Float64 dur = CMTimeGetSeconds(a.duration);
                img = [g copyCGImageAtTime:CMTimeMakeWithSeconds(dur > 2 ? 1.0 : 0, 600) actualTime:NULL error:NULL];
            }
            if (src) {
                NSDictionary *o = @{ (__bridge id)kCGImageSourceThumbnailMaxPixelSize: @(size),
                                     (__bridge id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                                     // kleine Vorschau: EXIF-Thumbnail reicht; groß: echtes Bild skalieren
                                     (__bridge id)(size > 200 ? kCGImageSourceCreateThumbnailFromImageAlways
                                                              : kCGImageSourceCreateThumbnailFromImageIfAbsent): @YES };
                img = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)o);
                CFRelease(src);
            }
            if (img) {
                NSMutableData *d = [NSMutableData data];
                CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)d, CFSTR("public.jpeg"), 1, NULL);
                if (dst) {
                    CGImageDestinationAddImage(dst, img, (__bridge CFDictionaryRef)@{ (__bridge id)kCGImageDestinationLossyCompressionQuality: @0.75 });
                    if (CGImageDestinationFinalize(dst)) jpg = d;
                    CFRelease(dst);
                }
                CGImageRelease(img);
            }
        }
        dispatch_semaphore_signal(_thumbSem);
        if (!jpg) { sendError(fd, 415, @"noimage"); return; }
        [_thumbs setObject:jpg forKey:key cost:jpg.length];
    }
    sendResponse(fd, 200, @"image/jpeg", jpg.bytes, jpg.length, nil);
}

#pragma mark - Download (gestreamt, mit einfachem Range für Fortsetzen/Spulen)

// Medien dürfen im Browser abgespielt/angezeigt werden (alles andere immer als Download)
static NSString *inlineType(NSString *name) {
    static NSDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{ @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg", @"png": @"image/png", @"gif": @"image/gif",
               @"mov": @"video/quicktime", @"mp4": @"video/mp4", @"m4v": @"video/mp4",
               @"mp3": @"audio/mpeg", @"m4a": @"audio/mp4", @"m4b": @"audio/mp4", @"aac": @"audio/aac",
               @"wav": @"audio/wav", @"aif": @"audio/aiff", @"aiff": @"audio/aiff", @"ogg": @"audio/ogg", @"flac": @"audio/flac" };
    });
    return m[name.pathExtension.lowercaseString];
}

- (void)download:(NSString *)file fd:(int)fd range:(NSString *)range inline:(BOOL)inl {
    int in = open(file.fileSystemRepresentation, O_RDONLY);
    struct stat st;
    if (in < 0 || fstat(in, &st) != 0 || !S_ISREG(st.st_mode)) {
        if (in >= 0) close(in);
        sendError(fd, 404, @"notfound"); return;
    }
    long long size = st.st_size, from = 0, to = size - 1;
    BOOL partial = NO;
    if ([range hasPrefix:@"bytes="] && [range rangeOfString:@","].location == NSNotFound) {
        NSArray *ab = [[range substringFromIndex:6] componentsSeparatedByString:@"-"];
        if (ab.count == 2) {
            NSString *a = ab[0], *b = ab[1];
            if (a.length) { from = a.longLongValue; if (b.length) to = MIN(b.longLongValue, size - 1); }
            else if (b.length) { from = MAX(0, size - b.longLongValue); }
            if (from > to || from >= size) {
                close(in);
                sendResponse(fd, 416, @"text/plain", NULL, 0, [NSString stringWithFormat:@"Content-Range: bytes */%lld\r\n", size]);
                return;
            }
            partial = YES;
        }
    }
    long long len = size ? to - from + 1 : 0;
    NSString *type = inl ? inlineType(file.lastPathComponent) : nil;
    NSMutableString *h = [baseHeaders(partial ? 206 : 200, type ?: @"application/octet-stream", (unsigned long long)len) mutableCopy];
    [h appendFormat:@"Accept-Ranges: bytes\r\nContent-Disposition: %@; filename*=UTF-8''%@\r\n"
                     "Content-Security-Policy: sandbox\r\n", type ? @"inline" : @"attachment", rfc5987(file.lastPathComponent)];
    if (partial) [h appendFormat:@"Content-Range: bytes %lld-%lld/%lld\r\n", from, to, size];
    [h appendString:@"\r\n"];
    NSData *hd = [h dataUsingEncoding:NSUTF8StringEncoding];
    if (from == 0 && !type) [self log:[NSString stringWithFormat:@"↓ %@ (%@)", file.lastPathComponent, sizeText(size)]];

    BOOL ok = sendAll(fd, hd.bytes, hd.length) && lseek(in, from, SEEK_SET) == from;
    char *chunk = malloc(CHUNK);
    while (ok && len > 0) {
        ssize_t n = read(in, chunk, (size_t)MIN((long long)CHUNK, len));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        ok = sendAll(fd, chunk, (size_t)n);
        len -= n;
    }
    free(chunk);
    close(in);
}

#pragma mark - Upload (gestreamt in Temp-Datei, danach atomar umbenennen)

- (void)upload:(int)fd query:(NSDictionary *)q headers:(NSDictionary *)hdr bodyStart:(NSData *)bodyStart {
    NSString *cl = hdr[@"content-length"];
    if (hdr[@"transfer-encoding"] || !cl.length) { sendError(fd, 411, @"length"); return; }
    char *endp = NULL;
    long long clen = strtoll(cl.UTF8String, &endp, 10);
    if (clen < 0 || !endp || *endp) { sendError(fd, 400, @"length"); return; }
    long long pending = clen - (long long)bodyStart.length;

    // photos=1: in einen Zwischenordner schreiben, danach an die Fotos-App übergeben und wieder löschen
    BOOL toPhotos = [q[@"photos"] isEqualToString:@"1"];
    NSString *name = q[@"n"];
    NSString *dir = toPhotos ? [self stagingDir] : [self resolve:q[@"p"] mustExist:YES];
    if (!dir || !isDirectory(dir) || !validName(name) || [name hasPrefix:@".fmup-"]) {
        sendErrorAndDrain(fd, 400, @"badname", pending); return;
    }
    if (toPhotos && (!self.importer || !self.isMedia || !self.isMedia(name))) { sendErrorAndDrain(fd, 415, @"format", pending); return; }
    NSString *dest = toPhotos ? [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", randomHex(6), name.pathExtension.lowercaseString]]
                              : [dir stringByAppendingPathComponent:name];
    struct stat st;
    if (!toPhotos && lstat(dest.fileSystemRepresentation, &st) == 0) {
        if (!S_ISREG(st.st_mode)) { sendErrorAndDrain(fd, 409, @"isdir", pending); return; }   // nie einen Ordner/Link ersetzen
        if (![q[@"o"] isEqualToString:@"1"]) { sendErrorAndDrain(fd, 409, @"exists", pending); return; }
    }
    if ((unsigned long long)clen + SPACE_RESERVE > freeSpace(dir)) { sendErrorAndDrain(fd, 507, @"space", pending); return; }

    NSString *part = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@".fmup-%@.part", randomHex(6)]];
    int out = open(part.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
    if (out < 0) { sendErrorAndDrain(fd, 403, @"denied", pending); return; }

    long long got = MIN((long long)bodyStart.length, clen);
    BOOL ok = got == 0 || writeAll(out, bodyStart.bytes, (size_t)got);
    char *chunk = malloc(CHUNK);
    while (ok && got < clen) {
        ssize_t n = recv(fd, chunk, (size_t)MIN((long long)CHUNK, clen - got), 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0 || !self.running) { ok = NO; break; }
        if (!writeAll(out, chunk, (size_t)n)) { ok = NO; break; }
        got += n;
    }
    free(chunk);
    if (ok && fsync(out) != 0) ok = NO;
    close(out);
    if (!ok) { unlink(part.fileSystemRepresentation); sendError(fd, 500, @"aborted"); return; }
    // erneut prüfen: in der Zwischenzeit könnte ein Ordner gleichen Namens entstanden sein
    if (lstat(dest.fileSystemRepresentation, &st) == 0 && !S_ISREG(st.st_mode)) {
        unlink(part.fileSystemRepresentation); sendError(fd, 409, @"isdir"); return;
    }
    if (rename(part.fileSystemRepresentation, dest.fileSystemRepresentation) != 0) {
        unlink(part.fileSystemRepresentation); sendError(fd, 500, @"io"); return;
    }
    if (toPhotos) {
        NSString *err = self.importer(dest);
        unlink(dest.fileSystemRepresentation);
        if (err) { sendError(fd, [err isEqualToString:@"photosdenied"] ? 403 : 415, err); return; }
        [self log:[@"↑ " stringByAppendingString:LF(@"%@ → Camera Roll", name)]];
        sendJSON(fd, 200, @{ @"ok": @YES });
        return;
    }
    [self log:[NSString stringWithFormat:@"↑ %@ (%@)", name, sizeText(clen)]];
    // cr=1: Bilder/Videos zusätzlich über ALAssetsLibrary in die Kamerarolle (Datei bleibt liegen)
    if ([q[@"cr"] isEqualToString:@"1"] && self.importer && self.isMedia && self.isMedia(name)) {
        NSString *err = self.importer(dest);
        if (!err) [self log:[@"↑ " stringByAppendingString:LF(@"%@ → Camera Roll", name)]];
        sendJSON(fd, 200, @{ @"ok": @YES, @"cr": err ?: @"ok" });
        return;
    }
    sendJSON(fd, 200, @{ @"ok": @YES });
}

// Zwischenordner für den Foto-Import (gleiches Dateisystem wie /var/mobile -> rename statt kopieren)
- (NSString *)stagingDir {
    NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:@"fm-import"];
    mkdir(d.fileSystemRepresentation, 0700);
    return realPath(d);
}

#pragma mark - Vorhandene Datei in „Aufnahmen“ übernehmen

- (void)importFile:(int)fd path:(NSString *)file {
    struct stat st;
    if (!file || stat(file.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) { sendError(fd, 404, @"notfound"); return; }
    if (!self.importer || !self.isMedia || !self.isMedia(file.lastPathComponent)) { sendError(fd, 415, @"format"); return; }
    // Liegt die Datei schon in DCIM (aber nicht in der Fotos-Datenbank), wird sie VERSCHOBEN: sonst bliebe
    // eine Waise zurück, deren Name (IMG_0001…) mit dem kollidieren kann, den iOS beim Import vergibt.
    BOOL inDCIM = [file rangeOfString:@"/DCIM/"].location != NSNotFound;
    NSString *src = file, *staging = [self stagingDir];
    if (inDCIM) {
        src = [staging stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", randomHex(6), file.pathExtension.lowercaseString]];
        if (!staging || rename(file.fileSystemRepresentation, src.fileSystemRepresentation) != 0) { sendError(fd, 403, @"denied"); return; }
    }
    NSString *err = self.importer(src);
    if (inDCIM) {
        if (err) rename(src.fileSystemRepresentation, file.fileSystemRepresentation);   // zurücklegen
        else unlink(src.fileSystemRepresentation);
    }
    if (err) { sendError(fd, [err isEqualToString:@"photosdenied"] ? 403 : 415, err); return; }
    [self log:[@"↑ " stringByAppendingString:LF(@"%@ → Camera Roll", file.lastPathComponent)]];
    sendJSON(fd, 200, @{ @"ok": @YES, @"moved": @(inDCIM) });
}
@end
