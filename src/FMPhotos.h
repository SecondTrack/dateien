// FMPhotos — Import in die Fotos-App („Aufnahmen“), iOS 6.
#import <Foundation/Foundation.h>

void FMPhotosSetup(void);                    // einmal auf dem Main-Thread
BOOL FMPhotosIsMedia(NSString *name);        // Endung, die in „Aufnahmen“ darf
NSString *FMPhotosImport(NSString *path);    // nil = ok, sonst Fehlercode; blockiert, nicht auf dem Main-Thread
