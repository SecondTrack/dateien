#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "FMServer.h"
#import "FMQR.h"
#import "FMPhotos.h"
#import "MeshL10n.h"

#define FM_PORT     8080

// ---- kleines Theme: Hell & klar (iOS-nativ) ----
static UIColor *C(int r, int g, int b) { return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
#define BG    C(242,242,247)
#define CARD  [UIColor whiteColor]
#define LINE  C(209,209,214)
#define INK   C(0,0,0)
#define MUT   C(142,142,147)
#define ACC   C(0,122,255)
#define GRN   C(52,199,89)
#define ORG   C(255,149,0)
#define RED   C(255,59,48)

static UILabel *label(CGRect f, UIFont *font, UIColor *color, NSTextAlignment align) {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.font = font; l.textColor = color; l.textAlignment = align; l.backgroundColor = [UIColor clearColor];
    return l;
}

static UIView *card(CGRect f) {
    UIView *v = [[UIView alloc] initWithFrame:f];
    v.backgroundColor = CARD; v.layer.cornerRadius = 12;
    v.layer.borderWidth = 0.5; v.layer.borderColor = LINE.CGColor;
    return v;
}

// mehrzeiliges Label, Höhe passt sich dem Text an
static CGFloat fitLabel(UILabel *l, NSString *text) {
    l.text = text; l.numberOfLines = 0;
    CGSize s = [text sizeWithFont:l.font constrainedToSize:CGSizeMake(l.frame.size.width, 400) lineBreakMode:NSLineBreakByWordWrapping];
    CGRect f = l.frame; f.size.height = ceil(s.height); l.frame = f;
    return f.size.height;
}

// runde Nummer für die Schritte 1 / 2
static UILabel *badge(CGPoint p, NSString *n) {
    UILabel *b = label(CGRectMake(p.x, p.y, 24, 24), [UIFont boldSystemFontOfSize:14], [UIColor whiteColor], NSTextAlignmentCenter);
    b.backgroundColor = ACC; b.layer.cornerRadius = 12; b.text = n;
    return b;
}

static UIButton *bigButton(CGRect f, UIColor *bg, UIColor *fg, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = f; b.backgroundColor = bg; b.layer.cornerRadius = 12;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [b setTitleColor:fg forState:UIControlStateNormal];
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// QR-Matrix -> scharfes Bild (1 Pixel pro Modul + 4 Module Ruhezone; skaliert mit Nearest-Filter)
static UIImage *qrImage(NSString *text) {
    uint8_t m[FMQR_MAX_SIZE * FMQR_MAX_SIZE];
    int n = fmqr_encode(text.UTF8String, m);
    if (!n) return nil;
    int W = n + 8;
    uint8_t *px = malloc((size_t)(W * W));
    memset(px, 255, (size_t)(W * W));
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++)
            if (m[y * n + x]) px[(y + 4) * W + x + 4] = 0;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(px, (size_t)W, (size_t)W, 8, (size_t)W, cs, (CGBitmapInfo)kCGImageAlphaNone);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    UIImage *res = [UIImage imageWithCGImage:img];
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(px);
    return res;
}

#pragma mark - Extras: Kommandozeile

@interface FMShellController : UIViewController
- (instancetype)initWithServer:(FMServer *)server;
- (void)refresh;
@end

@implementation FMShellController {
    FMServer *_server;
    UISwitch *_switch;
    UIView *_passCard;
    UILabel *_pass, *_state;
}

- (instancetype)initWithServer:(FMServer *)server {
    if ((self = [super init])) _server = server;
    return self;
}

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = BG;
    CGFloat W = self.view.bounds.size.width;

    UILabel *title = label(CGRectMake(0, 12, W, 24), [UIFont boldSystemFontOfSize:17], INK, NSTextAlignmentCenter);
    title.text = L(@"Command line");
    [self.view addSubview:title];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeCustom];
    done.frame = CGRectMake(W - 80, 8, 76, 32);
    done.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [done setTitle:L(@"Done") forState:UIControlStateNormal];
    [done setTitleColor:ACC forState:UIControlStateNormal];
    [done addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:done];

    UILabel *intro = label(CGRectMake(20, 50, W - 40, 0), [UIFont systemFontOfSize:14], MUT, NSTextAlignmentLeft);
    CGFloat y = 50 + fitLabel(intro, L(@"For experts: run commands on the iPod from the browser. It runs with limited rights (user “mobile”, not root) and switches itself off after 10 minutes without input.")) + 16;
    [self.view addSubview:intro];

    UIView *row = card(CGRectMake(16, y, W - 32, 50));
    [self.view addSubview:row];
    UILabel *rl = label(CGRectMake(14, 0, W - 32 - 110, 50), [UIFont systemFontOfSize:16], INK, NSTextAlignmentLeft);
    rl.text = L(@"Allow command line");
    [row addSubview:rl];
    _switch = [[UISwitch alloc] init];
    _switch.onTintColor = GRN;
    CGRect sf = _switch.frame;
    sf.origin = CGPointMake(row.bounds.size.width - sf.size.width - 12, (50 - sf.size.height) / 2);
    _switch.frame = sf;
    [_switch addTarget:self action:@selector(toggled) forControlEvents:UIControlEventValueChanged];
    [row addSubview:_switch];
    y += 66;

    _passCard = card(CGRectMake(16, y, W - 32, 128));
    [self.view addSubview:_passCard];
    UILabel *ph = label(CGRectMake(14, 12, W - 60, 18), [UIFont boldSystemFontOfSize:14], MUT, NSTextAlignmentLeft);
    ph.text = L(@"Password");
    [_passCard addSubview:ph];
    _pass = label(CGRectMake(8, 34, W - 48, 34), [UIFont fontWithName:@"Courier-Bold" size:30], INK, NSTextAlignmentCenter);
    _pass.adjustsFontSizeToFitWidth = YES; _pass.minimumScaleFactor = 0.6;
    [_passCard addSubview:_pass];
    UILabel *pn = label(CGRectMake(14, 72, W - 60, 0), [UIFont systemFontOfSize:13], MUT, NSTextAlignmentLeft);
    fitLabel(pn, L(@"Enter it in the browser under “Command line”. A new password is made every time you switch it on."));
    [_passCard addSubview:pn];

    _state = label(CGRectMake(20, y + 140, W - 40, 20), [UIFont boldSystemFontOfSize:14], ORG, NSTextAlignmentCenter);
    [self.view addSubview:_state];
    [self refresh];
}

- (void)toggled {
    if (_switch.on && !_server.running) { _switch.on = NO; return; }
    [_server setShellEnabled:_switch.on];
    [self refresh];
}

- (void)refresh {
    if (!_switch) return;
    BOOL on = _server.shellEnabled;
    [_switch setOn:on animated:YES];
    _switch.enabled = _server.running;
    _passCard.hidden = !on;
    _pass.text = _server.shellPassword ?: @"";
    _state.text = _server.shellInUse ? L(@"In use right now") : (_server.running ? @"" : L(@"Start sharing first."));
    _state.textColor = _server.shellInUse ? ORG : MUT;
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

#pragma mark - Hauptschirm

@interface FMViewController : UIViewController <UIAlertViewDelegate>
- (void)startServer;
- (void)stopServer;
- (void)refreshUI;
@property (nonatomic, readonly) BOOL running;
@end

@implementation FMViewController {
    FMServer *_server;
    UIScrollView *_scroll;
    // aus
    UIView *_offView;
    UILabel *_offHint, *_offError;
    UIButton *_startBtn;
    // an
    UIView *_onView, *_steps, *_addrBox, *_noWifi;
    UILabel *_status, *_shellNote, *_pin, *_host, *_ip;
    UIImageView *_qr;
    UIButton *_stopBtn, *_extras;
    NSTimer *_timer;
    NSString *_lastError, *_shownQR;
    FMShellController *_shellVC;
    UIAlertView *_ask;
    void (^_askDone)(BOOL yes);
}

- (instancetype)init {
    if ((self = [super init])) {
        _server = [[FMServer alloc] init];
        _server.rootPath = @"/";      // ganzes System; Schnellzugriffe stehen im Browser
        UIDevice *dev = [UIDevice currentDevice];
        _server.deviceName = dev.name;
        _server.deviceModel = dev.model;
        __weak FMViewController *ws = self;
        _server.onActivity = ^(NSString *line) { NSLog(@"Dateien: %@", line); [ws refreshUI]; };
        FMPhotosSetup();
        _server.importer = ^NSString *(NSString *path) { return FMPhotosImport(path); };
        _server.isMedia = ^BOOL(NSString *name) { return FMPhotosIsMedia(name); };
        // Installieren/Entfernen von Apps: nur nach Tippen am iPod; ohne Antwort nach 2 Minuten abgelehnt
        _server.confirm = ^BOOL(NSString *title, NSString *msg, NSString *ok) {
            __block BOOL yes = NO;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_main_queue(), ^{
                [ws ask:title message:msg ok:ok done:^(BOOL y) { yes = y; dispatch_semaphore_signal(done); }];
            });
            if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)) != 0) {
                dispatch_async(dispatch_get_main_queue(), ^{ [ws cancelAsk]; });
                return NO;
            }
            return yes;
        };
    }
    return self;
}

- (BOOL)running { return _server.running; }

- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = BG;
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.scrollEnabled = NO;                 // alles passt auf eine Bildschirmhöhe
    [self.view addSubview:_scroll];

    // ================= AUS =================
    _offView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    [_scroll addSubview:_offView];
    CGFloat y = 44;
    UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake((W - 80) / 2, y, 80, 80)];
    logo.image = [UIImage imageNamed:@"Icon"];
    [_offView addSubview:logo];
    y += 92;
    UILabel *name = label(CGRectMake(0, y, W, 32), [UIFont boldSystemFontOfSize:26], INK, NSTextAlignmentCenter);
    name.text = L(@"Files");
    [_offView addSubview:name];
    y += 42;
    UILabel *intro = label(CGRectMake(28, y, W - 56, 0), [UIFont systemFontOfSize:16], C(60,60,67), NSTextAlignmentCenter);
    y += fitLabel(intro, L(@"Look at the photos, music and files on this iPod from your phone or computer – no cable, just in the browser.")) + 28;
    [_offView addSubview:intro];
    _startBtn = bigButton(CGRectMake(24, y, W - 48, 56), ACC, [UIColor whiteColor], self, @selector(startTapped));
    _startBtn.titleLabel.font = [UIFont boldSystemFontOfSize:19];
    [_startBtn setTitle:L(@"Start sharing") forState:UIControlStateNormal];
    [self pressEffect:_startBtn];
    [_offView addSubview:_startBtn];
    y += 70;
    _offHint = label(CGRectMake(28, y, W - 56, 40), [UIFont systemFontOfSize:13], MUT, NSTextAlignmentCenter);
    [_offView addSubview:_offHint];
    _offError = label(CGRectMake(28, y + 48, W - 56, 40), [UIFont systemFontOfSize:13], RED, NSTextAlignmentCenter);
    [_offView addSubview:_offError];

    // ================= AN =================
    _onView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    [_scroll addSubview:_onView];

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    dot.backgroundColor = GRN; dot.layer.cornerRadius = 5;
    UILabel *title = label(CGRectZero, [UIFont boldSystemFontOfSize:21], INK, NSTextAlignmentLeft);
    title.text = L(@"Sharing is on");
    [title sizeToFit];
    CGFloat tw = 10 + 8 + title.bounds.size.width, tx = (W - tw) / 2;
    dot.frame = CGRectMake(tx, 24, 10, 10);
    title.frame = CGRectMake(tx + 18, 14, title.bounds.size.width, 28);
    [_onView addSubview:dot]; [_onView addSubview:title];

    _extras = [UIButton buttonWithType:UIButtonTypeCustom];
    _extras.frame = CGRectMake(W - 64, 12, 60, 32);
    _extras.titleLabel.font = [UIFont systemFontOfSize:14];
    [_extras setTitle:L(@"Extras") forState:UIControlStateNormal];
    [_extras setTitleColor:ACC forState:UIControlStateNormal];
    [_extras addTarget:self action:@selector(openExtras) forControlEvents:UIControlEventTouchUpInside];
    [_onView addSubview:_extras];

    _status = label(CGRectMake(16, 42, W - 32, 18), [UIFont systemFontOfSize:13], MUT, NSTextAlignmentCenter);
    [_onView addSubview:_status];
    _shellNote = label(CGRectMake(16, 59, W - 32, 15), [UIFont systemFontOfSize:12], ORG, NSTextAlignmentCenter);
    [_onView addSubview:_shellNote];

    // kein WLAN
    _noWifi = card(CGRectMake(16, 84, W - 32, 90));
    UILabel *nw = label(CGRectMake(14, 14, W - 60, 0), [UIFont systemFontOfSize:15], RED, NSTextAlignmentCenter);
    fitLabel(nw, L(@"The iPod is not connected to Wi-Fi. Connect it under Settings › Wi-Fi."));
    [_noWifi addSubview:nw];
    [_onView addSubview:_noWifi];

    // Schritte
    _steps = [[UIView alloc] initWithFrame:CGRectMake(0, 76, W, 346)];
    [_onView addSubview:_steps];
    UIView *c1 = card(CGRectMake(16, 0, W - 32, 182));
    [c1 addSubview:badge(CGPointMake(12, 12), @"1")];
    UILabel *s1 = label(CGRectMake(44, 12, W - 32 - 52, 24), [UIFont boldSystemFontOfSize:15], INK, NSTextAlignmentLeft);
    s1.text = L(@"Scan the code with your phone camera");
    s1.adjustsFontSizeToFitWidth = YES; s1.minimumScaleFactor = 0.8;
    [c1 addSubview:s1];
    _qr = [[UIImageView alloc] initWithFrame:CGRectMake((W - 32 - 132) / 2, 42, 132, 132)];
    _qr.layer.magnificationFilter = kCAFilterNearest;
    _qr.contentMode = UIViewContentModeScaleAspectFit;
    [c1 addSubview:_qr];
    [_steps addSubview:c1];

    UIView *c2 = card(CGRectMake(16, 190, W - 32, 80));
    [c2 addSubview:badge(CGPointMake(12, 12), @"2")];
    UILabel *s2 = label(CGRectMake(44, 12, W - 32 - 52, 24), [UIFont boldSystemFontOfSize:15], INK, NSTextAlignmentLeft);
    s2.text = L(@"Enter this number");
    [c2 addSubview:s2];
    _pin = label(CGRectMake(0, 36, W - 32, 40), [UIFont boldSystemFontOfSize:36], INK, NSTextAlignmentCenter);
    [c2 addSubview:_pin];
    [_steps addSubview:c2];

    _addrBox = card(CGRectMake(16, 278, W - 32, 68));
    UILabel *ah = label(CGRectMake(12, 8, W - 56, 16), [UIFont systemFontOfSize:12], MUT, NSTextAlignmentCenter);
    ah.text = L(@"On a computer? Type into the browser:");
    [_addrBox addSubview:ah];
    _host = label(CGRectMake(8, 24, W - 48, 24), [UIFont boldSystemFontOfSize:20], ACC, NSTextAlignmentCenter);
    _host.adjustsFontSizeToFitWidth = YES; _host.minimumScaleFactor = 0.6;
    [_addrBox addSubview:_host];
    _ip = label(CGRectMake(8, 48, W - 48, 14), [UIFont systemFontOfSize:12], MUT, NSTextAlignmentCenter);
    [_addrBox addSubview:_ip];
    [_steps addSubview:_addrBox];

    _stopBtn = bigButton(CGRectZero, CARD, RED, self, @selector(stopServer));
    _stopBtn.layer.borderWidth = 0.5; _stopBtn.layer.borderColor = LINE.CGColor;
    [_stopBtn setTitle:L(@"Stop sharing") forState:UIControlStateNormal];
    [self pressEffect:_stopBtn];
    [_onView addSubview:_stopBtn];

    [self refreshUI];
}

- (void)pressEffect:(UIButton *)b {
    [b addTarget:self action:@selector(pressDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [b addTarget:self action:@selector(pressUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                                                                 UIControlEventTouchDragExit | UIControlEventTouchCancel];
}
- (void)pressDown:(UIButton *)b { b.alpha = 0.6; }
- (void)pressUp:(UIButton *)b { b.alpha = 1.0; }

#pragma mark - Server

- (void)startTapped { [self startServer]; }

- (void)startServer {
    if (_server.running) return;
    NSString *err = nil;
    BOOL ok = NO;
    for (uint16_t p = FM_PORT; p < FM_PORT + 5 && !ok; p++) {   // 8080 belegt -> nächsten freien nehmen
        err = nil;
        ok = [_server startOnPort:p error:&err];
    }
    if (ok) {
        _lastError = nil;
        [UIApplication sharedApplication].idleTimerDisabled = YES;   // Display bleibt an
        [_timer invalidate];
        _timer = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(refreshUI) userInfo:nil repeats:YES];
    } else {
        _lastError = err ?: L(@"Sharing could not be started");
    }
    [self refreshUI];
}

- (void)stopServer {
    [_timer invalidate]; _timer = nil;
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [_server stop];
    [self refreshUI];
}

- (void)openExtras {
    _shellVC = [[FMShellController alloc] initWithServer:_server];
    [self presentViewController:_shellVC animated:YES completion:nil];
}

#pragma mark - Rückfrage am iPod

- (void)ask:(NSString *)title message:(NSString *)msg ok:(NSString *)ok done:(void (^)(BOOL))done {
    [self cancelAsk];
    _askDone = [done copy];
    _ask = [[UIAlertView alloc] initWithTitle:title message:msg delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:ok, nil];
    [_ask show];
}

- (void)cancelAsk {
    void (^d)(BOOL) = _askDone;
    _askDone = nil;
    [_ask dismissWithClickedButtonIndex:_ask.cancelButtonIndex animated:YES];
    _ask = nil;
    if (d) d(NO);
}

- (void)alertView:(UIAlertView *)a clickedButtonAtIndex:(NSInteger)i {
    if (a != _ask) return;
    void (^d)(BOOL) = _askDone;
    _askDone = nil; _ask = nil;
    if (d) d(i != a.cancelButtonIndex);
}

#pragma mark - Anzeige

- (void)layoutOn {
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    _onView.frame = CGRectMake(0, 0, W, H);
    _stopBtn.frame = CGRectMake(16, H - 50, W - 32, 42);
    _scroll.contentSize = CGSizeMake(W, H);
}

- (void)refreshUI {
    if (!_scroll) return;
    BOOL on = _server.running;
    _offView.hidden = on; _onView.hidden = !on;
    [_shellVC refresh];

    if (!on) {
        NSString *ip = [FMServer wifiAddress];
        _offHint.text = ip ? L(@"Phone or computer must be on the same Wi-Fi as this iPod.")
                           : L(@"The iPod is not connected to Wi-Fi. Connect it under Settings › Wi-Fi.");
        _offHint.textColor = ip ? MUT : RED;
        _offHint.numberOfLines = 0;
        _offError.text = _lastError; _offError.numberOfLines = 0;
        _scroll.contentSize = self.view.bounds.size;
        return;
    }

    NSString *ip = [FMServer wifiAddress];
    _noWifi.hidden = ip != nil;
    _steps.hidden = ip == nil;
    if (ip) {
        NSString *addr = [NSString stringWithFormat:@"http://%@:%d", ip, _server.port];
        // QR mit PIN im #-Teil: der Browser schickt ihn nie an den Server, die Seite meldet sich damit selbst an.
        // Im QR steht die IP: Android-Handys lösen .local-Namen oft nicht auf.
        NSString *qrText = [NSString stringWithFormat:@"%@/#pin=%@", addr, _server.pin];
        if (![qrText isEqualToString:_shownQR]) { _shownQR = qrText; _qr.image = qrImage(qrText); }
        NSMutableAttributedString *p = [[NSMutableAttributedString alloc] initWithString:_server.pin ?: @""];
        [p addAttribute:NSKernAttributeName value:@12 range:NSMakeRange(0, p.length)];
        _pin.attributedText = p;
        NSString *bonjour = [FMServer bonjourName];
        _host.text = [addr substringFromIndex:7];         // IP groß: klappt in jedem Browser
        _ip.text = bonjour ? LF(@"or %@", [NSString stringWithFormat:@"%@:%d", bonjour, _server.port]) : @"";
    } else _shownQR = nil;

    NSUInteger n = _server.sessionCount;
    _status.text = n == 0 ? L(@"No device connected yet") : n == 1 ? L(@"1 device connected ✓") : LF(@"%lu devices connected ✓", (unsigned long)n);
    _status.textColor = n ? GRN : MUT;
    _shellNote.text = _server.shellInUse ? L(@"Command line in use") : _server.shellEnabled ? L(@"Command line is allowed") : @"";
    [self layoutOn];
}
@end

#pragma mark - App

@interface FMAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation FMAppDelegate {
    FMViewController *_vc;
    UIBackgroundTaskIdentifier _bg;
}
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    _bg = UIBackgroundTaskInvalid;
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _vc = [[FMViewController alloc] init];
    self.window.rootViewController = _vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)endBackgroundTask {
    if (_bg != UIBackgroundTaskInvalid) { [[UIApplication sharedApplication] endBackgroundTask:_bg]; _bg = UIBackgroundTaskInvalid; }
}

// Freigabe startet nur per Knopf; zurück in der App nur die Anzeige auffrischen (WLAN kann sich geändert haben)
- (void)applicationDidBecomeActive:(UIApplication *)app {
    [self endBackgroundTask];
    [_vc refreshUI];
}

// Verlassen / Sperren: iOS 6 gewährt noch ~10 Minuten, dann Server sauber stoppen
- (void)applicationDidEnterBackground:(UIApplication *)app {
    if (!_vc.running) return;
    __weak FMAppDelegate *ws = self;
    _bg = [app beginBackgroundTaskWithExpirationHandler:^{
        FMAppDelegate *s = ws;
        [s->_vc stopServer];
        [s endBackgroundTask];
    }];
    if (_bg == UIBackgroundTaskInvalid) [_vc stopServer];
}

- (void)applicationWillTerminate:(UIApplication *)app { [_vc stopServer]; }
@end
