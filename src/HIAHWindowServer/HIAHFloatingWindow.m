/**
 * HIAHFloatingWindow.m - Draggable, resizable floating window with rollup and tiling
 */

#import "HIAHFloatingWindow.h"

static const CGFloat kTitleH = 32, kMinW = 200, kMinH = 150, kResizeSize = 20, kRadius = 12, kBtnSize = 12, kBtnSpace = 6;

static const CGFloat kUnfocusedAlpha = 0.85;
static const CGFloat kFocusedShadowOpacity = 0.5;
static const CGFloat kUnfocusedShadowOpacity = 0.25;

@interface HIAHFloatingWindow ()
@property (nonatomic, strong) UIView *titleBar, *resizeHandle, *contentContainer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeBtn, *minBtn, *maxBtn, *rollBtn;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, weak) UIViewController *contentVC;
@property (nonatomic, assign) CGPoint dragStart, resizeAnchor;
@property (nonatomic, assign) CGRect frameBeforeMax, frameBeforeMin;
@property (nonatomic, assign) CGFloat heightBeforeRollup, widthBeforeRollup;
@property (nonatomic, strong) UIImage *snapshotBeforeRollup;
@property (nonatomic, assign) BOOL isDragging, isResizing, isRolledUp, isFocused;
@property (nonatomic, strong) UIWindowScene *ws;
@property (nonatomic, strong) UIVisualEffectView *unfocusedOverlay;
@property (nonatomic, strong) UIView *bottomCornerFill;  // Fill view for animatable bottom corners
@end

@implementation HIAHFloatingWindow

- (instancetype)initWithFrame:(CGRect)frame windowID:(NSInteger)wid title:(NSString *)title {
    if (self = [super initWithFrame:frame]) {
        _windowID = wid; _windowTitle = title;
        _titleBarColor = [UIColor colorWithWhite:0.15 alpha:0.98];
        _isFocused = NO;  // Explicitly initialize to unfocused
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]]) { _ws = (UIWindowScene *)s; break; }
        [self setupViews];
        [self setupGestures];
        
        // Apply initial unfocused visual state (without animation)
        // This ensures newly created windows look unfocused until explicitly focused
        [self setFocused:NO animated:NO];
        
        // Register with state machine
        if (self.stateMachine) {
            [self.stateMachine registerWindowWithID:wid];
        }
    }
    return self;
}

- (void)setupViews {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;  // Don't clip - let drop shadow show!
    self.layer.cornerRadius = kRadius;
    
    // Drop shadow decoration
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 6);
    self.layer.shadowRadius = 16;
    self.layer.shadowOpacity = 0.5;
    
    self.titleBar = [[UIView alloc] init];
    self.titleBar.backgroundColor = self.titleBarColor;
    self.titleBar.clipsToBounds = YES;  // Clip titleBar content  
    self.titleBar.layer.cornerRadius = kRadius;
    self.titleBar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;  // ALWAYS top corners
    [self addSubview:self.titleBar];
    
    // Create bottom corner fill with animatable cornerRadius
    self.bottomCornerFill = [[UIView alloc] init];
    self.bottomCornerFill.backgroundColor = self.titleBarColor;
    self.bottomCornerFill.userInteractionEnabled = NO;
    self.bottomCornerFill.layer.cornerRadius = 0;  // Start square (will animate to kRadius)
    self.bottomCornerFill.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;  // Bottom corners only
    self.bottomCornerFill.alpha = 1.0;  // Fully opaque
    self.bottomCornerFill.clipsToBounds = YES;  // IMPORTANT: Must clip to show corner radius
    [self.titleBar insertSubview:self.bottomCornerFill atIndex:0];  // Behind all titleBar content
    
    CGFloat y = (kTitleH - kBtnSize) / 2, x = 8;
    self.closeBtn = [self makeBtn:x y:y color:[UIColor colorWithRed:1 green:0.38 blue:0.35 alpha:1] icon:@"xmark" action:@selector(close)];
    self.minBtn = [self makeBtn:x + kBtnSize + kBtnSpace y:y color:[UIColor colorWithRed:1 green:0.74 blue:0.18 alpha:1] icon:@"minus" action:@selector(minimize)];
    self.maxBtn = [self makeBtn:x + (kBtnSize + kBtnSpace) * 2 y:y color:[UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1] icon:@"plus" action:@selector(toggleMaximize)];
    
    self.rollBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.rollBtn.frame = CGRectMake(0, 0, 24, 24);
    [self.rollBtn setImage:[UIImage systemImageNamed:@"chevron.down"] forState:UIControlStateNormal];
    [self.rollBtn setImage:[UIImage systemImageNamed:@"chevron.up"] forState:UIControlStateSelected];
    self.rollBtn.tintColor = [UIColor whiteColor]; self.rollBtn.alpha = 0.6;
    [self.rollBtn addTarget:self action:@selector(toggleRollup) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:self.rollBtn];
    
    self.iconView = [[UIImageView alloc] initWithFrame:CGRectMake(70, (kTitleH - 20) / 2, 20, 20)];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.layer.cornerRadius = 4; self.iconView.clipsToBounds = YES;
    [self.titleBar addSubview:self.iconView];
    
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = self.windowTitle;
    self.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    [self.titleBar addSubview:self.titleLabel];
    
    self.contentContainer = [[UIView alloc] init];
    self.contentContainer.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.contentContainer.clipsToBounds = YES;
    self.contentContainer.layer.cornerRadius = kRadius;
    self.contentContainer.layer.maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    [self addSubview:self.contentContainer];
    
    // Resize handle - just the grip lines, no background box
    self.resizeHandle = [[UIView alloc] init];
    self.resizeHandle.backgroundColor = [UIColor clearColor];
    [self addSubview:self.resizeHandle];
    
    // Grip lines only
    CAShapeLayer *grip = [CAShapeLayer layer];
    grip.frame = CGRectMake(0, 0, kResizeSize, kResizeSize);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(kResizeSize, 0)]; [p addLineToPoint:CGPointMake(0, kResizeSize)];
    [p moveToPoint:CGPointMake(kResizeSize, 5)]; [p addLineToPoint:CGPointMake(5, kResizeSize)];
    [p moveToPoint:CGPointMake(kResizeSize, 10)]; [p addLineToPoint:CGPointMake(10, kResizeSize)];
    grip.path = p.CGPath;
    grip.strokeColor = [UIColor colorWithWhite:0.5 alpha:0.8].CGColor;
    grip.lineWidth = 2; grip.lineCap = kCALineCapRound;
    [self.resizeHandle.layer addSublayer:grip];
    
    [self layoutSubviews];
}

- (UIButton *)makeBtn:(CGFloat)x y:(CGFloat)y color:(UIColor *)c icon:(NSString *)icon action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(x, y, kBtnSize, kBtnSize);
    b.backgroundColor = c; b.layer.cornerRadius = kBtnSize / 2;
    b.tag = (icon ? ([icon isEqualToString:@"xmark"] ? 1 : ([icon isEqualToString:@"minus"] ? 2 : 3)) : 0);  // Tag: 1=close, 2=min, 3=max
    if (icon) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:7 weight:UIImageSymbolWeightBold];
        UIImage *img = [UIImage systemImageNamed:icon withConfiguration:cfg];
        [b setImage:img forState:UIControlStateNormal];
        b.tintColor = [UIColor colorWithWhite:0.2 alpha:0.9];
        b.imageView.contentMode = UIViewContentModeCenter;
    }
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:b];
    return b;
}

- (void)updateTrafficLightsForFocus:(BOOL)focused {
    if (focused) {
        // Focused: show normal traffic lights with icons and original colors
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:7 weight:UIImageSymbolWeightBold];
        [self.closeBtn setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg] forState:UIControlStateNormal];
        [self.minBtn setImage:[UIImage systemImageNamed:@"minus" withConfiguration:cfg] forState:UIControlStateNormal];
        [self.maxBtn setImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg] forState:UIControlStateNormal];
        self.closeBtn.tintColor = [UIColor colorWithWhite:0.2 alpha:0.9];
        self.minBtn.tintColor = [UIColor colorWithWhite:0.2 alpha:0.9];
        self.maxBtn.tintColor = [UIColor colorWithWhite:0.2 alpha:0.9];
        // Restore original colors
        self.closeBtn.backgroundColor = [UIColor colorWithRed:1 green:0.38 blue:0.35 alpha:1];
        self.minBtn.backgroundColor = [UIColor colorWithRed:1 green:0.74 blue:0.18 alpha:1];
        self.maxBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1];
    } else {
        // Unfocused: show gray dots (no icons)
        [self.closeBtn setImage:nil forState:UIControlStateNormal];
        [self.minBtn setImage:nil forState:UIControlStateNormal];
        [self.maxBtn setImage:nil forState:UIControlStateNormal];
        // Gray dots - no icons
        self.closeBtn.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.6];
        self.minBtn.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.6];
        self.maxBtn.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.6];
    }
}

- (void)setupGestures {
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.titleBar addGestureRecognizer:drag];
    
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMaximize)];
    dbl.numberOfTapsRequired = 2;
    [self.titleBar addGestureRecognizer:dbl];
    
    UIPanGestureRecognizer *resize = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResize:)];
    [self.resizeHandle addGestureRecognizer:resize];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bringToFront)];
    [self addGestureRecognizer:tap];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.titleBar.frame = CGRectMake(0, 0, b.size.width, kTitleH);
    self.titleLabel.frame = CGRectMake(95, 0, b.size.width - 130, kTitleH);
    self.rollBtn.frame = CGRectMake(b.size.width - 28, 4, 24, 24);
    
    // Position bottom corner fill at the very bottom of titleBar
    if (self.bottomCornerFill) {
        self.bottomCornerFill.frame = self.titleBar.bounds;  // Full titleBar size
    }
    
    if (self.isRolledUp) {
        self.contentContainer.hidden = YES;
        self.resizeHandle.hidden = YES;
    } else {
        CGRect contentFrame = CGRectMake(0, kTitleH, b.size.width, b.size.height - kTitleH);
        self.contentContainer.frame = contentFrame;
        self.contentContainer.hidden = NO;
        self.resizeHandle.hidden = self.isMaximized;
        self.resizeHandle.frame = CGRectMake(b.size.width - kResizeSize - 4, b.size.height - kResizeSize - 4, kResizeSize, kResizeSize);
        
        // Update content view controller frame and trigger layout
        if (self.contentVC) {
            self.contentVC.view.frame = self.contentContainer.bounds;
            [self.contentVC.view setNeedsLayout];
            [self.contentVC.view layoutIfNeeded];
        }
    }
    [self bringSubviewToFront:self.resizeHandle];
    [self bringSubviewToFront:self.titleBar];
}

- (CGRect)safeAreaBounds {
    if (!self.superview) return CGRectZero;
    UIEdgeInsets s = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        UIView *v = self.superview;
        while (v && UIEdgeInsetsEqualToEdgeInsets(s, UIEdgeInsetsZero)) {
            s = v.safeAreaInsets; v = v.superview;
        }
        if (UIEdgeInsetsEqualToEdgeInsets(s, UIEdgeInsetsZero) && self.ws)
            for (UIWindow *w in self.ws.windows) if (w.safeAreaInsets.top > 0 || w.safeAreaInsets.bottom > 0) { s = w.safeAreaInsets; break; }
    }
    return UIEdgeInsetsInsetRect(self.superview.bounds, s);
}

#pragma mark - Gestures

- (void)handleDrag:(UIPanGestureRecognizer *)g {
    if (self.isMaximized) return;
    CGPoint t = [g translationInView:self.superview], loc = [g locationInView:self.superview];
    
    if (g.state == UIGestureRecognizerStateBegan) {
        self.isDragging = YES; self.dragStart = loc; [self bringToFront];
        
        // Notify state machine of drag start
        if (self.stateMachine) {
            [self.stateMachine setDragState:HIAHWindowDragStateDragging forWindowID:self.windowID];
        }
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGRect safe = [self safeAreaBounds];
        CGFloat minH = self.isRolledUp ? kTitleH : kMinH;
        CGPoint o = CGPointMake(self.frame.origin.x + t.x, self.frame.origin.y + t.y);
        o.x = MAX(safe.origin.x, MIN(o.x, CGRectGetMaxX(safe) - self.frame.size.width));
        o.y = MAX(safe.origin.y, MIN(o.y, CGRectGetMaxY(safe) - minH));
        
        // Only show notch indicator if external display exists (iOS 16+ compatible)
        BOOL hasExternal = NO;
        // Get main screen from connected scenes (iOS 26.0+)
        UIScreen *mainScreen = nil;
        NSSet<UIScene *> *connectedScenes = [[UIApplication sharedApplication] connectedScenes];
        for (UIScene *scene in connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                if (!mainScreen && windowScene.screen) {
                    mainScreen = windowScene.screen;
                } else if (windowScene.screen && windowScene.screen != mainScreen) {
                    hasExternal = YES;
                    break;
                }
            }
        }
        if (!mainScreen) {
            mainScreen = [UIScreen mainScreen]; // Fallback for iOS < 26.0
        }
        if (hasExternal) {
            CGFloat notchW = safe.size.width * 0.3, notchX = (safe.size.width - notchW) / 2;
            BOOL nearNotch = loc.y < safe.origin.y + 60 && loc.x >= notchX && loc.x <= notchX + notchW;
            if ([self.delegate respondsToSelector:@selector(floatingWindow:isDraggingNearNotch:)])
                [self.delegate floatingWindow:self isDraggingNearNotch:nearNotch];
        }
        
        CGRect f = self.frame; f.origin = o; self.frame = f;
        [g setTranslation:CGPointZero inView:self.superview];
        
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidUpdateFrameDuringDrag:)])
            [self.delegate floatingWindowDidUpdateFrameDuringDrag:self];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.isDragging = NO;
        
        // Notify state machine drag ended
        if (self.stateMachine) {
            [self.stateMachine setDragState:HIAHWindowDragStateIdle forWindowID:self.windowID];
        }
        
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidEndDrag:)]) [self.delegate floatingWindowDidEndDrag:self];
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)]) [self.delegate floatingWindowDidChangeFrame:self];
        if ([self.delegate respondsToSelector:@selector(floatingWindow:isDraggingNearNotch:)]) [self.delegate floatingWindow:self isDraggingNearNotch:NO];
    }
}

- (void)handleResize:(UIPanGestureRecognizer *)g {
    if (self.isMaximized || self.isRolledUp) return;
    CGPoint finger = [g locationInView:self.superview];
    CGRect safe = [self safeAreaBounds];
    
    if (g.state == UIGestureRecognizerStateBegan) {
        self.isResizing = YES;
        self.resizeAnchor = self.frame.origin;
        [self bringToFront];
        
        // Notify state machine of resize start
        if (self.stateMachine) {
            [self.stateMachine setDragState:HIAHWindowDragStateResizing forWindowID:self.windowID];
        }
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGFloat w = MAX(kMinW, MIN(finger.x - self.resizeAnchor.x, CGRectGetMaxX(safe) - self.resizeAnchor.x));
        CGFloat h = MAX(kMinH, MIN(finger.y - self.resizeAnchor.y, CGRectGetMaxY(safe) - self.resizeAnchor.y));
        self.frame = CGRectMake(self.resizeAnchor.x, self.resizeAnchor.y, w, h);
        [self setNeedsLayout]; [self layoutIfNeeded];
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)]) [self.delegate floatingWindowDidChangeFrame:self];
    } else if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        self.isResizing = NO;
        
        // Notify state machine resize ended
        if (self.stateMachine) {
            [self.stateMachine setDragState:HIAHWindowDragStateIdle forWindowID:self.windowID];
        }
        
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)]) [self.delegate floatingWindowDidChangeFrame:self];
    }
}

#pragma mark - Actions

- (void)bringToFront {
    // Dismiss keyboard from all other windows in superview before focusing this one
    for (UIView *sibling in self.superview.subviews) {
        if (sibling != self && [sibling isKindOfClass:[HIAHFloatingWindow class]]) {
            [sibling endEditing:YES];
        }
    }
    
    [self.superview bringSubviewToFront:self];
    
    // Notify state machine of focus change
    if (self.stateMachine) {
        [self.stateMachine focusWindowWithID:self.windowID];
    }
    
    if ([self.delegate respondsToSelector:@selector(floatingWindowDidBecomeActive:)]) [self.delegate floatingWindowDidBecomeActive:self];
}

- (void)minimize {
    if (self.isMinimized) return;
    
    // Dismiss keyboard before minimizing
    [self endEditing:YES];
    
    // Notify state machine
    if (self.stateMachine) {
        [self.stateMachine setDisplayState:HIAHWindowDisplayStateMinimized forWindowID:self.windowID];
    }
    
    self.frameBeforeMin = self.frame; self.isMinimized = YES;
    [UIView animateWithDuration:0.3 animations:^{
        self.transform = CGAffineTransformMakeScale(0.1, 0.1); self.alpha = 0;
    } completion:^(BOOL f) {
        self.hidden = YES;
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidMinimize:)]) [self.delegate floatingWindowDidMinimize:self];
    }];
}

- (void)restore {
    if (!self.isMinimized) return;
    
    // Notify state machine
    if (self.stateMachine) {
        [self.stateMachine setDisplayState:HIAHWindowDisplayStateNormal forWindowID:self.windowID];
    }
    
    self.hidden = NO; self.isMinimized = NO;
    [UIView animateWithDuration:0.3 animations:^{ self.transform = CGAffineTransformIdentity; self.alpha = 1; }];
}

- (void)toggleMaximize {
    if (self.isRolledUp) [self toggleRollup];
    if (self.isMaximized) {
        self.isMaximized = NO;
        
        // Notify state machine
        if (self.stateMachine) {
            [self.stateMachine setDisplayState:HIAHWindowDisplayStateNormal forWindowID:self.windowID];
        }
        
        [UIView animateWithDuration:0.3 animations:^{
            self.frame = self.frameBeforeMax; [self setNeedsLayout]; [self layoutIfNeeded];
        } completion:^(BOOL f) {
            if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)]) [self.delegate floatingWindowDidChangeFrame:self];
        }];
    } else {
        self.frameBeforeMax = self.frame; self.isMaximized = YES;
        
        // Notify state machine
        if (self.stateMachine) {
            [self.stateMachine setDisplayState:HIAHWindowDisplayStateMaximized forWindowID:self.windowID];
        }
        
        [UIView animateWithDuration:0.3 animations:^{
            self.frame = [self safeAreaBounds]; [self setNeedsLayout]; [self layoutIfNeeded];
        } completion:^(BOOL f) {
            if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)]) [self.delegate floatingWindowDidChangeFrame:self];
        }];
    }
}

- (void)tileLeft {
    if (self.isRolledUp) [self toggleRollup];
    CGRect s = [self safeAreaBounds];
    self.isMaximized = NO;
    
    // Notify state machine
    if (self.stateMachine) {
        [self.stateMachine setDisplayState:HIAHWindowDisplayStateTiledLeft forWindowID:self.windowID];
    }
    
    [UIView animateWithDuration:0.3 animations:^{
        self.frame = CGRectMake(s.origin.x, s.origin.y, s.size.width / 2, s.size.height);
        [self setNeedsLayout]; [self layoutIfNeeded];
    }];
}

- (void)tileRight {
    if (self.isRolledUp) [self toggleRollup];
    CGRect s = [self safeAreaBounds];
    self.isMaximized = NO;
    
    // Notify state machine
    if (self.stateMachine) {
        [self.stateMachine setDisplayState:HIAHWindowDisplayStateTiledRight forWindowID:self.windowID];
    }
    
    [UIView animateWithDuration:0.3 animations:^{
        self.frame = CGRectMake(s.origin.x + s.size.width / 2, s.origin.y, s.size.width / 2, s.size.height);
        [self setNeedsLayout]; [self layoutIfNeeded];
    }];
}

- (void)toggleRollup {
    CGFloat w = self.frame.size.width;
    
    // Dismiss keyboard when rolling up
    if (!self.isRolledUp) {
        [self endEditing:YES];
    }
    
    if (self.isRolledUp) {
        // Unroll - transition to normal state
        
        // Notify state machine
        if (self.stateMachine) {
            [self.stateMachine setDisplayState:HIAHWindowDisplayStateNormal forWindowID:self.windowID];
        }
        
        self.isRolledUp = NO;
        self.snapshotBeforeRollup = nil;
        
        // Animate bottom corner radius shrinking from kRadius to 0 (corners become square)
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.2];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [CATransaction setCompletionBlock:^{
            // After corners shrink to square, expand window
            CGRect startFrame = self.frame;
            CGRect endFrame = CGRectMake(startFrame.origin.x, startFrame.origin.y, w, self.heightBeforeRollup);
            
            // Show content before animation - start from titlebar area (collapsed state)
            self.contentContainer.hidden = NO;
            self.contentContainer.alpha = 0;
            self.contentContainer.frame = CGRectMake(0, kTitleH, w, 0); // Start collapsed
            self.resizeHandle.hidden = NO;
            self.resizeHandle.alpha = 0;
            
            // End frame for content: expands down from titlebar
            CGRect endContentFrame = CGRectMake(0, kTitleH, w, self.heightBeforeRollup - kTitleH);
            
            [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                // Expand window frame
                self.frame = endFrame;
                
                // Expand content down from titlebar
                self.contentContainer.frame = endContentFrame;
                self.contentContainer.alpha = 1;
                
                // Fade in resize handle
                self.resizeHandle.alpha = 1;
                self.resizeHandle.frame = CGRectMake(w - kResizeSize - 4, self.heightBeforeRollup - kResizeSize - 4, kResizeSize, kResizeSize);
            } completion:^(BOOL done) {
                if (done) {
                    if (self.contentVC) self.contentVC.view.frame = self.contentContainer.bounds;
                    if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)])
                        [self.delegate floatingWindowDidChangeFrame:self];
                }
            }];
        }];
        
        // Apply cornerRadius animation
        self.bottomCornerFill.layer.cornerRadius = 0;  // Set final value
        [CATransaction commit];
        
        self.rollBtn.selected = NO;
    } else {
        // Rollup - animate content sliding up into titlebar (opposite of unroll)
        self.snapshotBeforeRollup = [self captureSnapshotInternal];
        self.heightBeforeRollup = self.frame.size.height;
        self.widthBeforeRollup = w;
        
        // Store current content container frame (for future use if needed)
        // CGRect currentContentFrame = self.contentContainer.frame;
        
        // End frame: window shrinks to titlebar height
        CGRect startFrame = self.frame;
        CGRect endFrame = CGRectMake(startFrame.origin.x, startFrame.origin.y, w, kTitleH);
        
        // End frame for content: slides up (y moves up, height shrinks to 0)
        CGRect endContentFrame = CGRectMake(0, kTitleH, w, 0);
        
        // Ensure content is visible before animation
        self.contentContainer.hidden = NO;
        self.contentContainer.alpha = 1.0;
        self.resizeHandle.hidden = NO;
        self.resizeHandle.alpha = 1.0;
        
        // Animate: window frame shrinks, content slides up and fades out
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            // Shrink window frame
            self.frame = endFrame;
            
            // Slide content up into titlebar area
            self.contentContainer.frame = endContentFrame;
            self.contentContainer.alpha = 0;
            
            // Fade out resize handle
            self.resizeHandle.alpha = 0;
            
            // Update resize handle position as window shrinks
            self.resizeHandle.frame = CGRectMake(w - kResizeSize - 4, kTitleH - kResizeSize - 4, kResizeSize, kResizeSize);
        } completion:^(BOOL shrinkDone) {
            if (!shrinkDone) return;
            
            self.contentContainer.hidden = YES;
            self.resizeHandle.hidden = YES;
            
            // After window shrinks: Animate bottom corner radius growing from 0 to kRadius
            [CATransaction begin];
            [CATransaction setAnimationDuration:0.2];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
            [CATransaction setCompletionBlock:^{
                self.isRolledUp = YES;
                
                // Notify state machine of rolled up state
                if (self.stateMachine) {
                    [self.stateMachine setDisplayState:HIAHWindowDisplayStateRolledUp forWindowID:self.windowID];
                }
                
                if ([self.delegate respondsToSelector:@selector(floatingWindowDidChangeFrame:)])
                    [self.delegate floatingWindowDidChangeFrame:self];
            }];
            
            // Animate cornerRadius property
            self.bottomCornerFill.layer.cornerRadius = kRadius;  // CATransaction will animate this!
            [CATransaction commit];
        }];
        self.rollBtn.selected = YES;
    }
}

- (void)close {
    // Dismiss keyboard before closing
    [self endEditing:YES];
    
    // Unregister from state machine
    if (self.stateMachine) {
        [self.stateMachine unregisterWindowWithID:self.windowID];
    }
    
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformMakeScale(0.8, 0.8); self.alpha = 0;
    } completion:^(BOOL f) {
        if ([self.delegate respondsToSelector:@selector(floatingWindowDidClose:)]) [self.delegate floatingWindowDidClose:self];
        [self removeFromSuperview];
    }];
}

- (UIImage *)captureSnapshotInternal {
    if (self.contentContainer.bounds.size.width <= 0 || self.contentContainer.bounds.size.height <= 0) return nil;
    UIGraphicsBeginImageContextWithOptions(self.contentContainer.bounds.size, NO, 0);
    [self.contentContainer.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (UIImage *)captureSnapshot {
    return (self.isRolledUp && self.snapshotBeforeRollup) ? self.snapshotBeforeRollup : [self captureSnapshotInternal];
}

- (void)setWindowTitle:(NSString *)t { _windowTitle = t; self.titleLabel.text = t; }
- (void)setAppIcon:(UIImage *)i { _appIcon = i; self.iconView.image = i; }
- (void)setTitleBarColor:(UIColor *)c { _titleBarColor = c; self.titleBar.backgroundColor = c; }
- (UIView *)contentView { return self.contentContainer; }

- (void)setContentViewController:(UIViewController *)vc {
    if (self.contentVC) {
        [self.contentVC.view removeFromSuperview];
        [self.contentVC willMoveToParentViewController:nil];
        [self.contentVC removeFromParentViewController];
    }
    _contentVC = vc;
    if (vc) {
        // Add as child view controller to the delegate (which should be DesktopViewController)
        if (self.delegate && [self.delegate isKindOfClass:[UIViewController class]]) {
            UIViewController *parentVC = (UIViewController *)self.delegate;
            [parentVC addChildViewController:vc];
        }
        
        vc.view.frame = self.contentContainer.bounds;
        vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        vc.view.clipsToBounds = YES;
        [self.contentContainer addSubview:vc.view];
        
        if (self.delegate && [self.delegate isKindOfClass:[UIViewController class]]) {
            [vc didMoveToParentViewController:(UIViewController *)self.delegate];
        }
        
        [vc.view setNeedsLayout];
        [vc.view layoutIfNeeded];
    }
}

- (UIView *)hitTest:(CGPoint)pt withEvent:(UIEvent *)e {
    CGPoint tp = [self convertPoint:pt toView:self.titleBar];
    if (CGRectContainsPoint(self.closeBtn.frame, tp)) return self.closeBtn;
    if (CGRectContainsPoint(self.minBtn.frame, tp)) return self.minBtn;
    if (CGRectContainsPoint(self.maxBtn.frame, tp)) return self.maxBtn;
    if (CGRectContainsPoint(self.rollBtn.frame, tp)) return self.rollBtn;
    if (!self.isMaximized && !self.isRolledUp && CGRectContainsPoint(CGRectInset(self.resizeHandle.frame, -15, -15), pt))
        return self.resizeHandle;
    return [super hitTest:pt withEvent:e];
}

#pragma mark - Focus State

- (void)setFocused:(BOOL)focused animated:(BOOL)animated {
    BOOL stateChanged = (_isFocused != focused);
    _isFocused = focused;
    
    // Dismiss keyboard when losing focus
    if (!focused && stateChanged) {
        [self endEditing:YES];
    }
    
    // ALWAYS apply visual state - even if _isFocused was already the same value,
    // the visual state may not have been applied yet (e.g., on window creation)
    
    void (^applyFocus)(void) = ^{
        if (focused) {
            // Focused: full opacity, stronger shadow, no blur, normal traffic lights
            self.contentContainer.alpha = 1.0;
            self.titleBar.alpha = 1.0;
            self.titleBar.backgroundColor = self.titleBarColor;  // Normal titlebar color
            self.layer.shadowOpacity = kFocusedShadowOpacity;
            self.layer.shadowRadius = 15;
            
            // Show normal traffic lights with icons
            [self updateTrafficLightsForFocus:YES];
            
            // Remove unfocused blur overlay
            if (self.unfocusedOverlay) {
                self.unfocusedOverlay.alpha = 0;
                // Keep overlay in view hierarchy but hidden for performance
            }
        } else {
            // Unfocused: slightly dimmed, lighter titlebar, weaker shadow with glass blur effect
            self.contentContainer.alpha = kUnfocusedAlpha;
            // Lighten titlebar for unfocused state
            UIColor *lightenedTitleBar = [UIColor colorWithWhite:0.25 alpha:0.98];  // Lighter gray
            self.titleBar.backgroundColor = lightenedTitleBar;
            self.titleBar.alpha = kUnfocusedAlpha;
            self.layer.shadowOpacity = kUnfocusedShadowOpacity;
            self.layer.shadowRadius = 8;
            
            // Show gray dots (no icons) for traffic lights
            [self updateTrafficLightsForFocus:NO];
            
            // Add glass blur overlay for unfocused effect (NSGlassEffectView-like)
            if (!self.unfocusedOverlay) {
                // Use light blur for a frosted glass effect
                UIBlurEffect *blur;
                if (@available(iOS 13.0, *)) {
                    blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
                } else {
                    blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
                }
                self.unfocusedOverlay = [[UIVisualEffectView alloc] initWithEffect:blur];
                self.unfocusedOverlay.frame = self.contentContainer.bounds;
                self.unfocusedOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                self.unfocusedOverlay.userInteractionEnabled = NO;
                self.unfocusedOverlay.alpha = 0;
                // Ensure blur overlay is on top of content for glass effect
                [self.contentContainer addSubview:self.unfocusedOverlay];
            }
            // Update frame to match current bounds
            self.unfocusedOverlay.frame = self.contentContainer.bounds;
            // Visible glass blur effect - creates frosted glass appearance
            self.unfocusedOverlay.alpha = 0.5; // Glass blur effect
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:applyFocus completion:nil];
    } else {
        applyFocus();
    }
}

@end
