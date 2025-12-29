/**
 * HIAHCarPlayController.m - CarPlay Interface Controller
 */

#import "HIAHCarPlayController.h"
#import "HIAHKernel.h"
#import "HIAHProcess.h"
#import "HIAHFloatingWindow.h"
#import "HIAHAppLauncher.h"

@interface HIAHCarPlayController ()
@property (nonatomic, strong) CPListTemplate *mainTemplate;
@property (nonatomic, assign) BOOL connected;
@end

@implementation HIAHCarPlayController

+ (instancetype)sharedController {
    static HIAHCarPlayController *c = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ c = [[self alloc] init]; });
    return c;
}

- (BOOL)isCarPlayConnected { return _connected && self.interfaceController; }

- (void)application:(UIApplication *)app didConnectCarInterfaceController:(CPInterfaceController *)ic toWindow:(CPWindow *)w API_AVAILABLE(ios(12.0)) {
    self.interfaceController = ic; self.carWindow = w; self.connected = YES;
    [self setupCarPlayInterface];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HIAHCarPlayDidConnect" object:self];
}

- (void)application:(UIApplication *)app didDisconnectCarInterfaceController:(CPInterfaceController *)ic fromWindow:(CPWindow *)w API_AVAILABLE(ios(12.0)) {
    self.interfaceController = nil; self.carWindow = nil; self.connected = NO; self.mainTemplate = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HIAHCarPlayDidDisconnect" object:self];
}

- (void)setupCarPlayInterface {
    if (!self.interfaceController) return;
    self.connected = YES;
    
    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    
    CPListItem *procs = [[CPListItem alloc] initWithText:@"Running Processes" 
                                              detailText:[NSString stringWithFormat:@"%lu active", (unsigned long)[self processCount]]
                                                           image:nil];
    procs.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [self showProcessList]; c(); };
    [items addObject:procs];
    
    CPListItem *launcher = [[CPListItem alloc] initWithText:@"App Launcher" detailText:@"Launch applications" image:nil];
    launcher.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [self showAppLauncher]; c(); };
    [items addObject:launcher];
    
    CPListItem *wins = [[CPListItem alloc] initWithText:@"Window Manager"
                                             detailText:[NSString stringWithFormat:@"%lu windows", (unsigned long)[self windowCount]]
                                                         image:nil];
    wins.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [self showWindowManager]; c(); };
    [items addObject:wins];
    
    self.mainTemplate = [[CPListTemplate alloc] initWithTitle:@"HIAH Desktop" sections:@[[[CPListSection alloc] initWithItems:items header:nil sectionIndexTitle:nil]]];
    if (@available(iOS 14.0, *)) {
        [self.interfaceController setRootTemplate:self.mainTemplate animated:YES completion:nil];
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.interfaceController setRootTemplate:self.mainTemplate animated:YES];
        #pragma clang diagnostic pop
    }
}

- (NSUInteger)processCount { return [[HIAHKernel sharedKernel] allProcesses].count; }

- (NSUInteger)windowCount {
    id d = self.mainDesktop ?: [self getMainDesktop];
    return d && [d respondsToSelector:@selector(windows)] ? [[d valueForKey:@"windows"] count] : 0;
}

- (id)getMainDesktop {
    id ad = [UIApplication sharedApplication].delegate;
    SEL sel = NSSelectorFromString(@"desktopsByScreen");
    if (ad && [ad respondsToSelector:sel]) {
        NSDictionary *ds = [ad valueForKey:@"desktopsByScreen"];
        if (ds) {
            // Get main screen from connected scenes (iOS 26.0+)
            UIScreen *mainScreen = nil;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    if (ws.screen) {
                        mainScreen = ws.screen;
                        break;
                    }
                }
            }
            if (!mainScreen) {
                mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
            }
            return ds[[NSValue valueWithNonretainedObject:mainScreen]];
        }
    }
    return nil;
}

- (void)showProcessList {
    if (!self.interfaceController) return;
    
    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    for (HIAHProcess *p in [[HIAHKernel sharedKernel] allProcesses]) {
        NSString *name = [p.executablePath lastPathComponent] ?: @"Unknown";
        CPListItem *item = [[CPListItem alloc] initWithText:name
                                                 detailText:[NSString stringWithFormat:@"PID: %d • %@", p.pid, p.isExited ? @"Exited" : @"Running"]
                                                     image:nil];
        item.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [self showProcessDetails:p]; c(); };
        [items addObject:item];
    }
    if (!items.count) [items addObject:[[CPListItem alloc] initWithText:@"No processes running" detailText:nil image:nil]];
    
    CPListTemplate *t = [[CPListTemplate alloc] initWithTitle:@"Running Processes" sections:@[[[CPListSection alloc] initWithItems:items header:nil sectionIndexTitle:nil]]];
    [self.interfaceController pushTemplate:t animated:YES completion:nil];
}

- (void)showProcessDetails:(HIAHProcess *)p {
    if (!self.interfaceController) return;
    NSString *name = [p.executablePath lastPathComponent] ?: @"Unknown";
    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    [items addObject:[[CPListItem alloc] initWithText:@"PID" detailText:[NSString stringWithFormat:@"%d", p.pid] image:nil]];
    [items addObject:[[CPListItem alloc] initWithText:@"Path" detailText:p.executablePath image:nil]];
    [items addObject:[[CPListItem alloc] initWithText:@"Status" detailText:p.isExited ? @"Exited" : @"Running" image:nil]];
    
    CPListTemplate *t = [[CPListTemplate alloc] initWithTitle:name sections:@[[[CPListSection alloc] initWithItems:items header:nil sectionIndexTitle:nil]]];
    [self.interfaceController pushTemplate:t animated:YES completion:nil];
}

- (void)showAppLauncher {
    if (!self.interfaceController) return;
    
    NSArray<NSDictionary *> *apps = @[
        @{@"name": @"HIAHTop", @"bid": @"com.aspauldingcode.HIAHTop"},
        @{@"name": @"Calculator", @"bid": @"com.aspauldingcode.Calculator"},
        @{@"name": @"Notes", @"bid": @"com.aspauldingcode.Notes"},
        @{@"name": @"Weather", @"bid": @"com.aspauldingcode.Weather"},
        @{@"name": @"Timer", @"bid": @"com.aspauldingcode.Timer"},
        @{@"name": @"Canvas", @"bid": @"com.aspauldingcode.Canvas"},
    ];
    
    NSMutableArray<CPGridButton *> *btns = [NSMutableArray array];
    for (NSDictionary *a in apps) {
        NSString *name = a[@"name"];
        NSString *bid = a[@"bid"];
        if (!name || !bid) continue; // Skip invalid entries
        // Create button with empty image array (CarPlay API requires non-null but can be empty)
        CPGridButton *b = [[CPGridButton alloc] initWithTitleVariants:@[name] image:[UIImage new] handler:^(CPGridButton *gb) {
            [self launchApp:name bundleID:bid];
        }];
        [btns addObject:b];
    }
    
    CPGridTemplate *t = [[CPGridTemplate alloc] initWithTitle:@"App Launcher" gridButtons:btns];
    [self.interfaceController pushTemplate:t animated:YES completion:nil];
}

- (void)launchApp:(NSString *)name bundleID:(NSString *)bid {
    if (!self.mainDesktop) self.mainDesktop = [self getMainDesktop];
    id d = self.mainDesktop;
    if (!d) return;
    
    SEL sel = @selector(appLauncher:didSelectApp:bundleID:);
    if ([d respondsToSelector:sel]) {
        HIAHAppLauncher *mock = [[HIAHAppLauncher alloc] init];
        NSMethodSignature *sig = [d methodSignatureForSelector:sel];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:d]; [inv setSelector:sel];
            [inv setArgument:&mock atIndex:2]; [inv setArgument:&name atIndex:3]; [inv setArgument:&bid atIndex:4];
            [inv invoke];
        }
    }
}

- (void)showWindowManager {
    if (!self.interfaceController) return;
    if (!self.mainDesktop) self.mainDesktop = [self getMainDesktop];
    
    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    id d = self.mainDesktop;
    if (d && [d respondsToSelector:@selector(windows)]) {
        for (HIAHFloatingWindow *w in [[d valueForKey:@"windows"] allValues]) {
            CPListItem *item = [[CPListItem alloc] initWithText:w.windowTitle
                                                     detailText:[NSString stringWithFormat:@"Window ID: %ld", (long)w.windowID]
                                                                image:nil];
            item.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [self showWindowActions:w]; c(); };
            [items addObject:item];
        }
    }
    if (!items.count) [items addObject:[[CPListItem alloc] initWithText:@"No windows open" detailText:nil image:nil]];
    
    CPListTemplate *t = [[CPListTemplate alloc] initWithTitle:@"Window Manager" sections:@[[[CPListSection alloc] initWithItems:items header:nil sectionIndexTitle:nil]]];
    [self.interfaceController pushTemplate:t animated:YES completion:nil];
}

- (void)showWindowActions:(HIAHFloatingWindow *)w {
    if (!self.interfaceController) return;
    
    NSMutableArray<CPListItem *> *items = [NSMutableArray array];
    
    if (w.isMinimized) {
        CPListItem *i = [[CPListItem alloc] initWithText:@"Restore Window" detailText:nil image:nil];
        i.handler = ^(id<CPSelectableListItem> it, dispatch_block_t c) { [w restore]; c(); };
        [items addObject:i];
    } else {
        CPListItem *i = [[CPListItem alloc] initWithText:@"Minimize Window" detailText:nil image:nil];
        i.handler = ^(id<CPSelectableListItem> it, dispatch_block_t c) { [w minimize]; c(); };
        [items addObject:i];
    }
    
    CPListItem *max = [[CPListItem alloc] initWithText:w.isMaximized ? @"Restore Size" : @"Maximize Window" detailText:nil image:nil];
    max.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [w toggleMaximize]; c(); };
    [items addObject:max];
    
    CPListItem *roll = [[CPListItem alloc] initWithText:w.isRolledUp ? @"Unroll Window" : @"Roll Up Window" detailText:nil image:nil];
    roll.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [w toggleRollup]; c(); };
    [items addObject:roll];
    
    CPListItem *close = [[CPListItem alloc] initWithText:@"Close Window" detailText:nil image:nil];
    close.handler = ^(id<CPSelectableListItem> i, dispatch_block_t c) { [w close]; c(); };
    [items addObject:close];
    
    CPListTemplate *t = [[CPListTemplate alloc] initWithTitle:w.windowTitle sections:@[[[CPListSection alloc] initWithItems:items header:nil sectionIndexTitle:nil]]];
    [self.interfaceController pushTemplate:t animated:YES completion:nil];
}

// Implement required methods from header
- (void)updateProcessList {
    // Refresh the process list display if showing
    if (self.mainTemplate && self.interfaceController) {
        [self setupCarPlayInterface];
    }
}

- (void)launchAppWithBundleID:(NSString *)bundleID name:(NSString *)name {
    if (!bundleID || !name) return;
    [self launchApp:name bundleID:bundleID];
}

@end
