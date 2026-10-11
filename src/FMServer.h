// FMServer — kleiner HTTP-Dateiserver (BSD-Sockets, ein Thread pro Verbindung), iOS 6.
// Zugriff nur mit PIN; danach Sitzungstoken NUR im Header X-FM-Token (kein Cookie -> kein CSRF).
// Downloads laufen über kurzlebige Tickets (/api/ticket -> /dl?k=), damit kein Token in URLs landet.
// Kommandozeile: standardmäßig aus, nur am iPod einschaltbar, eigenes langes Passwort, Auto-Aus.
#import <Foundation/Foundation.h>

@interface FMServer : NSObject
@property (atomic, readonly) BOOL running;
@property (atomic, readonly, copy) NSString *pin;
@property (atomic, readonly) uint16_t port;
@property (atomic, readonly) NSUInteger sessionCount;     // angemeldete Browser
@property (nonatomic, copy) NSString *rootPath;          // nur darunter ist Zugriff erlaubt; nur im gestoppten Zustand ändern
@property (atomic, copy) NSString *deviceName;           // für die Seitenleiste im Browser
@property (atomic, copy) NSString *deviceModel;
@property (nonatomic, copy) void (^onActivity)(NSString *line);   // wird auf dem Main-Thread gerufen
// Übergabe an die Fotos-App (läuft auf dem Verbindungs-Thread, blockierend): nil = ok, sonst Fehlercode
@property (nonatomic, copy) NSString *(^importer)(NSString *path);
@property (nonatomic, copy) BOOL (^isMedia)(NSString *name);
// Rückfrage am iPod (blockiert den Verbindungs-Thread bis getippt wurde oder die Zeit abläuft); YES = bestätigt
@property (nonatomic, copy) BOOL (^confirm)(NSString *title, NSString *message, NSString *okLabel);

// Kommandozeile
@property (atomic, readonly) BOOL shellEnabled;
@property (atomic, readonly) BOOL shellInUse;            // eine Shell läuft gerade
@property (atomic, readonly, copy) NSString *shellPassword;
- (void)setShellEnabled:(BOOL)on;                        // an: neues Passwort; aus: laufende Shell sofort beenden

- (BOOL)startOnPort:(uint16_t)port error:(NSString **)err;
- (void)stop;                                            // schließt alle Verbindungen, alle Sitzungen ungültig
+ (NSString *)wifiAddress;
+ (NSString *)bonjourName;                               // z. B. iPod-touch.local
@end
