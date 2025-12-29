/**
 * HIAHeDisplayMode.m
 * External Display Mode - Samsung DeX-style experience
 */

#import "HIAHeDisplayMode.h"

static const CGFloat kCursorSize = 32.0; // Larger cursor for better visibility (macOS-like)
static const CGFloat kDefaultSensitivity = 1.5;
static const CGFloat kTrackpadHeight = 0.65; // 65% of screen for trackpad

#pragma mark - Virtual Cursor Implementation

@interface HIAHVirtualCursor ()
@property (nonatomic, strong) UIImageView *cursorImage;
@property (nonatomic, strong) UIView *clickIndicator;
@end

@implementation HIAHVirtualCursor

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:CGRectMake(0, 0, kCursorSize, kCursorSize)]) {
        _sensitivity = kDefaultSensitivity;
        [self setupCursor];
    }
    return self;
}

- (void)setupCursor {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = NO;
    self.layer.zPosition = 10000;
    
    // macOS-like cursor arrow image - larger and more visible
    self.cursorImage = [[UIImageView alloc] initWithFrame:self.bounds];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold];
    self.cursorImage.image = [UIImage systemImageNamed:@"cursorarrow" withConfiguration:cfg];
    // White cursor with black outline for visibility (macOS style)
    self.cursorImage.tintColor = [UIColor whiteColor];
    self.cursorImage.contentMode = UIViewContentModeScaleAspectFit;
    
    // Add black outline/shadow for better visibility (macOS cursor style)
    self.cursorImage.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cursorImage.layer.shadowOffset = CGSizeMake(0.5, 0.5);
    self.cursorImage.layer.shadowRadius = 1;
    self.cursorImage.layer.shadowOpacity = 1.0;
    
    [self addSubview:self.cursorImage];
    
    // Strong drop shadow for visibility on any background
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(1, 2);
    self.layer.shadowRadius = 4;
    self.layer.shadowOpacity = 0.8;
    
    // Click indicator (ring that appears on click) - macOS style
    self.clickIndicator = [[UIView alloc] initWithFrame:CGRectMake(-8, -8, kCursorSize + 16, kCursorSize + 16)];
    self.clickIndicator.backgroundColor = [UIColor clearColor];
    self.clickIndicator.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    self.clickIndicator.layer.borderWidth = 2.5;
    self.clickIndicator.layer.cornerRadius = (kCursorSize + 16) / 2;
    self.clickIndicator.alpha = 0;
    [self addSubview:self.clickIndicator];
    
    // Ensure cursor is always visible
    self.alpha = 1.0;
    self.hidden = NO;
}

- (void)setPosition:(CGPoint)position {
    _position = position;
    self.center = position;
}

- (void)moveTo:(CGPoint)point animated:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:0.08 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.position = point;
        } completion:nil];
    } else {
        self.position = point;
    }
}

- (void)moveByDelta:(CGPoint)delta {
    CGPoint newPos = CGPointMake(
        self.position.x + delta.x * self.sensitivity,
        self.position.y + delta.y * self.sensitivity
    );
    
    // Clamp to superview bounds
    if (self.superview) {
        CGRect bounds = self.superview.bounds;
        newPos.x = MAX(0, MIN(newPos.x, bounds.size.width));
        newPos.y = MAX(0, MIN(newPos.y, bounds.size.height));
    }
    
    self.position = newPos;
}

- (void)animateClick {
    self.clickIndicator.transform = CGAffineTransformMakeScale(0.5, 0.5);
    self.clickIndicator.alpha = 1;
    
    [UIView animateWithDuration:0.15 animations:^{
        self.clickIndicator.transform = CGAffineTransformIdentity;
        self.clickIndicator.alpha = 0;
    }];
    
    // Quick scale bounce on cursor
    [UIView animateWithDuration:0.05 animations:^{
        self.cursorImage.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.05 animations:^{
            self.cursorImage.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)animateRightClick {
    self.clickIndicator.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.8].CGColor;
    [self animateClick];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.clickIndicator.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;
    });
}

- (void)setIsClicking:(BOOL)isClicking {
    _isClicking = isClicking;
    if (isClicking) {
        self.cursorImage.tintColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    } else {
        self.cursorImage.tintColor = [UIColor whiteColor];
    }
}

@end

#pragma mark - Input Controller Implementation

@interface HIAHInputController ()
@property (nonatomic, strong) UIView *trackpadArea;
@property (nonatomic, strong) UIView *keyboardArea;
@property (nonatomic, strong) UITextField *hiddenTextField;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *keyboardToggle;
@property (nonatomic, strong) UIView *trackpadSurface;
@property (nonatomic, assign) CGPoint lastTouchLocation;
@property (nonatomic, assign) NSInteger touchCount;
@property (nonatomic, assign) BOOL isDragging;
@property (nonatomic, strong) NSDate *lastTapTime;
@end

@implementation HIAHInputController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _trackpadSensitivity = kDefaultSensitivity;
    _naturalScrolling = YES;
    _tapToClick = YES;
    
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [self setupTrackpad];
    [self setupKeyboardArea];
    [self setupStatusBar];
}

- (void)setupStatusBar {
    UIView *statusBar = [[UIView alloc] init];
    statusBar.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:statusBar];
    
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"eDisplay Mode Active";
    self.statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [statusBar addSubview:self.statusLabel];
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"display"]];
    icon.tintColor = [UIColor systemBlueColor];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [statusBar addSubview:icon];
    
    [NSLayoutConstraint activateConstraints:@[
        [statusBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [statusBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [statusBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [statusBar.heightAnchor constraintEqualToConstant:44],
        [icon.leadingAnchor constraintEqualToAnchor:statusBar.leadingAnchor constant:16],
        [icon.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:statusBar.centerYAnchor],
    ]];
}

- (void)setupTrackpad {
    self.trackpadArea = [[UIView alloc] init];
    self.trackpadArea.backgroundColor = [UIColor clearColor];
    self.trackpadArea.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.trackpadArea];
    
    // Trackpad surface with subtle border
    self.trackpadSurface = [[UIView alloc] init];
    self.trackpadSurface.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.trackpadSurface.layer.cornerRadius = 20;
    self.trackpadSurface.layer.borderWidth = 1;
    self.trackpadSurface.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    self.trackpadSurface.translatesAutoresizingMaskIntoConstraints = NO;
    [self.trackpadArea addSubview:self.trackpadSurface];
    
    // Trackpad label
    UILabel *trackpadLabel = [[UILabel alloc] init];
    trackpadLabel.text = @"TRACKPAD";
    trackpadLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    trackpadLabel.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    trackpadLabel.textAlignment = NSTextAlignmentCenter;
    trackpadLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.trackpadSurface addSubview:trackpadLabel];
    
    // Instructions
    UILabel *instructions = [[UILabel alloc] init];
    instructions.text = @"Drag to move cursor\nTap to click • Two fingers to right-click\nTwo finger drag to scroll";
    instructions.font = [UIFont systemFontOfSize:12];
    instructions.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    instructions.textAlignment = NSTextAlignmentCenter;
    instructions.numberOfLines = 0;
    instructions.translatesAutoresizingMaskIntoConstraints = NO;
    [self.trackpadSurface addSubview:instructions];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.trackpadArea.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:54],
        [self.trackpadArea.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.trackpadArea.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.trackpadArea.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:kTrackpadHeight constant:-60],
        [self.trackpadSurface.topAnchor constraintEqualToAnchor:self.trackpadArea.topAnchor],
        [self.trackpadSurface.leadingAnchor constraintEqualToAnchor:self.trackpadArea.leadingAnchor],
        [self.trackpadSurface.trailingAnchor constraintEqualToAnchor:self.trackpadArea.trailingAnchor],
        [self.trackpadSurface.bottomAnchor constraintEqualToAnchor:self.trackpadArea.bottomAnchor],
        [trackpadLabel.topAnchor constraintEqualToAnchor:self.trackpadSurface.topAnchor constant:20],
        [trackpadLabel.centerXAnchor constraintEqualToAnchor:self.trackpadSurface.centerXAnchor],
        [instructions.centerXAnchor constraintEqualToAnchor:self.trackpadSurface.centerXAnchor],
        [instructions.centerYAnchor constraintEqualToAnchor:self.trackpadSurface.centerYAnchor],
    ]];
    
    // Gesture recognizers
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 2;
    [self.trackpadSurface addGestureRecognizer:pan];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.trackpadSurface addGestureRecognizer:tap];
    
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.trackpadSurface addGestureRecognizer:doubleTap];
    [tap requireGestureRecognizerToFail:doubleTap];
    
    UITapGestureRecognizer *twoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerTap:)];
    twoFingerTap.numberOfTouchesRequired = 2;
    [self.trackpadSurface addGestureRecognizer:twoFingerTap];
    
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self.trackpadSurface addGestureRecognizer:pinch];
}

- (void)setupKeyboardArea {
    self.keyboardArea = [[UIView alloc] init];
    self.keyboardArea.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.keyboardArea.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.keyboardArea];
    
    // Keyboard toggle button
    self.keyboardToggle = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.keyboardToggle setImage:[UIImage systemImageNamed:@"keyboard"] forState:UIControlStateNormal];
    [self.keyboardToggle setTitle:@" Show Keyboard" forState:UIControlStateNormal];
    self.keyboardToggle.tintColor = [UIColor whiteColor];
    self.keyboardToggle.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.keyboardToggle.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.keyboardToggle.layer.cornerRadius = 12;
    self.keyboardToggle.translatesAutoresizingMaskIntoConstraints = NO;
    [self.keyboardToggle addTarget:self action:@selector(toggleKeyboard) forControlEvents:UIControlEventTouchUpInside];
    [self.keyboardArea addSubview:self.keyboardToggle];
    
    // Hidden text field for keyboard input
    self.hiddenTextField = [[UITextField alloc] init];
    self.hiddenTextField.delegate = self;
    self.hiddenTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.hiddenTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.hiddenTextField.keyboardAppearance = UIKeyboardAppearanceDark;
    self.hiddenTextField.alpha = 0.01;
    self.hiddenTextField.translatesAutoresizingMaskIntoConstraints = NO;
    [self.keyboardArea addSubview:self.hiddenTextField];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.keyboardArea.topAnchor constraintEqualToAnchor:self.trackpadArea.bottomAnchor constant:10],
        [self.keyboardArea.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.keyboardArea.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.keyboardArea.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.keyboardToggle.centerXAnchor constraintEqualToAnchor:self.keyboardArea.centerXAnchor],
        [self.keyboardToggle.centerYAnchor constraintEqualToAnchor:self.keyboardArea.centerYAnchor],
        [self.keyboardToggle.widthAnchor constraintEqualToConstant:180],
        [self.keyboardToggle.heightAnchor constraintEqualToConstant:50],
        [self.hiddenTextField.centerXAnchor constraintEqualToAnchor:self.keyboardArea.centerXAnchor],
        [self.hiddenTextField.bottomAnchor constraintEqualToAnchor:self.keyboardArea.bottomAnchor],
    ]];
}

#pragma mark - Gesture Handlers

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint translation = [g translationInView:self.trackpadSurface];
    NSInteger touches = g.numberOfTouches;
    
    if (g.state == UIGestureRecognizerStateBegan) {
        self.touchCount = touches;
        self.isDragging = YES;
        // Visual feedback
        [UIView animateWithDuration:0.1 animations:^{
            self.trackpadSurface.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        }];
    } else if (g.state == UIGestureRecognizerStateChanged) {
        if (self.touchCount >= 2) {
            // Two finger scroll
            CGPoint delta = self.naturalScrolling ? CGPointMake(-translation.x, -translation.y) : translation;
            if ([self.delegate respondsToSelector:@selector(inputController:didScrollByDelta:)]) {
                [self.delegate inputController:self didScrollByDelta:delta];
            }
        } else {
            // Single finger cursor move
            if ([self.delegate respondsToSelector:@selector(inputController:didMoveCursorByDelta:)]) {
                [self.delegate inputController:self didMoveCursorByDelta:translation];
            }
        }
        [g setTranslation:CGPointZero inView:self.trackpadSurface];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.isDragging = NO;
        [UIView animateWithDuration:0.1 animations:^{
            self.trackpadSurface.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        }];
    }
}

- (void)handleTap:(UITapGestureRecognizer *)g {
    if (!self.tapToClick) return;
    
    // Visual feedback
    [self flashTrackpad];
    
    if ([self.delegate respondsToSelector:@selector(inputControllerDidTap:)]) {
        [self.delegate inputControllerDidTap:self];
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)g {
    [self flashTrackpad];
    
    if ([self.delegate respondsToSelector:@selector(inputControllerDidDoubleTap:)]) {
        [self.delegate inputControllerDidDoubleTap:self];
    }
}

- (void)handleTwoFingerTap:(UITapGestureRecognizer *)g {
    [self flashTrackpad];
    
    if ([self.delegate respondsToSelector:@selector(inputControllerDidTwoFingerTap:)]) {
        [self.delegate inputControllerDidTwoFingerTap:self];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateChanged) {
        if ([self.delegate respondsToSelector:@selector(inputController:didPinchWithScale:)]) {
            [self.delegate inputController:self didPinchWithScale:g.scale];
        }
        g.scale = 1.0;
    }
}

- (void)flashTrackpad {
    [UIView animateWithDuration:0.05 animations:^{
        self.trackpadSurface.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    } completion:^(BOOL f) {
        [UIView animateWithDuration:0.1 animations:^{
            self.trackpadSurface.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        }];
    }];
}

#pragma mark - Keyboard

- (void)toggleKeyboard {
    if (self.hiddenTextField.isFirstResponder) {
        [self hideKeyboard];
    } else {
        [self showKeyboard];
    }
}

- (void)showKeyboard {
    [self.hiddenTextField becomeFirstResponder];
    [self.keyboardToggle setTitle:@" Hide Keyboard" forState:UIControlStateNormal];
}

- (void)hideKeyboard {
    [self.hiddenTextField resignFirstResponder];
    [self.keyboardToggle setTitle:@" Show Keyboard" forState:UIControlStateNormal];
}

- (void)setStatusText:(NSString *)text {
    self.statusLabel.text = text;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (string.length == 0) {
        // Backspace
        if ([self.delegate respondsToSelector:@selector(inputControllerDidPressBackspace:)]) {
            [self.delegate inputControllerDidPressBackspace:self];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(inputController:didTypeText:)]) {
            [self.delegate inputController:self didTypeText:string];
        }
    }
    return NO; // Don't actually insert text
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([self.delegate respondsToSelector:@selector(inputControllerDidPressReturn:)]) {
        [self.delegate inputControllerDidPressReturn:self];
    }
    return NO;
}

@end

#pragma mark - eDisplay Mode Manager Implementation

@interface HIAHeDisplayMode ()
@property (nonatomic, assign) HIAHeDisplayModeState state;
@property (nonatomic, strong) UIScreen *externalScreen;
@property (nonatomic, strong) UIWindow *externalWindow;
@property (nonatomic, strong) UIWindow *inputWindow;
@property (nonatomic, strong) HIAHVirtualCursor *cursor;
@property (nonatomic, strong) HIAHInputController *inputController;
@property (nonatomic, strong) UIView *desktopContainer;
@property (nonatomic, assign) CGPoint cursorPosition;
@end

@implementation HIAHeDisplayMode

+ (instancetype)shared {
    static HIAHeDisplayMode *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HIAHeDisplayMode alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _state = HIAHeDisplayModeDisabled;
        
        // Monitor for scene connections (iOS 16+ replacement for UIScreen notifications)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screensDidChange:)
                                                     name:UISceneWillConnectNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screensDidChange:)
                                                     name:UISceneDidDisconnectNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)hasExternalDisplay {
    // iOS 16+: Use openSessions to find external displays
    // Get main screen from connected scenes (iOS 26.0+)
    UIScreen *mainScreen = nil;
    NSSet<UIScene *> *connectedScenes = [[UIApplication sharedApplication] connectedScenes];
    for (UIScene *scene in connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (!mainScreen && windowScene.screen) {
                mainScreen = windowScene.screen;
            } else if (windowScene.screen && windowScene.screen != mainScreen) {
                return YES; // Found external screen
            }
        }
    }
    if (!mainScreen) {
        mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
    }
    return NO;
}

- (void)screensDidChange:(NSNotification *)note {
    [self handleScreensDidChange];
}

- (void)handleScreensDidChange {
    // iOS 16+: Use connectedScenes to find external displays
    NSSet<UIScene *> *connectedScenes = [[UIApplication sharedApplication] connectedScenes];
    UIScreen *external = nil;
    UIScreen *mainScreen = nil;
    
    // First pass: identify main screen
    for (UIScene *scene in connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (!mainScreen && windowScene.screen) {
                mainScreen = windowScene.screen;
            }
        }
    }
    if (!mainScreen) {
        mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
    }
    
    // Second pass: find external screen
    for (UIScene *scene in connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.screen && windowScene.screen != mainScreen) {
                external = windowScene.screen;
                break;
            }
        }
    }
    
    BOOL hasExternalDisplay = (external != nil);
    
    if (hasExternalDisplay && self.state == HIAHeDisplayModeDisabled) {
        // External display connected - notify delegate to handle activation
        if (external) {
            // Check if delegate wants to handle window creation
            if ([self.delegate respondsToSelector:@selector(eDisplayMode:willActivateOnScreen:)]) {
                // Let delegate create the window and call back with it
                [self.delegate eDisplayMode:self willActivateOnScreen:external];
            } else {
                // No delegate or delegate doesn't implement - use default activation
                [self activateWithExternalScreen:external];
            }
        }
    } else if (!hasExternalDisplay && self.state == HIAHeDisplayModeActive) {
        // External display disconnected - deactivate
        [self deactivate];
    }
}

- (void)activateWithExternalScreen:(UIScreen *)screen existingWindow:(UIWindow *)existingWindow desktopViewController:(id)desktopVC {
    if (self.state == HIAHeDisplayModeActive) return;
    
    // Use the existing window and DesktopViewController
    if (existingWindow && desktopVC) {
        NSLog(@"[eDisplay] Using provided existing window and DesktopViewController for external screen");
        self.state = HIAHeDisplayModeTransitioning;
        self.externalWindow = existingWindow;
        self.externalScreen = screen;
        
        // Get the desktop view directly from DesktopViewController
        UIView *desktopView = nil;
        @try {
            desktopView = [desktopVC valueForKey:@"desktop"];
            if (desktopView && [desktopView isKindOfClass:[UIView class]]) {
                self.desktopContainer = desktopView;
                NSLog(@"[eDisplay] Found desktop view: %@ (frame: %@)", 
                      desktopView, NSStringFromCGRect(desktopView.frame));
            } else {
                // Fallback to root VC view
                UIViewController *rootVC = existingWindow.rootViewController;
                self.desktopContainer = rootVC.view;
                NSLog(@"[eDisplay] Using root VC view as desktop container");
            }
        } @catch (NSException *exception) {
            NSLog(@"[eDisplay] KVC failed, using root VC view: %@", exception);
            UIViewController *rootVC = existingWindow.rootViewController;
            self.desktopContainer = rootVC.view;
        }
        
        // Create virtual cursor
        if (!self.cursor) {
            self.cursor = [[HIAHVirtualCursor alloc] init];
        }
        
        // Position cursor at center of desktop
        CGPoint center = CGPointMake(self.desktopContainer.bounds.size.width / 2, 
                                      self.desktopContainer.bounds.size.height / 2);
        self.cursor.position = center;
        self.cursorPosition = center;
        
        // Remove cursor from any previous parent
        [self.cursor removeFromSuperview];
        
        // Add cursor to desktop view
        [self.desktopContainer addSubview:self.cursor];
        
        // Ensure cursor is visible and on top
        self.cursor.hidden = NO;
        self.cursor.alpha = 1.0;
        self.cursor.layer.zPosition = 10000;
        [self.desktopContainer bringSubviewToFront:self.cursor];
        
        NSLog(@"[eDisplay] Cursor added to desktop view at position: %@", NSStringFromCGPoint(center));
        NSLog(@"[eDisplay] Cursor frame: %@, hidden: %d, alpha: %.2f", 
              NSStringFromCGRect(self.cursor.frame), self.cursor.hidden, self.cursor.alpha);
        
        // Setup input controller on iPhone
        [self setupInputControllerOnMainScreen];
        
        // CRITICAL: Ensure external window is still visible and key after input setup
        self.externalWindow.hidden = NO;
        [self.externalWindow makeKeyAndVisible];
        
        self.state = HIAHeDisplayModeActive;
        NSLog(@"[eDisplay] Mode activated successfully");
        NSLog(@"[eDisplay] External window: %@, hidden: %d, keyWindow: %d", 
              self.externalWindow, self.externalWindow.hidden, self.externalWindow.isKeyWindow);
        NSLog(@"[eDisplay] Desktop container: %@, frame: %@", 
              self.desktopContainer, NSStringFromCGRect(self.desktopContainer.frame));
        
        if ([self.delegate respondsToSelector:@selector(eDisplayModeDidActivate:onScreen:)]) {
            [self.delegate eDisplayModeDidActivate:self onScreen:screen];
        }
        
        return;
    }
    
    // Fallback to method without desktopVC
    [self activateWithExternalScreen:screen existingWindow:existingWindow];
}

- (void)activateWithExternalScreen:(UIScreen *)screen existingWindow:(UIWindow *)existingWindow {
    if (self.state == HIAHeDisplayModeActive) return;
    
    // Use the existing window instead of creating a new one
    if (existingWindow) {
        NSLog(@"[eDisplay] Using provided existing window for external screen");
        self.externalWindow = existingWindow;
        self.externalScreen = screen;
        
        // Get the desktop container from the window's root view controller
        // The root VC should be a DesktopViewController
        UIViewController *rootVC = existingWindow.rootViewController;
        if (rootVC && rootVC.view) {
            // Try to get desktop view via KVC
            @try {
                UIView *desktopView = [rootVC valueForKey:@"desktop"];
                if (desktopView && [desktopView isKindOfClass:[UIView class]]) {
                    self.desktopContainer = desktopView;
                    NSLog(@"[eDisplay] Found desktop view via KVC: %@", NSStringFromCGRect(desktopView.frame));
                } else {
                    self.desktopContainer = rootVC.view;
                    NSLog(@"[eDisplay] Using root VC view as desktop container");
                }
            } @catch (NSException *exception) {
                self.desktopContainer = rootVC.view;
                NSLog(@"[eDisplay] KVC failed, using root VC view: %@", exception);
            }
        } else {
            NSLog(@"[eDisplay] ERROR: Existing window has no root view controller!");
            // Fallback to normal activation
            [self activateWithExternalScreen:screen];
            return;
        }
        
        // Continue with cursor and input setup
        [self setupCursorAndInputForScreen:screen];
        
        self.state = HIAHeDisplayModeActive;
        
        if ([self.delegate respondsToSelector:@selector(eDisplayModeDidActivate:onScreen:)]) {
            [self.delegate eDisplayModeDidActivate:self onScreen:screen];
        }
        
        return;
    }
    
    // Fallback to normal activation if window is invalid
    [self activateWithExternalScreen:screen];
}

- (void)setupCursorAndInputForScreen:(UIScreen *)screen {
    // Virtual cursor
    if (!self.cursor) {
        self.cursor = [[HIAHVirtualCursor alloc] init];
    }
    
    CGPoint center = CGPointMake(screen.bounds.size.width / 2, screen.bounds.size.height / 2);
    self.cursor.position = center;
    self.cursorPosition = center;
    
    // Use desktopContainer directly - it should already be the desktop view
    // (set in activateWithExternalScreen:existingWindow:desktopViewController:)
    UIView *targetView = self.desktopContainer;
    
    if (!targetView) {
        NSLog(@"[eDisplay] ERROR: desktopContainer is nil!");
        return;
    }
    
    // Remove cursor from any previous parent
    [self.cursor removeFromSuperview];
    
    // Add cursor to target view
    [targetView addSubview:self.cursor];
    
    // Ensure cursor is visible and on top
    self.cursor.hidden = NO;
    self.cursor.alpha = 1.0;
    self.cursor.layer.zPosition = 10000;
    [targetView bringSubviewToFront:self.cursor];
    
    // Update cursor position to center
    self.cursor.position = center;
    self.cursorPosition = center;
    
    NSLog(@"[eDisplay] Cursor added to view: %@ (class: %@) at position: %@", 
          targetView, NSStringFromClass([targetView class]), NSStringFromCGPoint(center));
    NSLog(@"[eDisplay] Cursor frame: %@, target view bounds: %@", 
          NSStringFromCGRect(self.cursor.frame), NSStringFromCGRect(targetView.bounds));
    NSLog(@"[eDisplay] Cursor hidden: %d, alpha: %.2f, zPosition: %.0f", 
          self.cursor.hidden, self.cursor.alpha, self.cursor.layer.zPosition);
    
    // Input controller on iPhone
    self.inputController = [[HIAHInputController alloc] init];
    self.inputController.delegate = self;
    
    // Find the main window scene
    UIWindowScene *mainScene = nil;
    UIScreen *mainScreen = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (!mainScreen && ws.screen) {
                mainScreen = ws.screen;
                mainScene = ws;
            }
        }
    }
    if (!mainScreen) {
        mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
    }
    
    if (mainScene) {
        self.inputWindow = [[UIWindow alloc] initWithWindowScene:mainScene];
        self.inputWindow.frame = mainScreen.bounds;
        self.inputWindow.rootViewController = self.inputController;
        self.inputWindow.windowLevel = UIWindowLevelNormal + 1;
        self.inputWindow.hidden = NO;
        [self.inputWindow makeKeyAndVisible];
        NSLog(@"[eDisplay] Input window created on main screen");
    } else {
        NSLog(@"[eDisplay] WARNING: Could not find main window scene for input window");
    }
}

/// Sets up just the input controller on the main screen (trackpad + keyboard)
- (void)setupInputControllerOnMainScreen {
    // Input controller on iPhone
    self.inputController = [[HIAHInputController alloc] init];
    self.inputController.delegate = self;
    
    // Find the main window scene
    UIWindowScene *mainScene = nil;
    UIScreen *mainScreen = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (!mainScreen && ws.screen) {
                mainScreen = ws.screen;
                mainScene = ws;
            }
        }
    }
    if (!mainScreen) {
        mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
    }
    
    if (mainScene) {
        self.inputWindow = [[UIWindow alloc] initWithWindowScene:mainScene];
        self.inputWindow.frame = mainScreen.bounds;
        self.inputWindow.rootViewController = self.inputController;
        self.inputWindow.windowLevel = UIWindowLevelNormal + 1;
        self.inputWindow.hidden = NO;
        // Don't make key - just make visible. The external window should remain key.
        // This prevents interference with the external display
        NSLog(@"[eDisplay] Input window created on main screen with window scene");
    } else {
        // Fallback without window scene
        NSLog(@"[eDisplay] WARNING: Could not find main window scene, creating without it");
        UIScreen *mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
        self.inputWindow = [[UIWindow alloc] initWithFrame:mainScreen.bounds];
        self.inputWindow.rootViewController = self.inputController;
        self.inputWindow.windowLevel = UIWindowLevelNormal + 1;
        self.inputWindow.hidden = NO;
        NSLog(@"[eDisplay] Input window created on main screen (legacy mode)");
    }
    
    NSLog(@"[eDisplay] Input controller delegate: %@", self.inputController.delegate);
    NSLog(@"[eDisplay] Input window: %@, hidden: %d", self.inputWindow, self.inputWindow.hidden);
}

- (void)activateWithExternalScreen:(UIScreen *)screen {
    if (self.state == HIAHeDisplayModeActive) return;
    
    self.state = HIAHeDisplayModeTransitioning;
    self.externalScreen = screen;
    
    NSLog(@"[eDisplay] Activating on external screen: %@ (bounds: %@)", screen, NSStringFromCGRect(screen.bounds));
    NSLog(@"[eDisplay] Screen available modes: %lu", (unsigned long)screen.availableModes.count);
    NSLog(@"[eDisplay] Screen current mode: %@", screen.currentMode);
    NSLog(@"[eDisplay] Screen preferred mode: %@", screen.preferredMode);
    
    // Ensure screen has a valid mode
    if (screen.availableModes.count == 0) {
        NSLog(@"[eDisplay] ERROR: External screen has no available modes!");
        self.state = HIAHeDisplayModeDisabled;
        return;
    }
    
    // Use preferred mode if available
    if (screen.preferredMode && screen.currentMode != screen.preferredMode) {
        screen.currentMode = screen.preferredMode;
        NSLog(@"[eDisplay] Set screen to preferred mode");
    }
    
    // Try to find or create a window scene for the external screen
    UIWindowScene *externalScene = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.screen == screen) {
                externalScene = ws;
                NSLog(@"[eDisplay] Found existing window scene for external screen");
                break;
            }
        }
    }
    
    // If no scene exists, try to create one using scene session
    if (!externalScene) {
        if (@available(iOS 13.0, *)) {
            // iOS doesn't provide a direct API to create window scenes for external screens
            // However, we can try to request a scene configuration
            // For now, we'll use the legacy window approach with KVC workaround
            NSLog(@"[eDisplay] No window scene found for external screen - using legacy approach with KVC");
        }
    }
    
    // Create window on external display
    // CRITICAL: On iOS, windows for external screens must be created with the screen property set correctly
    // We cannot change the screen after creation, so we must use the right initializer
    
    if (externalScene) {
        // Use window scene if available
        self.externalWindow = [[UIWindow alloc] initWithWindowScene:externalScene];
        NSLog(@"[eDisplay] Created window with window scene");
    } else {
        // For external displays without a scene, we need to create the window properly
        // The issue is that UIWindow doesn't have initWithFrame:screen: initializer
        // And setting screen after creation doesn't work reliably
        
        CGRect screenBounds = screen.bounds;
        
        // Create window using windowScene if available (iOS 26.0+)
        UIWindowScene *externalScene = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.screen == screen) {
                    externalScene = ws;
                    break;
                }
            }
        }
        
        if (externalScene) {
            self.externalWindow = [[UIWindow alloc] initWithWindowScene:externalScene];
        } else {
            // Fallback for iOS < 26.0
            self.externalWindow = [[UIWindow alloc] initWithFrame:screenBounds];
        }
        
        // Set screen using the same method as setupScreen
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([self.externalWindow respondsToSelector:@selector(setScreen:)]) {
            self.externalWindow.screen = screen;
            NSLog(@"[eDisplay] Set screen using setScreen: method");
        }
        #pragma clang diagnostic pop
        
        // If that didn't work, try KVC as fallback
        if (self.externalWindow.screen != screen) {
            @try {
                [self.externalWindow setValue:screen forKey:@"screen"];
                NSLog(@"[eDisplay] Set screen using KVC fallback");
            } @catch (NSException *exception) {
                NSLog(@"[eDisplay] KVC also failed: %@", exception);
            }
        }
        
        NSLog(@"[eDisplay] Created window without window scene");
        NSLog(@"[eDisplay] Screen set to: %@ (bounds: %@)", screen, NSStringFromCGRect(screen.bounds));
    }
    
    // Verify screen association
    UIScreen *windowScreen = self.externalWindow.screen;
    BOOL screenMatches = (windowScreen == screen);
    
    NSLog(@"[eDisplay] Window screen verification:");
    NSLog(@"[eDisplay]   Window screen: %@", windowScreen);
    NSLog(@"[eDisplay]   Target screen: %@", screen);
    NSLog(@"[eDisplay]   Matches: %d", screenMatches);
    NSLog(@"[eDisplay]   Window screen bounds: %@", NSStringFromCGRect(windowScreen.bounds));
    NSLog(@"[eDisplay]   Target screen bounds: %@", NSStringFromCGRect(screen.bounds));
    
    if (!screenMatches) {
        NSLog(@"[eDisplay] ERROR: Window screen does not match external screen!");
        NSLog(@"[eDisplay] This is a critical error - window will not display on external screen");
        NSLog(@"[eDisplay] Attempting alternative window creation approach...");
        
        // Try recreating the window with a different approach
        // Sometimes the screen needs a moment to be ready
        dispatch_async(dispatch_get_main_queue(), ^{
            // Try to find windowScene for this screen
            UIWindowScene *screenScene = nil;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    if (ws.screen == screen) {
                        screenScene = ws;
                        break;
                    }
                }
            }
            
            UIWindow *retryWindow = nil;
            if (screenScene) {
                retryWindow = [[UIWindow alloc] initWithWindowScene:screenScene];
            } else {
                // Fallback for iOS < 26.0
                retryWindow = [[UIWindow alloc] init];
            }
            [retryWindow setValue:screen forKey:@"screen"];
            retryWindow.frame = screen.bounds;
            retryWindow.backgroundColor = [UIColor blackColor];
            
            if (retryWindow.screen == screen) {
                NSLog(@"[eDisplay] Retry successful - replacing window");
                // Transfer content
                retryWindow.rootViewController = self.externalWindow.rootViewController;
                self.externalWindow = retryWindow;
                self.externalWindow.hidden = NO;
                [self.externalWindow makeKeyAndVisible];
            } else {
                NSLog(@"[eDisplay] Retry also failed - window screen still incorrect");
            }
        });
    }
    
    self.externalWindow.backgroundColor = [UIColor blackColor];
    self.externalWindow.rootViewController = nil; // Will be set below
    
    // Ensure frame matches screen bounds (like setupScreen does)
    self.externalWindow.frame = screen.bounds;
    
    // Desktop container
    self.desktopContainer = [[UIView alloc] initWithFrame:screen.bounds];
    self.desktopContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0];
    self.desktopContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.desktopContainer.userInteractionEnabled = YES;
    
    // Add a test label to verify the window is rendering
    UILabel *testLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 50, 400, 100)];
    testLabel.text = @"eDisplay Mode Active - HIAH Desktop";
    testLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
    testLabel.textColor = [UIColor whiteColor];
    testLabel.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:0.8];
    testLabel.textAlignment = NSTextAlignmentCenter;
    testLabel.layer.cornerRadius = 10;
    testLabel.clipsToBounds = YES;
    [self.desktopContainer addSubview:testLabel];
    
    UIViewController *externalVC = [[UIViewController alloc] init];
    externalVC.view = self.desktopContainer;
    
    // Set root view controller
    self.externalWindow.rootViewController = externalVC;
    
    // CRITICAL: Ensure window layer is properly configured for external screen
    // Force the window to update its screen association
    [self.externalWindow setNeedsLayout];
    [self.externalWindow layoutIfNeeded];
    
    // Make window visible and key
    self.externalWindow.hidden = NO;
    
    // CRITICAL: Ensure window is in the application's window hierarchy
    // This might be needed for external displays
    if (@available(iOS 13.0, *)) {
        if (externalScene && ![externalScene.windows containsObject:self.externalWindow]) {
            // Window should be in scene's windows list
            NSLog(@"[eDisplay] Window not in scene windows list - this might be the issue");
        }
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (![UIApplication.sharedApplication.windows containsObject:self.externalWindow]) {
            NSLog(@"[eDisplay] Window not in application windows list - this might be the issue");
        }
        #pragma clang diagnostic pop
    }
    
    // Force the window to become key on the external screen
    // This is critical for external displays
    [self.externalWindow makeKeyWindow];
    [self.externalWindow makeKeyAndVisible];
    
    // Force a layout pass to ensure everything is rendered
    [self.externalWindow setNeedsLayout];
    [self.externalWindow layoutIfNeeded];
    [self.desktopContainer setNeedsDisplay];
    
    // Additional verification - check if window is actually on external screen
    UIScreen *actualScreen = self.externalWindow.screen;
    BOOL isOnExternalScreen = (actualScreen == screen);
    
    NSLog(@"[eDisplay] Window visibility setup complete");
    NSLog(@"[eDisplay] Window screen: %@, matches external: %d", actualScreen, isOnExternalScreen);
    NSLog(@"[eDisplay] Window isKeyWindow: %d, isHidden: %d", self.externalWindow.isKeyWindow, self.externalWindow.hidden);
    NSLog(@"[eDisplay] Window frame: %@", NSStringFromCGRect(self.externalWindow.frame));
    NSLog(@"[eDisplay] Root VC view frame: %@", NSStringFromCGRect(externalVC.view.frame));
    NSLog(@"[eDisplay] Desktop container frame: %@", NSStringFromCGRect(self.desktopContainer.frame));
    
    if (!isOnExternalScreen) {
        NSLog(@"[eDisplay] WARNING: Window is not on external screen! This will cause display issues.");
        NSLog(@"[eDisplay] Attempting to force screen association...");
        
        // Try one more time to set the screen
        // Note: This might not work, but it's worth trying
        dispatch_async(dispatch_get_main_queue(), ^{
            // Sometimes the screen association needs to happen on the next run loop
            if (self.externalWindow.screen != screen) {
                NSLog(@"[eDisplay] Screen association failed - window may not display correctly");
            }
        });
    }
    
    NSLog(@"[eDisplay] External window created: %@, hidden: %d, keyWindow: %d", 
          self.externalWindow, self.externalWindow.hidden, self.externalWindow.isKeyWindow);
    NSLog(@"[eDisplay] External window frame: %@", NSStringFromCGRect(self.externalWindow.frame));
    NSLog(@"[eDisplay] Desktop container frame: %@", NSStringFromCGRect(self.desktopContainer.frame));
    
    // Setup cursor and input using shared method
    [self setupCursorAndInputForScreen:screen];
    
    self.state = HIAHeDisplayModeActive;
    
    // Notify delegate AFTER everything is set up
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(eDisplayModeDidActivate:onScreen:)]) {
            [self.delegate eDisplayModeDidActivate:self onScreen:screen];
        }
        NSLog(@"[eDisplay] Mode activated - delegate notified");
    });
}

- (void)cancelActivation {
    NSLog(@"[eDisplay] Activation cancelled");
    self.state = HIAHeDisplayModeDisabled;
}

- (void)deactivate {
    if (self.state == HIAHeDisplayModeDisabled) return;
    
    self.state = HIAHeDisplayModeTransitioning;
    
    NSLog(@"[eDisplay] Deactivating");
    
    // Clean up
    [self.cursor removeFromSuperview];
    self.cursor = nil;
    
    self.inputWindow.hidden = YES;
    self.inputWindow = nil;
    self.inputController = nil;
    
    self.externalWindow.hidden = YES;
    self.externalWindow = nil;
    self.externalScreen = nil;
    self.desktopContainer = nil;
    
    self.state = HIAHeDisplayModeDisabled;
    
    if ([self.delegate respondsToSelector:@selector(eDisplayModeDidDeactivate:)]) {
        [self.delegate eDisplayModeDidDeactivate:self];
    }
    
    NSLog(@"[eDisplay] Mode deactivated");
}

- (UIView *)desktopHostView {
    return self.desktopContainer;
}

- (void)setCursorPosition:(CGPoint)position {
    _cursorPosition = position;
    [self.cursor moveTo:position animated:NO];
}

- (UIView *)viewAtCursorPosition {
    if (!self.desktopContainer) return nil;
    
    // Find view at cursor position (excluding cursor itself)
    CGPoint point = self.cursorPosition;
    for (UIView *subview in [self.desktopContainer.subviews reverseObjectEnumerator]) {
        if (subview == self.cursor) continue;
        if (CGRectContainsPoint(subview.frame, point)) {
            return subview;
        }
    }
    return self.desktopContainer;
}

#pragma mark - HIAHInputControllerDelegate

- (void)inputController:(id)controller didMoveCursorByDelta:(CGPoint)delta {
    if (!self.cursor) {
        NSLog(@"[eDisplay] ERROR: Cursor is nil when trying to move!");
        return;
    }
    
    NSLog(@"[eDisplay] Moving cursor by delta: %@", NSStringFromCGPoint(delta));
    
    CGPoint oldPos = self.cursor.position;
    [self.cursor moveByDelta:delta];
    self.cursorPosition = self.cursor.position;
    
    NSLog(@"[eDisplay] Cursor moved from %@ to %@", NSStringFromCGPoint(oldPos), NSStringFromCGPoint(self.cursorPosition));
    NSLog(@"[eDisplay] Cursor superview: %@, hidden: %d, alpha: %.2f", 
          self.cursor.superview, self.cursor.hidden, self.cursor.alpha);
    
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:cursorDidMoveTo:)]) {
        [self.delegate eDisplayMode:self cursorDidMoveTo:self.cursorPosition];
    }
}

- (void)inputControllerDidTap:(id)controller {
    [self.cursor animateClick];
    
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didReceiveTapAtCursor:)]) {
        [self.delegate eDisplayMode:self didReceiveTapAtCursor:self.cursorPosition];
    }
}

- (void)inputControllerDidDoubleTap:(id)controller {
    [self.cursor animateClick];
    
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didReceiveDoubleTapAtCursor:)]) {
        [self.delegate eDisplayMode:self didReceiveDoubleTapAtCursor:self.cursorPosition];
    }
}

- (void)inputControllerDidTwoFingerTap:(id)controller {
    [self.cursor animateRightClick];
    
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didReceiveRightTapAtCursor:)]) {
        [self.delegate eDisplayMode:self didReceiveRightTapAtCursor:self.cursorPosition];
    }
}

- (void)inputController:(id)controller didScrollByDelta:(CGPoint)delta {
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didScrollByDelta:)]) {
        [self.delegate eDisplayMode:self didScrollByDelta:delta];
    }
}

- (void)inputController:(id)controller didPinchWithScale:(CGFloat)scale {
    // Could be used for zoom functionality
}

- (void)inputController:(id)controller didTypeText:(NSString *)text {
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didTypeText:)]) {
        [self.delegate eDisplayMode:self didTypeText:text];
    }
}

- (void)inputControllerDidPressReturn:(id)controller {
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didTypeText:)]) {
        [self.delegate eDisplayMode:self didTypeText:@"\n"];
    }
}

- (void)inputControllerDidPressBackspace:(id)controller {
    if ([self.delegate respondsToSelector:@selector(eDisplayMode:didTypeText:)]) {
        [self.delegate eDisplayMode:self didTypeText:@"\b"];
    }
}

@end

