/**
 * HIAHAppLauncher.m
 * App launcher dock - UI component controlled by HIAHStateMachine
 */

#import "HIAHAppLauncher.h"
#import "../HIAHDesktop/HIAHFilesystem.h"
#import <sys/event.h>
#import <sys/time.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

static const CGFloat kDockHeight = 80.0;
static const CGFloat kPillHeight = 32.0;
static const CGFloat kPillWidth = 100.0;
static const CGFloat kIconSize = 56.0;
static const CGFloat kIconSpacing = 12.0;
static const CGFloat kDrawerHeight = 320.0;

@interface HIAHAppLauncher ()
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) UIView *dockBar;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UIView *drawer;
@property (nonatomic, strong) UICollectionView *grid;
@property (nonatomic, strong) UIScrollView *minimizedScroll;
@property (nonatomic, strong) UIStackView *minimizedStack;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *apps;
@property (nonatomic, strong) UILabel *pillLabel;
@property (nonatomic, strong) UITapGestureRecognizer *pillTap;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *drawerHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *drawerBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *dockBarScrollTrailingConstraint;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *dockBarConstraints;
@property (nonatomic, assign) HIAHDockState currentVisualState;
@property (nonatomic, assign) int kqueueFD;
@property (nonatomic, assign) int directoryFD;
@property (nonatomic, strong) dispatch_source_t fileMonitorSource;
@end

@implementation HIAHAppLauncher

#pragma mark - Init

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _minimizedWindows = [NSMutableArray array];
        _currentVisualState = HIAHDockStateNormal;
        _kqueueFD = -1;
        _directoryFD = -1;
        [self setupApps];
        [self setupUI];
    }
    return self;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview) {
        // Ensure dock starts in normal state (not pill)
        _currentVisualState = HIAHDockStateNormal;
        [self applyDockState:HIAHDockStateNormal animated:NO];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.superview && !self.layer.animationKeys.count) {
        [self updateFrameForState:_currentVisualState];
    }
    
    // Update shadow path when blur view bounds change
    if (self.blur && !CGRectIsEmpty(self.blur.bounds)) {
        self.layer.shadowPath = [[UIBezierPath bezierPathWithRoundedRect:self.blur.frame 
                                                            cornerRadius:self.blur.layer.cornerRadius] CGPath];
    }
}

+ (NSString *)applicationsPath {
    // Use App Group shared container via HIAHFilesystem
    return [[HIAHFilesystem shared] appsPath];
}

+ (NSArray<NSDictionary *> *)scanInstalledApps {
    NSString *appsPath = [self applicationsPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Ensure Applications folder exists
    if (![fm fileExistsAtPath:appsPath]) {
        [fm createDirectoryAtPath:appsPath withIntermediateDirectories:YES attributes:nil error:nil];
        NSLog(@"[Launcher] Created Applications folder: %@", appsPath);
    }
    
    NSMutableArray *apps = [NSMutableArray array];
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:appsPath error:nil] ?: @[];
    
    NSLog(@"[Launcher] Scanning: %@", appsPath);
    NSLog(@"[Launcher] Found: %lu items", (unsigned long)contents.count);
    
    for (NSString *item in contents) {
        // Support both .app bundles and folders (for Files app compatibility)
        BOOL isApp = [item hasSuffix:@".app"];
        if (!isApp) {
            // Check if it's a folder that should be treated as an app
            NSString *itemPath = [appsPath stringByAppendingPathComponent:item];
            BOOL isDir;
            if ([fm fileExistsAtPath:itemPath isDirectory:&isDir] && isDir) {
                // Check if it has Info.plist (making it an app)
                NSString *plist = [itemPath stringByAppendingPathComponent:@"Info.plist"];
                isApp = [fm fileExistsAtPath:plist];
            }
        }
        
        if (!isApp) continue;
        
        NSString *appPath = [appsPath stringByAppendingPathComponent:item];
        NSString *infoPlistPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
        
        if (info) {
            NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: [item stringByReplacingOccurrencesOfString:@".app" withString:@""];
            NSString *bundleID = info[@"CFBundleIdentifier"] ?: @"unknown";
            
            // Determine icon based on app name or bundle ID
            NSString *icon = @"app.fill";
            UIColor *color = [UIColor colorWithHue:(apps.count * 0.1) saturation:0.6 brightness:0.8 alpha:1.0];
            
            if ([bundleID isEqualToString:@"com.aspauldingcode.HIAHTop"]) {
                icon = @"chart.bar.fill";
                color = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:1.0];
            }
            
            [apps addObject:@{
                @"name": name,
                @"bundleID": bundleID,
                @"icon": icon,
                @"color": color,
                @"path": appPath
            }];
            
            NSLog(@"[Launcher] Found app: %@ (%@) at %@", name, bundleID, appPath);
        }
    }
    
    if (apps.count == 0) {
        NSLog(@"[Launcher] No apps installed - Applications folder is empty");
        NSLog(@"[Launcher] Install apps via Files app or HIAH Installer");
    }
    
    return apps;
}

- (void)setupApps {
    self.apps = [[[self class] scanInstalledApps] mutableCopy];
    [self startFileMonitoring];
}

- (void)startFileMonitoring {
    // Stop existing monitoring if any
    [self stopFileMonitoring];
    
    NSString *appsPath = [[self class] applicationsPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // Ensure directory exists
    if (![fm fileExistsAtPath:appsPath]) {
        [fm createDirectoryAtPath:appsPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // Open directory for monitoring
    int dirFD = open([appsPath UTF8String], O_RDONLY);
    if (dirFD < 0) {
        NSLog(@"[Launcher] Failed to open Applications directory for monitoring: %s", strerror(errno));
        return;
    }
    
    self.directoryFD = dirFD;
    
    // Create kqueue
    int kq = kqueue();
    if (kq < 0) {
        NSLog(@"[Launcher] Failed to create kqueue: %s", strerror(errno));
        close(dirFD);
        self.directoryFD = -1;
        return;
    }
    
    self.kqueueFD = kq;
    
    // Set up event filter for file system events
    struct kevent event;
    EV_SET(&event, dirFD, EVFILT_VNODE, EV_ADD | EV_CLEAR | EV_ENABLE,
           NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_RENAME | NOTE_REVOKE,
           0, NULL);
    
    if (kevent(kq, &event, 1, NULL, 0, NULL) < 0) {
        NSLog(@"[Launcher] Failed to register kqueue event: %s", strerror(errno));
        close(kq);
        close(dirFD);
        self.kqueueFD = -1;
        self.directoryFD = -1;
        return;
    }
    
    // Create dispatch source for kqueue
    dispatch_queue_t monitorQueue = dispatch_queue_create("com.aspauldingcode.HIAHDesktop.appMonitor", DISPATCH_QUEUE_SERIAL);
    self.fileMonitorSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, kq, 0, monitorQueue);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.fileMonitorSource, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.kqueueFD < 0) return;
        
        // Read events from kqueue
        struct kevent event;
        struct timespec timeout = {0, 0};
        int eventCount = kevent(strongSelf.kqueueFD, NULL, 0, &event, 1, &timeout);
        
        if (eventCount > 0) {
            NSLog(@"[Launcher] 📁 File system change detected in Applications directory");
            
            // Debounce: wait a bit for file operations to complete
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf refreshApps];
                }
            });
        }
    });
    
    dispatch_source_set_cancel_handler(self.fileMonitorSource, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            if (strongSelf.kqueueFD >= 0) {
                close(strongSelf.kqueueFD);
                strongSelf.kqueueFD = -1;
            }
            if (strongSelf.directoryFD >= 0) {
                close(strongSelf.directoryFD);
                strongSelf.directoryFD = -1;
            }
        }
    });
    
    dispatch_resume(self.fileMonitorSource);
    NSLog(@"[Launcher] ✅ Started file monitoring for: %@", appsPath);
}

- (void)stopFileMonitoring {
    if (self.fileMonitorSource) {
        dispatch_source_cancel(self.fileMonitorSource);
        self.fileMonitorSource = nil;
    }
    if (self.kqueueFD >= 0) {
        close(self.kqueueFD);
        self.kqueueFD = -1;
    }
    if (self.directoryFD >= 0) {
        close(self.directoryFD);
        self.directoryFD = -1;
    }
}

- (void)dealloc {
    [self stopFileMonitoring];
}

- (void)refreshApps {
    [self setupApps];
    [self.grid reloadData];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.clipsToBounds = NO;  // Don't clip - let shadows show!
    self.layer.masksToBounds = NO;  // Important for shadow visibility
    self.userInteractionEnabled = YES;
    
    self.blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    self.blur.layer.cornerRadius = 24;
    self.blur.clipsToBounds = YES;  // Must clip to show rounded corners
    self.blur.userInteractionEnabled = YES;
    self.blur.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.blur];
    
    // Drop shadow on parent container (self) since blur clips
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, -4);  // Shadow upward
    self.layer.shadowRadius = 16;
    self.layer.shadowOpacity = 0.6;
    self.layer.shadowPath = [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 400, 100) cornerRadius:24] CGPath];
    
    self.heightConstraint = [self.blur.heightAnchor constraintEqualToConstant:kDockHeight];
    [NSLayoutConstraint activateConstraints:@[
        [self.blur.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.blur.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.blur.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        self.heightConstraint
    ]];
    
    [self setupDockBar];  // Setup dockBar first so drawer can reference it
    [self setupDrawer];
    [self setupPill];
}

- (void)setupPill {
    self.pillLabel = [[UILabel alloc] init];
    self.pillLabel.text = @"HIAH Desktop";
    self.pillLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.pillLabel.textColor = [UIColor whiteColor];
    self.pillLabel.textAlignment = NSTextAlignmentCenter;
    self.pillLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillLabel.alpha = 0;
    self.pillLabel.hidden = YES;
    [self.blur.contentView addSubview:self.pillLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.pillLabel.centerXAnchor constraintEqualToAnchor:self.blur.contentView.centerXAnchor],
        [self.pillLabel.centerYAnchor constraintEqualToAnchor:self.blur.contentView.centerYAnchor],
    ]];
    
    self.pillTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(pillTapped)];
    self.pillTap.enabled = NO;
    [self.blur addGestureRecognizer:self.pillTap];
}

- (void)setupDrawer {
    self.drawer = [[UIView alloc] init];
    self.drawer.translatesAutoresizingMaskIntoConstraints = NO;
    self.drawer.alpha = 0;
    self.drawer.hidden = YES;
    self.drawer.userInteractionEnabled = YES;
    [self.blur.contentView addSubview:self.drawer];
    
    UILabel *title = [[UILabel alloc] init];
    title.text = @"Apps";
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    title.textColor = [UIColor whiteColor];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.drawer addSubview:title];
    
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(kIconSize + 20, kIconSize + 30);
    layout.minimumInteritemSpacing = kIconSpacing;
    layout.minimumLineSpacing = kIconSpacing;
    layout.sectionInset = UIEdgeInsetsMake(10, 16, 10, 16);
    
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.grid.backgroundColor = [UIColor clearColor];
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    self.grid.userInteractionEnabled = YES;
    self.grid.allowsSelection = YES;
    [self.grid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"Cell"];
    [self.drawer addSubview:self.grid];
    
    // Constrain drawer to fill space above dockBar
    // Store bottom constraint so we can deactivate it when drawer is hidden
    self.drawerBottomConstraint = [self.drawer.bottomAnchor constraintEqualToAnchor:self.dockBar.topAnchor];
    
    // Store drawer height constraint so we can set it to 0 when drawer is hidden
    self.drawerHeightConstraint = [self.drawer.heightAnchor constraintEqualToConstant:0];
    self.drawerHeightConstraint.priority = UILayoutPriorityDefaultHigh;  // Lower priority, can be broken
    
    NSLayoutConstraint *titleTop = [title.topAnchor constraintEqualToAnchor:self.drawer.topAnchor constant:16];
    NSLayoutConstraint *gridTop = [self.grid.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10];
    NSLayoutConstraint *gridBottom = [self.grid.bottomAnchor constraintEqualToAnchor:self.drawer.bottomAnchor];
    
    // Make internal constraints lower priority so they can break when drawer has 0 height
    titleTop.priority = UILayoutPriorityDefaultHigh - 1;
    gridTop.priority = UILayoutPriorityDefaultHigh - 1;
    gridBottom.priority = UILayoutPriorityDefaultHigh - 1;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.drawer.topAnchor constraintEqualToAnchor:self.blur.contentView.topAnchor],
        [self.drawer.leadingAnchor constraintEqualToAnchor:self.blur.contentView.leadingAnchor],
        [self.drawer.trailingAnchor constraintEqualToAnchor:self.blur.contentView.trailingAnchor],
        self.drawerBottomConstraint,  // Active when drawer is shown
        self.drawerHeightConstraint,  // Active when drawer is hidden (height = 0)
        titleTop,
        [title.centerXAnchor constraintEqualToAnchor:self.drawer.centerXAnchor],
        gridTop,
        [self.grid.leadingAnchor constraintEqualToAnchor:self.drawer.leadingAnchor],
        [self.grid.trailingAnchor constraintEqualToAnchor:self.drawer.trailingAnchor],
        gridBottom,
    ]];
    
    // Initially, drawer is hidden, so activate height constraint and deactivate bottom constraint
    self.drawerBottomConstraint.active = NO;
    self.drawerHeightConstraint.active = YES;
}

- (void)setupDockBar {
    self.dockBar = [[UIView alloc] init];
    self.dockBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.dockBar.userInteractionEnabled = YES;
    [self.blur.contentView addSubview:self.dockBar];
    
    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *bg = [[UIView alloc] init];
    bg.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.8];
    bg.layer.cornerRadius = 14;
    bg.userInteractionEnabled = NO;
    bg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.toggleBtn addSubview:bg];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.grid.2x2.fill"]];
    icon.tintColor = [UIColor whiteColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tag = 100;
    [self.toggleBtn addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [bg.topAnchor constraintEqualToAnchor:self.toggleBtn.topAnchor],
        [bg.leadingAnchor constraintEqualToAnchor:self.toggleBtn.leadingAnchor],
        [bg.trailingAnchor constraintEqualToAnchor:self.toggleBtn.trailingAnchor],
        [bg.bottomAnchor constraintEqualToAnchor:self.toggleBtn.bottomAnchor],
        [icon.centerXAnchor constraintEqualToAnchor:self.toggleBtn.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:self.toggleBtn.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:28],
        [icon.heightAnchor constraintEqualToConstant:28],
    ]];
    [self.toggleBtn addTarget:self action:@selector(toggleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.dockBar addSubview:self.toggleBtn];
    
    UIView *sep = [[UIView alloc] init];
    sep.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.3];
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dockBar addSubview:sep];
    
    self.minimizedScroll = [[UIScrollView alloc] init];
    self.minimizedScroll.showsHorizontalScrollIndicator = NO;
    self.minimizedScroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dockBar addSubview:self.minimizedScroll];
    
    self.minimizedStack = [[UIStackView alloc] init];
    self.minimizedStack.axis = UILayoutConstraintAxisHorizontal;
    self.minimizedStack.spacing = kIconSpacing;
    self.minimizedStack.alignment = UIStackViewAlignmentCenter;
    self.minimizedStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.minimizedScroll addSubview:self.minimizedStack];
    
    UILabel *placeholder = [[UILabel alloc] init];
    placeholder.text = @"No minimized windows";
    placeholder.font = [UIFont systemFontOfSize:12];
    placeholder.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    placeholder.tag = 200;
    placeholder.translatesAutoresizingMaskIntoConstraints = NO;
    [self.minimizedScroll addSubview:placeholder];
    
    // Store constraint so we can adjust priority when dockBar is hidden
    self.dockBarScrollTrailingConstraint = [self.minimizedScroll.trailingAnchor constraintEqualToAnchor:self.dockBar.trailingAnchor constant:-16];
    self.dockBarScrollTrailingConstraint.priority = UILayoutPriorityDefaultHigh;  // Lower priority - can compress if needed
    
    // Store all dockBar constraints so we can deactivate them when hidden
    self.dockBarConstraints = @[
        [self.dockBar.leadingAnchor constraintEqualToAnchor:self.blur.contentView.leadingAnchor],
        [self.dockBar.trailingAnchor constraintEqualToAnchor:self.blur.contentView.trailingAnchor],
        [self.dockBar.bottomAnchor constraintEqualToAnchor:self.blur.contentView.bottomAnchor],
        [self.dockBar.heightAnchor constraintEqualToConstant:kDockHeight],
        [self.toggleBtn.leadingAnchor constraintEqualToAnchor:self.dockBar.leadingAnchor constant:16],
        [self.toggleBtn.centerYAnchor constraintEqualToAnchor:self.dockBar.centerYAnchor],
        [self.toggleBtn.widthAnchor constraintEqualToConstant:kIconSize],
        [self.toggleBtn.heightAnchor constraintEqualToConstant:kIconSize],
        [sep.leadingAnchor constraintEqualToAnchor:self.toggleBtn.trailingAnchor constant:12],
        [sep.centerYAnchor constraintEqualToAnchor:self.dockBar.centerYAnchor],
        [sep.widthAnchor constraintEqualToConstant:1],
        [sep.heightAnchor constraintEqualToConstant:40],
        [self.minimizedScroll.leadingAnchor constraintEqualToAnchor:sep.trailingAnchor constant:12],
        self.dockBarScrollTrailingConstraint,  // Flexible trailing constraint
        [self.minimizedScroll.topAnchor constraintEqualToAnchor:self.dockBar.topAnchor],
        [self.minimizedScroll.bottomAnchor constraintEqualToAnchor:self.dockBar.bottomAnchor],
        [self.minimizedStack.leadingAnchor constraintEqualToAnchor:self.minimizedScroll.leadingAnchor],
        [self.minimizedStack.trailingAnchor constraintEqualToAnchor:self.minimizedScroll.trailingAnchor],
        [self.minimizedStack.centerYAnchor constraintEqualToAnchor:self.minimizedScroll.centerYAnchor],
        [self.minimizedStack.heightAnchor constraintEqualToConstant:kIconSize],
        [placeholder.centerXAnchor constraintEqualToAnchor:self.minimizedScroll.centerXAnchor],
        [placeholder.centerYAnchor constraintEqualToAnchor:self.minimizedScroll.centerYAnchor],
    ];
    
    [NSLayoutConstraint activateConstraints:self.dockBarConstraints];
}

#pragma mark - State Application (called by state machine)

- (void)applyDockState:(HIAHDockState)state animated:(BOOL)animated {
    _currentVisualState = state;
    
    // Prepare non-animatable changes
    [self prepareForState:state];
    
    void (^apply)(void) = ^{
        [self updateFrameForState:state];
        [self applyVisualState:state];
        [self layoutIfNeeded];
    };
    
    void (^complete)(BOOL) = ^(BOOL done) {
        [self finalizeState:state];
        // Notify state machine that transition is complete
        [[HIAHStateMachine shared] dockTransitionDidComplete];
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:apply completion:complete];
    } else {
        apply();
        complete(YES);
    }
}

- (void)prepareForState:(HIAHDockState)state {
    switch (state) {
        case HIAHDockStateNormal:
        case HIAHDockStateTemporarilyRevealed:
            self.dockBar.hidden = NO;
            self.pillLabel.hidden = YES;
            self.drawer.hidden = YES;
            // Activate dockBar constraints
            [NSLayoutConstraint activateConstraints:self.dockBarConstraints];
            if (self.dockBarScrollTrailingConstraint) {
                self.dockBarScrollTrailingConstraint.priority = UILayoutPriorityRequired;
            }
            break;
        case HIAHDockStateLauncherOpen:
            self.dockBar.hidden = NO;
            self.drawer.hidden = NO;
            self.pillLabel.hidden = YES;
            // Activate dockBar constraints
            [NSLayoutConstraint activateConstraints:self.dockBarConstraints];
            if (self.dockBarScrollTrailingConstraint) {
                self.dockBarScrollTrailingConstraint.priority = UILayoutPriorityRequired;
            }
            break;
        case HIAHDockStatePill:
            self.pillLabel.hidden = NO;
            self.dockBar.hidden = YES;  // Hide dockBar in pill state
            self.drawer.hidden = YES;
            // Deactivate dockBar constraints when hidden to prevent conflicts
            [NSLayoutConstraint deactivateConstraints:self.dockBarConstraints];
            break;
    }
}

- (void)applyVisualState:(HIAHDockState)state {
    UIImageView *icon = [self.toggleBtn viewWithTag:100];
    
    switch (state) {
        case HIAHDockStateNormal:
        case HIAHDockStateTemporarilyRevealed:
            self.heightConstraint.constant = kDockHeight;
            self.drawerHeightConstraint.constant = 0;  // Drawer has 0 height when hidden
            self.drawerHeightConstraint.active = YES;
            self.drawerBottomConstraint.active = NO;  // Deactivate bottom constraint
            self.blur.alpha = 1.0;
            self.blur.layer.cornerRadius = 24;
            self.dockBar.alpha = 1;
            self.drawer.alpha = 0;
            self.pillLabel.alpha = 0;
            self.pillTap.enabled = NO;
            self.grid.hidden = NO;
            icon.transform = CGAffineTransformIdentity;
            break;
        case HIAHDockStateLauncherOpen:
            self.heightConstraint.constant = kDrawerHeight;
            self.drawerHeightConstraint.active = NO;  // Deactivate height constraint
            self.drawerBottomConstraint.active = YES;  // Activate bottom constraint to fill space above dockBar
            self.blur.alpha = 1.0;
            self.blur.layer.cornerRadius = 24;
            self.dockBar.alpha = 1;
            self.drawer.alpha = 1;
            self.pillLabel.alpha = 0;
            self.pillTap.enabled = NO;
            self.grid.userInteractionEnabled = YES;
            self.grid.allowsSelection = YES;
            self.grid.hidden = NO;
            [self.blur.contentView bringSubviewToFront:self.drawer];
            icon.transform = CGAffineTransformMakeRotation(M_PI / 4);
            break;
        case HIAHDockStatePill:
            self.heightConstraint.constant = kPillHeight;
            self.drawerHeightConstraint.constant = 0;  // Drawer has 0 height when hidden
            self.drawerHeightConstraint.active = YES;
            self.drawerBottomConstraint.active = NO;  // Deactivate bottom constraint
            self.blur.alpha = 0.7;
            self.blur.layer.cornerRadius = kPillHeight / 2.0;
            self.dockBar.alpha = 0;
            self.drawer.alpha = 0;
            self.pillLabel.alpha = 1;
            self.pillTap.enabled = YES;
            self.grid.hidden = YES;
            break;
    }
}

- (void)finalizeState:(HIAHDockState)state {
    switch (state) {
        case HIAHDockStateNormal:
        case HIAHDockStateTemporarilyRevealed:
            self.drawer.hidden = YES;
            break;
        case HIAHDockStateLauncherOpen:
            [self.grid.collectionViewLayout invalidateLayout];
            [self.grid reloadData];
            break;
        case HIAHDockStatePill:
            self.dockBar.hidden = YES;
            self.drawer.hidden = YES;
            break;
    }
}

- (void)updateFrameForState:(HIAHDockState)state {
    if (!self.superview) return;
    
    CGRect bounds = self.superview.bounds;
    UIEdgeInsets safeArea = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) safeArea = self.superview.safeAreaInsets;
    
    CGFloat maxWidth = MIN(bounds.size.width - safeArea.left - safeArea.right - 32, 500);
    CGFloat centerX = safeArea.left + (bounds.size.width - safeArea.left - safeArea.right - maxWidth) / 2.0;
    
    switch (state) {
        case HIAHDockStateNormal:
        case HIAHDockStateTemporarilyRevealed:
            self.frame = CGRectMake(centerX, bounds.size.height - safeArea.bottom - kDockHeight - 20, maxWidth, kDockHeight);
            break;
        case HIAHDockStateLauncherOpen:
            self.frame = CGRectMake(centerX, bounds.size.height - safeArea.bottom - kDrawerHeight - 20, maxWidth, kDrawerHeight);
            break;
        case HIAHDockStatePill: {
            CGFloat pillY = (bounds.size.height + (bounds.size.height - safeArea.bottom)) / 2.0 - kPillHeight / 2.0;
            CGFloat pillX = safeArea.left + (bounds.size.width - safeArea.left - safeArea.right - kPillWidth) / 2.0;
            self.frame = CGRectMake(pillX, pillY, kPillWidth, kPillHeight);
            break;
        }
    }
}

#pragma mark - Actions (forward to state machine)

- (void)pillTapped {
    [[HIAHStateMachine shared] dockPillWasTapped];
}

- (void)toggleTapped {
    [[HIAHStateMachine shared] dockToggleWasTapped];
}

#pragma mark - Collection View

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.apps.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"Cell" forIndexPath:ip];
    cell.tag = ip.item;
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];
    for (UIGestureRecognizer *g in cell.gestureRecognizers) [cell removeGestureRecognizer:g];
    
    NSDictionary *app = self.apps[ip.item];
    UIView *bg = [[UIView alloc] initWithFrame:CGRectMake((cell.contentView.bounds.size.width - kIconSize) / 2, 0, kIconSize, kIconSize)];
    bg.backgroundColor = app[@"color"];
    bg.layer.cornerRadius = 14;
    bg.userInteractionEnabled = NO;
    [cell.contentView addSubview:bg];
    
    UIImageView *img = [[UIImageView alloc] initWithFrame:bg.bounds];
    img.image = [UIImage systemImageNamed:app[@"icon"]];
    img.tintColor = [UIColor whiteColor];
    img.contentMode = UIViewContentModeScaleAspectFit;
    [bg addSubview:img];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, kIconSize + 4, cell.contentView.bounds.size.width, 20)];
    lbl.text = app[@"name"];
    lbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    lbl.textColor = [UIColor whiteColor];
    lbl.textAlignment = NSTextAlignmentCenter;
    lbl.adjustsFontSizeToFitWidth = YES;
    [cell.contentView addSubview:lbl];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cellTap:)];
    [cell addGestureRecognizer:tap];
    return cell;
}

- (void)cellTap:(UITapGestureRecognizer *)g {
    NSInteger i = g.view.tag;
    [self collectionView:self.grid didSelectItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    if (ip.item >= self.apps.count) return;
    NSDictionary *app = self.apps[ip.item];
    
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
    [UIView animateWithDuration:0.1 animations:^{ cell.transform = CGAffineTransformMakeScale(0.9, 0.9); } completion:^(BOOL f) {
        [UIView animateWithDuration:0.1 animations:^{ cell.transform = CGAffineTransformIdentity; }];
    }];
    
    // Let state machine handle dock collapse
    HIAHStateMachine *sm = [HIAHStateMachine shared];
    [sm setDockState:sm.windowsOverlappingDock ? HIAHDockStatePill : HIAHDockStateNormal animated:YES];
    
    if ([self.delegate respondsToSelector:@selector(appLauncher:didSelectApp:bundleID:)]) {
        [self.delegate appLauncher:self didSelectApp:app[@"name"] bundleID:app[@"bundleID"]];
    }
}

- (NSArray<NSDictionary *> *)availableApps { return [self.apps copy]; }

#pragma mark - Minimized Windows

- (void)addMinimizedWindow:(NSInteger)wid title:(NSString *)title snapshot:(UIImage *)snap {
    [self.minimizedWindows addObject:@{@"windowID": @(wid), @"title": title ?: @"Window", @"snapshot": snap ?: [NSNull null]}];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = wid;
    UIView *bg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kIconSize, kIconSize)];
    bg.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    bg.layer.cornerRadius = 12;
    bg.layer.borderWidth = 2;
    bg.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    bg.userInteractionEnabled = NO;
    [btn addSubview:bg];
    
    UIImageView *iv = [[UIImageView alloc] initWithFrame:(snap && ![snap isEqual:[NSNull null]]) ? CGRectMake(3, 3, kIconSize - 6, kIconSize - 6) : CGRectMake(0, 0, kIconSize, kIconSize)];
    iv.image = (snap && ![snap isEqual:[NSNull null]]) ? snap : [UIImage systemImageNamed:@"macwindow"];
    iv.tintColor = [UIColor whiteColor];
    iv.contentMode = (snap && ![snap isEqual:[NSNull null]]) ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    iv.clipsToBounds = YES;
    iv.layer.cornerRadius = (snap && ![snap isEqual:[NSNull null]]) ? 10 : 0;
    [btn addSubview:iv];
    
    [btn addTarget:self action:@selector(minimizedTap:) forControlEvents:UIControlEventTouchUpInside];
    [btn.widthAnchor constraintEqualToConstant:kIconSize].active = YES;
    [btn.heightAnchor constraintEqualToConstant:kIconSize].active = YES;
    
    btn.alpha = 0;
    btn.transform = CGAffineTransformMakeScale(0.5, 0.5);
    [self.minimizedStack addArrangedSubview:btn];
    [UIView animateWithDuration:0.25 animations:^{ btn.alpha = 1; btn.transform = CGAffineTransformIdentity; }];
    [self updatePlaceholder];
}

- (void)removeMinimizedWindow:(NSInteger)wid {
    for (NSInteger i = 0; i < self.minimizedWindows.count; i++) {
        if ([self.minimizedWindows[i][@"windowID"] integerValue] == wid) { [self.minimizedWindows removeObjectAtIndex:i]; break; }
    }
    for (UIView *v in self.minimizedStack.arrangedSubviews) {
        if ([v isKindOfClass:[UIButton class]] && v.tag == wid) {
            [UIView animateWithDuration:0.2 animations:^{ v.alpha = 0; v.transform = CGAffineTransformMakeScale(0.5, 0.5); } completion:^(BOOL f) {
                [self.minimizedStack removeArrangedSubview:v];
                [v removeFromSuperview];
                [self updatePlaceholder];
            }];
            break;
        }
    }
}

- (void)minimizedTap:(UIButton *)btn {
    [[HIAHStateMachine shared] cancelDockAutoCollapse];
    if ([self.delegate respondsToSelector:@selector(appLauncher:didRequestRestoreWindow:)]) {
        [self.delegate appLauncher:self didRequestRestoreWindow:btn.tag];
    }
    [self removeMinimizedWindow:btn.tag];
}

- (void)updatePlaceholder { [self.minimizedScroll viewWithTag:200].hidden = self.minimizedStack.arrangedSubviews.count > 0; }

@end
