// FMShell — eine Shell-Sitzung (bash) an einem Pseudo-Terminal, IMMER als Benutzer mobile.
// Ausgabe landet in einem Ringpuffer; der Browser holt sie per Long-Polling mit einem Byte-Cursor ab.
#import <Foundation/Foundation.h>

@interface FMShell : NSObject
+ (instancetype)spawnWithError:(NSString **)err;
- (BOOL)write:(NSData *)data;
// Wartet höchstens `wait` Sekunden auf neue Ausgabe ab *cursor; setzt *cursor weiter, *ended = Sitzung vorbei.
- (NSData *)readFrom:(unsigned long long *)cursor wait:(NSTimeInterval)wait ended:(BOOL *)ended;
- (void)terminate;                          // auflegen, alle Prozesse am Terminal beenden
@property (atomic, readonly) BOOL ended;
@end
