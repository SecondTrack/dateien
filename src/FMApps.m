#import "FMApps.h"
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>

extern char **environ;

#define APPS_DIR  @"/Applications"
#define DPKG_INFO @"/var/lib/dpkg/info"

#pragma mark - Hilfen

// Programm starten und Ausgabe einsammeln (blockiert, nicht auf dem Main-Thread)
static int runCapture(NSString *exe, NSArray *args, NSString **out) {
    int p[2];
    if (pipe(p) != 0) return -1;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, p[1], 1);
    posix_spawn_file_actions_adddup2(&fa, p[1], 2);
    posix_spawn_file_actions_addclose(&fa, p[0]);
    NSUInteger n = args.count;
    char **argv = calloc(n + 2, sizeof(char *));
    argv[0] = (char *)exe.fileSystemRepresentation;
    for (NSUInteger i = 0; i < n; i++) argv[i + 1] = (char *)[args[i] UTF8String];
    char *env[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=C", NULL };
    pid_t pid;
    int r = posix_spawn(&pid, argv[0], &fa, NULL, argv, env);
    posix_spawn_file_actions_destroy(&fa);
    free(argv);
    close(p[1]);
    NSMutableData *d = [NSMutableData data];
    if (r == 0) {
        char buf[4096]; ssize_t k;
        while ((k = read(p[0], buf, sizeof buf)) > 0 || (k < 0 && errno == EINTR)) if (k > 0) [d appendBytes:buf length:(NSUInteger)k];
    }
    close(p[0]);
    if (out) *out = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
    if (r != 0) return -1;
    int st;
    while (waitpid(pid, &st, 0) < 0) if (errno != EINTR) return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

static unsigned long long dirSize(NSString *dir) {
    unsigned long long sum = 0;
    DIR *d = opendir(dir.fileSystemRepresentation);
    if (!d) return 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        NSString *p = [dir stringByAppendingPathComponent:[NSString stringWithUTF8String:e->d_name] ?: @""];
        struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) sum += dirSize(p);
        else if (S_ISREG(st.st_mode)) sum += (unsigned long long)st.st_size;
    }
    closedir(d);
    return sum;
}

// /Applications/X.app -> dpkg-Paket (aus /var/lib/dpkg/info/*.list), neu gelesen nur wenn sich dpkg geändert hat
static NSDictionary *debOwners(void) {
    static NSDictionary *cache; static time_t stamp;
    struct stat st;
    stat(DPKG_INFO.fileSystemRepresentation, &st);
    @synchronized ([NSFileManager class]) {
        if (cache && st.st_mtime == stamp) return cache;
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:DPKG_INFO error:NULL]) {
            if (![f hasSuffix:@".list"]) continue;
            NSString *txt = [NSString stringWithContentsOfFile:[DPKG_INFO stringByAppendingPathComponent:f] encoding:NSUTF8StringEncoding error:NULL];
            for (NSString *line in [txt componentsSeparatedByString:@"\n"]) {
                if (![line hasPrefix:@"/Applications/"] || ![line hasSuffix:@".app"]) continue;
                NSString *rest = [line substringFromIndex:14];
                if ([rest rangeOfString:@"/"].location == NSNotFound) m[rest] = [f stringByDeletingPathExtension];
            }
        }
        cache = m; stamp = st.st_mtime;
        return cache;
    }
}

// Info.plist-Werte gibt es teils gerätespezifisch (z. B. CFBundleIconFiles~ipod bei FaceTime)
static id devValue(NSDictionary *info, NSString *key) {
    return info[[key stringByAppendingString:@"~ipod"]] ?: info[[key stringByAppendingString:@"~iphone"]] ?: info[key];
}

static BOOL isAppleApp(NSString *bid) { return [bid hasPrefix:@"com.apple."]; }

#pragma mark - Liste

NSArray *FMAppsList(void) {
    static NSMutableDictionary *sizes;                     // Pfad|mtime -> Größe
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sizes = [NSMutableDictionary dictionary]; });
    NSDictionary *owners = debOwners();
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *a in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:APPS_DIR error:NULL]) {
        if (![a hasSuffix:@".app"] || [a hasPrefix:@"."]) continue;
        @autoreleasepool {
            NSString *path = [APPS_DIR stringByAppendingPathComponent:a];
            NSBundle *b = [NSBundle bundleWithPath:path];
            NSDictionary *info = b.infoDictionary;
            if (!info) continue;
            NSArray *tags = info[@"SBAppTags"];
            if ([tags isKindOfClass:[NSArray class]] && [tags containsObject:@"hidden"]) continue;
            NSString *name = [b objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [b objectForInfoDictionaryKey:@"CFBundleName"] ?: [a stringByDeletingPathExtension];
            NSString *ver = info[@"CFBundleShortVersionString"] ?: info[@"CFBundleVersion"] ?: @"";
            struct stat st; stat(path.fileSystemRepresentation, &st);
            NSString *key = [NSString stringWithFormat:@"%@|%ld", path, (long)st.st_mtime];
            NSNumber *size;
            @synchronized (sizes) { size = sizes[key]; }
            if (!size) { size = @(dirSize(path)); @synchronized (sizes) { sizes[key] = size; } }
            NSString *pkg = owners[a];
            BOOL ipa = [[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@".fm-ipa"]];
            NSString *bid = info[@"CFBundleIdentifier"] ?: @"";
            // system = von Apple; own = ohne Paket von Hand aufgespielt (z. B. per scp)
            NSString *src = ipa ? @"ipa" : pkg ? @"deb" : isAppleApp(bid) ? @"system" : @"own";
            BOOL rm = ipa || (pkg && ![pkg isEqualToString:@"de.mesh.files"] && ![pkg isEqualToString:@"cydia"])
                   || ([src isEqualToString:@"own"] && ![bid hasPrefix:@"com.saurik."] && ![a isEqualToString:@"Dateien.app"]);
            NSMutableDictionary *e = [@{ @"a": a, @"n": [name description], @"id": info[@"CFBundleIdentifier"] ?: @"", @"v": [ver description],
                                         @"s": size, @"m": @((long long)st.st_mtime), @"src": src, @"rm": @(rm) } mutableCopy];
            if (pkg) e[@"pkg"] = pkg;
            [out addObject:e];
        }
    }
    return out;
}

NSDictionary *FMAppsFind(NSString *appDir) {
    for (NSDictionary *e in FMAppsList()) if ([e[@"a"] isEqualToString:appDir]) return e;
    return nil;
}

#pragma mark - Icon (ImageIO liest auch Apples „CgBI“-PNGs, die Browser nicht können)

NSData *FMAppsIcon(NSString *appDir) {
    if (![appDir hasSuffix:@".app"] || [appDir rangeOfString:@"/"].location != NSNotFound || [appDir hasPrefix:@"."]) return nil;
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 120; });
    NSString *path = [APPS_DIR stringByAppendingPathComponent:appDir];
    NSData *hit = [cache objectForKey:path];
    if (hit) return hit;

    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
    NSMutableArray *names = [NSMutableArray array];
    id icons = devValue(info, @"CFBundleIcons");
    id prim = [icons isKindOfClass:[NSDictionary class]] ? icons[@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"] : nil;
    if ([prim isKindOfClass:[NSArray class]]) [names addObjectsFromArray:prim];
    id files = devValue(info, @"CFBundleIconFiles");
    if ([files isKindOfClass:[NSArray class]]) [names addObjectsFromArray:files];
    id one = devValue(info, @"CFBundleIconFile");
    if ([one isKindOfClass:[NSString class]]) [names addObject:one];
    [names addObjectsFromArray:@[@"Icon.png", @"icon.png", @"Icon-72.png"]];

    CGImageRef best = NULL; size_t bestW = 0;
    for (NSString *n0 in names) {
        if (![n0 isKindOfClass:[NSString class]] || !n0.length) continue;
        NSString *base = [n0.pathExtension isEqualToString:@"png"] ? [n0 stringByDeletingPathExtension] : n0;
        for (NSString *cand in @[[base stringByAppendingString:@"@2x.png"], [base stringByAppendingString:@"@2x~iphone.png"],
                                 [base stringByAppendingString:@".png"], [base stringByAppendingString:@"~iphone.png"], n0]) {
            NSString *f = [path stringByAppendingPathComponent:cand];
            if ([f rangeOfString:@".."].location != NSNotFound) continue;
            CGImageSourceRef s = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:f], NULL);
            if (!s) continue;
            CGImageRef img = CGImageSourceGetCount(s) ? CGImageSourceCreateImageAtIndex(s, 0, NULL) : NULL;
            CFRelease(s);
            if (!img) continue;
            size_t w = CGImageGetWidth(img);
            if (w > bestW && w <= 512) { if (best) CGImageRelease(best); best = img; bestW = w; }
            else CGImageRelease(img);
        }
        if (bestW >= 114) break;
    }
    if (!best) return nil;
    NSMutableData *d = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)d, CFSTR("public.png"), 1, NULL);
    if (dst) { CGImageDestinationAddImage(dst, best, NULL); if (!CGImageDestinationFinalize(dst)) d = nil; CFRelease(dst); }
    CGImageRelease(best);
    if (d.length) [cache setObject:d forKey:path];
    return d.length ? d : nil;
}

#pragma mark - Pakete

NSDictionary *FMPkgInfo(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"ipa"]) return @{ @"n": [path.lastPathComponent stringByDeletingPathExtension] };
    NSString *out = nil;
    if (runCapture(@"/usr/bin/dpkg-deb", @[@"-f", path, @"Package", @"Name", @"Version"], &out) != 0) return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        NSRange c = [line rangeOfString:@": "];
        if (c.location == NSNotFound) continue;
        NSString *k = [line substringToIndex:c.location], *v = [line substringFromIndex:c.location + 2];
        if ([k isEqualToString:@"Package"]) d[@"pkg"] = v;
        else if ([k isEqualToString:@"Name"]) d[@"n"] = v;
        else if ([k isEqualToString:@"Version"]) d[@"v"] = v;
    }
    if (!d[@"pkg"]) return nil;
    if (!d[@"n"]) d[@"n"] = d[@"pkg"];
    return d;
}

NSString *FMSHA256(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return nil;
    CC_SHA256_CTX c; CC_SHA256_Init(&c);
    char *buf = malloc(65536); ssize_t n;
    while ((n = read(fd, buf, 65536)) > 0) CC_SHA256_Update(&c, buf, (CC_LONG)n);
    free(buf); close(fd);
    if (n < 0) return nil;
    unsigned char md[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(md, &c);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", md[i]];
    return s;
}

NSString *FMHelperRun(NSArray *args, NSString **log) {
    NSString *helper = [[NSBundle mainBundle] pathForResource:@"fmpkg" ofType:nil];
    NSString *out = nil;
    if (!helper) { if (log) *log = @"fmpkg fehlt"; return @"helper"; }
    runCapture(helper, args, &out);
    NSString *code = @"helper";
    for (NSString *line in [out componentsSeparatedByString:@"\n"])
        if ([line hasPrefix:@"RESULT "]) code = [line substringFromIndex:7];
    if (log) *log = out;
    return code;
}
