// FMApps — installierte Apps auflisten und über den root-Helfer fmpkg (im Bundle) installieren/entfernen.
// Alles hier läuft als mobile; nur fmpkg selbst hat root-Rechte (und prüft, dass wir der Aufrufer sind).
#import <Foundation/Foundation.h>

NSArray *FMAppsList(void);                          // @{a: "X.app", n, id, v, s, src: deb|ipa|system, pkg?, rm}
NSDictionary *FMAppsFind(NSString *appDir);         // ein Eintrag aus FMAppsList oder nil
NSData *FMAppsIcon(NSString *appDir);               // PNG, nil wenn keins
NSDictionary *FMPkgInfo(NSString *path);            // .deb: @{n, pkg, v}; .ipa: @{n}
NSString *FMSHA256(NSString *path);
// fmpkg ausführen; Rückgabe = Ergebniscode ("ok", "dpkg", …), *log = gesamte Ausgabe
NSString *FMHelperRun(NSArray *args, NSString **log);
