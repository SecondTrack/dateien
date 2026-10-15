// fmpkg — kleiner root-Helfer der App „Dateien“ (setuid root, liegt im App-Bundle).
// Kann NUR: .deb installieren, .ipa installieren, App-Paket entfernen, per .ipa installierte App entfernen.
//
// Sicherheit:
//  * nimmt Befehle nur von der echten App an: Aufrufer = /Applications/Dateien.app/Dateien, läuft als mobile,
//    wird nicht debuggt und hat keine DYLD_-Variablen (sonst könnte fremder Code in ihrem Namen sprechen).
//    Eine Shell (auch die Kommandozeile der App, Benutzer mobile) kann den Helfer also nicht benutzen.
//  * die App ruft ihn erst auf, nachdem am iPod „Installieren“/„Entfernen“ getippt wurde.
//  * die Datei wird zuerst in einen root-eigenen Ordner kopiert und per SHA-256 mit dem bestätigten Stand
//    verglichen -> kein Austausch zwischen Bestätigung und Installation.
//  * Systempakete und Apps, die nicht von dpkg bzw. von hier stammen, werden nie angefasst.
// Ausgabe: Protokollzeilen, als letzte Zeile „RESULT ok“ oder „RESULT <fehlercode>“.
#include <stdio.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <spawn.h>
#include <ftw.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <zlib.h>
#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>

#define APP_BIN   "/Applications/Dateien.app/Dateien"
#define MOBILE    501
#define MARKER    ".fm-ipa"                 // kennzeichnet per .ipa installierte Apps
#define DPKG_INFO "/var/lib/dpkg/info/"

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);

static char *cleanEnv[] = { "PATH=/usr/sbin:/usr/bin:/sbin:/bin", "HOME=/var/root", "LANG=C", NULL };
static char tmpDir[64];

static void cleanup(void);
static void finish(const char *code) {
    cleanup();
    fflush(stderr);
    printf("RESULT %s\n", code);
    fflush(stdout);
    exit(strcmp(code, "ok") == 0 ? 0 : 1);
}

// ---------- Aufrufer prüfen ----------
/* Einzige erlaubte DYLD_-Variable: DYLD_INSERT_LIBRARIES, wenn darin nur Cydia Substrate steht (so lädt
 * Substrate sich unter iOS 5/6 in jede App). Jede Bibliothek muss aufgelöst unter
 * /Library/Frameworks/CydiaSubstrate.framework/ oder /Library/MobileSubstrate/ liegen, root gehören und
 * für niemand anderen beschreibbar sein. Alles andere (eigene Bibliotheken, DYLD_LIBRARY_PATH …) bleibt verboten. */
static int hasPrefixStr(const char *s, const char *p) { return strncmp(s, p, strlen(p)) == 0; }
static int trustedDyld(const char *kv) {
    const char *key = "DYLD_INSERT_LIBRARIES=";
    if (!hasPrefixStr(kv, key)) return 0;
    const char *val = kv + strlen(key);
    char list[1024];
    size_t n = strlen(val);
    if (n == 0 || n >= sizeof list) return 0;
    memcpy(list, val, n + 1);
    char *save = NULL;
    for (char *p = strtok_r(list, ":", &save); p; p = strtok_r(NULL, ":", &save)) {
        char real[PATH_MAX]; struct stat st;
        if (!realpath(p, real)) return 0;
        if (!hasPrefixStr(real, "/Library/Frameworks/CydiaSubstrate.framework/") && !hasPrefixStr(real, "/Library/MobileSubstrate/")) return 0;
        if (lstat(real, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 022)) return 0;
    }
    return 1;
}

static int callerOK(void) {
    if (getuid() != MOBILE || geteuid() != 0) return 0;
    pid_t pp = getppid();
    char path[1024] = { 0 };
    if (proc_pidpath(pp, path, sizeof path) <= 0 || strcmp(path, APP_BIN) != 0) return 0;
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pp };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0) return 0;
    if (kp.kp_eproc.e_ucred.cr_uid != MOBILE || (kp.kp_proc.p_flag & P_TRACED)) return 0;
    int argmax = 0; size_t sz = sizeof argmax;
    int mma[2] = { CTL_KERN, KERN_ARGMAX };
    if (sysctl(mma, 2, &argmax, &sz, NULL, 0) != 0 || argmax <= 0) return 0;
    char *buf = malloc((size_t)argmax);
    int mpa[3] = { CTL_KERN, KERN_PROCARGS2, pp };
    sz = (size_t)argmax;
    if (!buf || sysctl(mpa, 3, buf, &sz, NULL, 0) != 0) { free(buf); return 0; }
    int ok = 1;
    for (size_t i = sizeof(int); i < sz; ) {                // Pfad, Argumente, Umgebung: nullgetrennt
        size_t n = strnlen(buf + i, sz - i);
        if (n >= 5 && strncmp(buf + i, "DYLD_", 5) == 0 && !trustedDyld(buf + i)) { ok = 0; break; }
        i += n + 1;
    }
    free(buf);
    return ok;
}

// ---------- Prozesse ----------
static int run(char *const argv[]) {
    pid_t pid;
    fflush(stdout); fflush(stderr);
    if (posix_spawn(&pid, argv[0], NULL, NULL, argv, cleanEnv) != 0) return -1;
    int st;
    while (waitpid(pid, &st, 0) < 0) if (errno != EINTR) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

static int capture(char *const argv[], char *out, size_t cap) {
    int p[2];
    if (pipe(p) != 0) return -1;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_addclose(&fa, p[0]);
    pid_t pid;
    int r = posix_spawn(&pid, argv[0], &fa, NULL, argv, cleanEnv);
    posix_spawn_file_actions_destroy(&fa);
    close(p[1]);
    size_t n = 0;
    if (r == 0) {
        ssize_t k;
        while ((k = read(p[0], out + n, cap - 1 - n)) > 0) { n += (size_t)k; if (n >= cap - 1) break; }
    }
    close(p[0]);
    out[n] = 0;
    while (n && (out[n - 1] == '\n' || out[n - 1] == ' ')) out[--n] = 0;
    if (r != 0) return -1;
    int st;
    while (waitpid(pid, &st, 0) < 0) if (errno != EINTR) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

// uicache als mobile (so wie von Hand: su mobile -c uicache)
static void uicache(void) {
    fflush(stdout); fflush(stderr);
    pid_t pid = fork();
    if (pid == 0) {
        char *env[] = { "PATH=/usr/bin:/bin", "HOME=/var/mobile", "USER=mobile", NULL };
        if (setgid(MOBILE) != 0 || setuid(MOBILE) != 0) _exit(1);
        execle("/usr/bin/uicache", "uicache", (char *)NULL, env);
        _exit(127);
    }
    if (pid > 0) { int st; while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {} }
}

// ---------- Dateien ----------
static int rmEntry(const char *p, const struct stat *s, int flag, struct FTW *f) { (void)s; (void)flag; (void)f; return remove(p); }
static void rmtree(const char *p) { nftw(p, rmEntry, 32, FTW_DEPTH | FTW_PHYS); }
static int chownEntry(const char *p, const struct stat *s, int flag, struct FTW *f) { (void)s; (void)flag; (void)f; lchown(p, 0, 0); return 0; }
static void cleanup(void) { if (tmpDir[0]) { rmtree(tmpDir); tmpDir[0] = 0; } }

static int validPkg(const char *s) {
    if (!*s || strlen(s) > 128) return 0;
    for (; *s; s++) if (!((*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9') || strchr(".+-", *s))) return 0;
    return 1;
}
static int validApp(const char *s) {                      // „Name.app“, eine Pfadkomponente
    size_t n = strlen(s);
    if (n < 5 || n > 200 || strcmp(s + n - 4, ".app") != 0 || s[0] == '.') return 0;
    for (; *s; s++) if (*s == '/' || (unsigned char)*s < 0x20) return 0;
    return 1;
}

// in den root-eigenen Ordner kopieren und dabei hashen; Hash muss dem bestätigten entsprechen
static int copyVerify(const char *src, const char *sha, const char *dst) {
    int in = open(src, O_RDONLY | O_NOFOLLOW);
    struct stat st;
    if (in < 0 || fstat(in, &st) != 0 || !S_ISREG(st.st_mode)) { if (in >= 0) close(in); return 0; }
    int out = open(dst, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (out < 0) { close(in); return 0; }
    CC_SHA256_CTX c; CC_SHA256_Init(&c);
    static char buf[65536];
    ssize_t n; int ok = 1;
    while ((n = read(in, buf, sizeof buf)) > 0) {
        CC_SHA256_Update(&c, buf, (CC_LONG)n);
        if (write(out, buf, (size_t)n) != n) { ok = 0; break; }
    }
    if (n < 0) ok = 0;
    close(in); close(out);
    unsigned char md[CC_SHA256_DIGEST_LENGTH]; char hex[65];
    CC_SHA256_Final(md, &c);
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) sprintf(hex + i * 2, "%02x", md[i]);
    return ok && strcasecmp(hex, sha) == 0;
}

// ---------- .deb ----------
static void installDeb(const char *src, const char *sha) {
    char deb[128]; snprintf(deb, sizeof deb, "%s/p.deb", tmpDir);
    if (!copyVerify(src, sha, deb)) finish("changed");
    char pkg[256], arch[64];
    char *fp[] = { "/usr/bin/dpkg-deb", "-f", deb, "Package", NULL };
    char *fa[] = { "/usr/bin/dpkg-deb", "-f", deb, "Architecture", NULL };
    if (capture(fp, pkg, sizeof pkg) != 0 || !validPkg(pkg)) finish("notdeb");
    if (capture(fa, arch, sizeof arch) != 0 || (strcmp(arch, "iphoneos-arm") && strcmp(arch, "all"))) finish("arch");
    char list[512]; snprintf(list, sizeof list, DPKG_INFO "%s.list", pkg);
    int had = access(list, F_OK) == 0;
    printf("dpkg -i %s\n", pkg);
    char *di[] = { "/usr/bin/dpkg", "-i", deb, NULL };
    if (run(di) != 0) {
        if (!had) {                                          // halb installiertes Paket wieder entfernen
            printf("rollback: dpkg -r %s\n", pkg);
            char *dr[] = { "/usr/bin/dpkg", "-r", pkg, NULL };
            run(dr);
        }
        uicache();
        finish("dpkg");
    }
    uicache();
    finish("ok");
}

// Paket entfernen – nur wenn es eine App unter /Applications mitbringt (keine Systempakete)
static void removePkg(const char *pkg) {
    if (!validPkg(pkg) || !strcmp(pkg, "de.mesh.files") || !strcmp(pkg, "cydia")) finish("protected");
    char list[512]; snprintf(list, sizeof list, DPKG_INFO "%s.list", pkg);
    FILE *f = fopen(list, "r");
    if (!f) finish("notfound");
    char line[1024]; int app = 0;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\n")] = 0;
        if (!strncmp(line, "/Applications/", 14) && validApp(line + 14)) { app = 1; break; }
    }
    fclose(f);
    if (!app) finish("protected");
    printf("dpkg -r %s\n", pkg);
    char *dr[] = { "/usr/bin/dpkg", "-r", (char *)pkg, NULL };
    int r = run(dr);
    uicache();
    finish(r == 0 ? "ok" : "dpkg");
}

// ---------- .ipa (ZIP, ohne unzip: Zentralverzeichnis lesen, gespeichert/deflate) ----------
static unsigned rd16(const unsigned char *p) { return p[0] | p[1] << 8; }
static unsigned rd32(const unsigned char *p) { return p[0] | p[1] << 8 | p[2] << 16 | (unsigned)p[3] << 24; }

static int safeName(const char *n) {
    if (strncmp(n, "Payload/", 8) != 0 || strstr(n, "..") || strstr(n, "//") || strchr(n, '\\')) return 0;
    for (const char *s = n; *s; s++) if ((unsigned char)*s < 0x20) return 0;
    return 1;
}
static int mkdirs(const char *path) {                       // alle Elternordner anlegen
    char t[1024]; snprintf(t, sizeof t, "%s", path);
    for (char *s = t + 1; *s; s++) if (*s == '/') { *s = 0; if (mkdir(t, 0755) != 0 && errno != EEXIST) return 0; *s = '/'; }
    return 1;
}

static int extractEntry(int fd, unsigned long off, unsigned method, unsigned long csize, unsigned long usize, const char *dst, int exec) {
    unsigned char lh[30];
    if (pread(fd, lh, 30, (off_t)off) != 30 || rd32(lh) != 0x04034b50) return 0;
    off_t data = (off_t)off + 30 + rd16(lh + 26) + rd16(lh + 28);
    if (!mkdirs(dst)) return 0;
    int out = open(dst, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, exec ? 0755 : 0644);
    if (out < 0) return 0;
    static unsigned char ib[65536], ob[65536];
    int ok = 1; unsigned long left = csize, wrote = 0;
    if (method == 0) {
        while (left && ok) {
            ssize_t n = pread(fd, ib, left < sizeof ib ? left : sizeof ib, data);
            if (n <= 0 || write(out, ib, (size_t)n) != n) ok = 0;
            else { data += n; left -= (unsigned long)n; wrote += (unsigned long)n; }
        }
    } else if (method == 8) {
        z_stream z; memset(&z, 0, sizeof z);
        if (inflateInit2(&z, -15) != Z_OK) ok = 0;
        int zr = Z_OK;
        while (ok && zr != Z_STREAM_END) {
            if (z.avail_in == 0) {
                if (!left) { ok = 0; break; }
                ssize_t n = pread(fd, ib, left < sizeof ib ? left : sizeof ib, data);
                if (n <= 0) { ok = 0; break; }
                data += n; left -= (unsigned long)n;
                z.next_in = ib; z.avail_in = (uInt)n;
            }
            z.next_out = ob; z.avail_out = sizeof ob;
            zr = inflate(&z, Z_NO_FLUSH);
            if (zr != Z_OK && zr != Z_STREAM_END) { ok = 0; break; }
            size_t got = sizeof ob - z.avail_out;
            if (got && write(out, ob, got) != (ssize_t)got) ok = 0;
            wrote += got;
        }
        inflateEnd(&z);
    } else ok = 0;
    close(out);
    return ok && wrote == usize;
}

static CFStringRef plistString(CFDictionaryRef d, const char *key) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFDictionaryGetValue(d, k);
    CFRelease(k);
    return v && CFGetTypeID(v) == CFStringGetTypeID() ? (CFStringRef)v : NULL;
}

static void installIpa(const char *src, const char *sha) {
    // auf dem Systemvolume entpacken, damit am Ende ein einfaches rename() reicht
    char stage[64]; snprintf(stage, sizeof stage, "/Applications/.fmpkg-XXXXXX");
    if (!mkdtemp(stage)) finish("io");
    char ipa[128]; snprintf(ipa, sizeof ipa, "%s/p.ipa", tmpDir);
    if (!copyVerify(src, sha, ipa)) { rmtree(stage); finish("changed"); }
    int fd = open(ipa, O_RDONLY);
    struct stat st; fstat(fd, &st);
    // Ende des Zentralverzeichnisses suchen
    size_t tail = st.st_size < 65557 ? (size_t)st.st_size : 65557;
    unsigned char *t = malloc(tail);
    if (!t || pread(fd, t, tail, st.st_size - (off_t)tail) != (ssize_t)tail) { rmtree(stage); finish("notipa"); }
    long eo = -1;
    for (long i = (long)tail - 22; i >= 0; i--) if (rd32(t + i) == 0x06054b50) { eo = i; break; }
    if (eo < 0) { rmtree(stage); finish("notipa"); }
    unsigned count = rd16(t + eo + 10);
    unsigned long cdSize = rd32(t + eo + 12), cdOff = rd32(t + eo + 16);
    free(t);
    if (cdOff == 0xffffffffUL || cdOff + cdSize > (unsigned long)st.st_size) { rmtree(stage); finish("notipa"); }
    unsigned char *cd = malloc(cdSize);
    if (!cd || pread(fd, cd, cdSize, (off_t)cdOff) != (ssize_t)cdSize) { rmtree(stage); finish("notipa"); }

    // Platz prüfen (Systemvolume ist klein)
    unsigned long long need = 0;
    for (unsigned i = 0, p = 0; i < count && p + 46 <= cdSize; i++) { need += rd32(cd + p + 24); p += 46 + rd16(cd + p + 28) + rd16(cd + p + 30) + rd16(cd + p + 32); }
    struct statfs sf;
    if (statfs("/Applications", &sf) == 0 && need + 20ULL * 1024 * 1024 > (unsigned long long)sf.f_bavail * sf.f_bsize) { rmtree(stage); finish("space"); }

    char appName[256] = { 0 };
    for (unsigned i = 0, p = 0; i < count; i++) {
        if (p + 46 > cdSize || rd32(cd + p) != 0x02014b50) { rmtree(stage); finish("notipa"); }
        unsigned method = rd16(cd + p + 10), nlen = rd16(cd + p + 28);
        unsigned long csize = rd32(cd + p + 20), usize = rd32(cd + p + 24), loff = rd32(cd + p + 42);
        unsigned long ext = rd32(cd + p + 38);
        char name[1024];
        if (nlen >= sizeof name || p + 46 + nlen > cdSize) { rmtree(stage); finish("notipa"); }
        memcpy(name, cd + p + 46, nlen); name[nlen] = 0;
        p += 46 + nlen + rd16(cd + p + 30) + rd16(cd + p + 32);
        if (strncmp(name, "Payload/", 8) != 0) continue;    // iTunesMetadata etc. ignorieren
        if (!safeName(name)) { rmtree(stage); finish("notipa"); }
        unsigned mode = (unsigned)(ext >> 16);
        if ((mode & S_IFMT) == S_IFLNK) continue;            // Symlinks nie übernehmen
        // Name der App: Payload/<X>.app/...
        const char *a = name + 8, *slash = strchr(a, '/');
        if (slash) {
            char an[256]; size_t al = (size_t)(slash - a);
            if (al >= sizeof an) { rmtree(stage); finish("notipa"); }
            memcpy(an, a, al); an[al] = 0;
            if (!validApp(an)) { rmtree(stage); finish("notipa"); }
            if (!appName[0]) snprintf(appName, sizeof appName, "%s", an);
            else if (strcmp(appName, an) != 0) { rmtree(stage); finish("notipa"); }   // genau eine App
        }
        char dst[1400]; snprintf(dst, sizeof dst, "%s/%s", stage, name);
        if (name[nlen - 1] == '/') { if (!mkdirs(dst) || (mkdir(dst, 0755) != 0 && errno != EEXIST)) { rmtree(stage); finish("io"); } continue; }
        if (!extractEntry(fd, loff, method, csize, usize, dst, (mode & 0111) != 0)) { rmtree(stage); finish("notipa"); }
    }
    free(cd); close(fd);
    if (!appName[0]) { rmtree(stage); finish("notipa"); }

    char app[512]; snprintf(app, sizeof app, "%s/Payload/%s", stage, appName);
    char plist[600]; snprintf(plist, sizeof plist, "%s/Info.plist", app);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)plist, (CFIndex)strlen(plist), false);
    CFReadStreamRef rs = CFReadStreamCreateWithFile(NULL, u);
    CFRelease(u);
    CFPropertyListRef pl = NULL;
    if (rs && CFReadStreamOpen(rs)) pl = CFPropertyListCreateWithStream(NULL, rs, 0, kCFPropertyListImmutable, NULL, NULL);
    if (rs) { CFReadStreamClose(rs); CFRelease(rs); }
    if (!pl || CFGetTypeID(pl) != CFDictionaryGetTypeID()) { rmtree(stage); finish("notipa"); }
    CFStringRef ex = plistString(pl, "CFBundleExecutable"), bid = plistString(pl, "CFBundleIdentifier");
    char exe[256], bidc[256];
    if (!ex || !bid || !CFStringGetCString(ex, exe, sizeof exe, kCFStringEncodingUTF8) || !CFStringGetCString(bid, bidc, sizeof bidc, kCFStringEncodingUTF8)
        || strchr(exe, '/') || !exe[0]) { rmtree(stage); finish("notipa"); }
    CFRelease(pl);
    char bin[900]; snprintf(bin, sizeof bin, "%s/%s", app, exe);
    chmod(bin, 0755);

    // Ziel: /Applications/<X>.app – vorhandene App nur ersetzen, wenn sie selbst per .ipa kam
    char target[512], mark[600];
    snprintf(target, sizeof target, "/Applications/%s", appName);
    struct stat ts;
    if (lstat(target, &ts) == 0) {
        snprintf(mark, sizeof mark, "%s/" MARKER, target);
        if (!S_ISDIR(ts.st_mode) || access(mark, F_OK) != 0) { rmtree(stage); finish("exists"); }
        char old[600]; snprintf(old, sizeof old, "%s/old.app", stage);
        if (rename(target, old) != 0) { rmtree(stage); finish("io"); }
        printf("replace %s\n", appName);
    }
    nftw(app, chownEntry, 32, FTW_PHYS);
    snprintf(mark, sizeof mark, "%s/" MARKER, app);
    FILE *m = fopen(mark, "w"); if (m) { fprintf(m, "%s\n", bidc); fclose(m); }
    if (rename(app, target) != 0) { rmtree(stage); finish("io"); }
    rmtree(stage);
    printf("installed %s (%s)\n", appName, bidc);
    uicache();
    finish("ok");
}

// gehört /Applications/<name> zu einem dpkg-Paket? (dann nur über remove-pkg)
static int ownedByDpkg(const char *name) {
    char want[600]; snprintf(want, sizeof want, "/Applications/%s", name);
    DIR *d = opendir(DPKG_INFO);
    if (!d) return 1;                                        // im Zweifel: ja (nicht anfassen)
    struct dirent *e; int found = 0;
    char line[1024], path[1200];
    while (!found && (e = readdir(d))) {
        size_t n = strlen(e->d_name);
        if (n < 6 || strcmp(e->d_name + n - 5, ".list") != 0) continue;
        snprintf(path, sizeof path, DPKG_INFO "%s", e->d_name);
        FILE *f = fopen(path, "r");
        if (!f) continue;
        while (fgets(line, sizeof line, f)) { line[strcspn(line, "\n")] = 0; if (!strcmp(line, want)) { found = 1; break; } }
        fclose(f);
    }
    closedir(d);
    return found;
}

// Bundle-ID aus Info.plist; Apple- und Cydia-Apps sowie die App selbst sind tabu
static int foreignApp(const char *target) {
    char plist[700]; snprintf(plist, sizeof plist, "%s/Info.plist", target);
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)plist, (CFIndex)strlen(plist), false);
    CFReadStreamRef rs = CFReadStreamCreateWithFile(NULL, u);
    CFRelease(u);
    CFPropertyListRef pl = NULL;
    if (rs && CFReadStreamOpen(rs)) pl = CFPropertyListCreateWithStream(NULL, rs, 0, kCFPropertyListImmutable, NULL, NULL);
    if (rs) { CFReadStreamClose(rs); CFRelease(rs); }
    if (!pl || CFGetTypeID(pl) != CFDictionaryGetTypeID()) { if (pl) CFRelease(pl); return 0; }
    CFStringRef bid = plistString(pl, "CFBundleIdentifier");
    char b[256] = { 0 };
    int ok = bid && CFStringGetCString(bid, b, sizeof b, kCFStringEncodingUTF8) && b[0]
          && strncmp(b, "com.apple.", 10) && strncmp(b, "com.saurik.", 11) && strcmp(b, "de.mesh.files");
    CFRelease(pl);
    return ok;
}

static void removeApp(const char *name) {
    if (!validApp(name)) finish("protected");
    char target[512], mark[600];
    snprintf(target, sizeof target, "/Applications/%s", name);
    snprintf(mark, sizeof mark, "%s/" MARKER, target);
    struct stat ts;
    if (lstat(target, &ts) != 0 || !S_ISDIR(ts.st_mode)) finish("notfound");
    // erlaubt: per .ipa von hier installiert, oder von Hand aufgespielt (kein dpkg-Paket, nicht Apple/Cydia)
    if (access(mark, F_OK) != 0 && (ownedByDpkg(name) || !foreignApp(target))) finish("protected");
    rmtree(target);
    printf("removed %s\n", name);
    uicache();
    finish(access(target, F_OK) == 0 ? "io" : "ok");
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    dup2(1, 2);                                              // alles in eine Ausgabe
    if (!callerOK()) finish("caller");
    if (setgid(0) != 0 || setuid(0) != 0) finish("root");
    umask(022);
    if (argc == 4 && (!strcmp(argv[1], "install-deb") || !strcmp(argv[1], "install-ipa"))) {
        snprintf(tmpDir, sizeof tmpDir, "/var/tmp/fmpkg-XXXXXX");
        if (!mkdtemp(tmpDir)) { tmpDir[0] = 0; finish("io"); }
        if (!strcmp(argv[1], "install-deb")) installDeb(argv[2], argv[3]);
        else installIpa(argv[2], argv[3]);
    }
    if (argc == 3 && !strcmp(argv[1], "remove-pkg")) removePkg(argv[2]);
    if (argc == 3 && !strcmp(argv[1], "remove-app")) removeApp(argv[2]);
    finish("usage");
    return 1;
}
