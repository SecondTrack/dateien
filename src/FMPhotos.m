// FMPhotos — Bilder/Videos über die offizielle iOS-Schnittstelle (ALAssetsLibrary) in „Aufnahmen“ eintragen.
// Nur so erscheinen sie in der Fotos-App: iOS kopiert die Datei selbst nach DCIM und trägt sie in Photos.sqlite ein.
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>
#import "FMPhotos.h"

static ALAssetsLibrary *gLib;

void FMPhotosSetup(void) {
    if (!gLib) gLib = [[ALAssetsLibrary alloc] init];      // auf dem Main-Thread anlegen, lebt so lange wie die App
}

static NSString *errCode(NSError *e) {
    if (!e) return nil;
    if (e.code == ALAssetsLibraryAccessUserDeniedError || e.code == ALAssetsLibraryAccessGloballyDeniedError) return @"photosdenied";
    if (e.code == ALAssetsLibraryWriteDiskSpaceError) return @"space";
    if (e.code == ALAssetsLibraryWriteIncompatibleDataError || e.code == ALAssetsLibraryWriteInvalidDataError) return @"format";
    return @"photosfail";
}

BOOL FMPhotosIsMedia(NSString *name) {
    static NSSet *ext;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ext = [NSSet setWithObjects:@"jpg", @"jpeg", @"png", @"gif", @"tif", @"tiff", @"bmp",
                                                       @"mov", @"mp4", @"m4v", nil]; });
    return [ext containsObject:name.pathExtension.lowercaseString];
}

// Blockiert bis iOS fertig ist; NIE auf dem Main-Thread aufrufen (dort kommen die Rückmeldungen an).
NSString *FMPhotosImport(NSString *path) {
    if ([NSThread isMainThread] || !gLib) return @"photosfail";
    static NSLock *one;                                     // immer nur ein Import gleichzeitig
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NSLock alloc] init]; });
    [one lock];
    __block NSString *err = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSString *ext = path.pathExtension.lowercaseString;

    if ([@[@"mov", @"mp4", @"m4v"] containsObject:ext]) {
        NSURL *url = [NSURL fileURLWithPath:path];
        if (![gLib videoAtPathIsCompatibleWithSavedPhotosAlbum:url]) err = @"format";   // nur was der iPod abspielen kann
        else {
            [gLib writeVideoAtPathToSavedPhotosAlbum:url completionBlock:^(NSURL *u, NSError *e) {
                err = errCode(e);
                dispatch_semaphore_signal(done);
            }];
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        }
    } else {
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        CGImageSourceRef src = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
        BOOL ok = src && CGImageSourceGetCount(src) > 0 && CGImageSourceGetType(src);
        if (src) CFRelease(src);
        if (!ok) err = @"format";                           // z. B. HEIC/WebP: kann iOS 6 nicht lesen
        else {
            // Originaldaten 1:1 übergeben -> EXIF (Aufnahmedatum, Ausrichtung) bleibt erhalten
            [gLib writeImageDataToSavedPhotosAlbum:data metadata:nil completionBlock:^(NSURL *u, NSError *e) {
                err = errCode(e);
                dispatch_semaphore_signal(done);
            }];
            dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        }
    }
    [one unlock];
    return err;
}
