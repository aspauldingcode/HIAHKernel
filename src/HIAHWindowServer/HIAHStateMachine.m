/**
 * HIAHStateMachine.m
 * Centralized state machine for HIAH Desktop window management
 */

#import "HIAHStateMachine.h"

static const CGFloat kDefaultUnfocusedAlpha = 0.85;
static const NSTimeInterval kDefaultAutoCollapseDelay = 4.0;
static const CGFloat kDockOverlapThreshold = 100.0;

#pragma mark - Window State Implementation

@implementation HIAHWindowState

+ (instancetype)stateWithWindowID:(NSInteger)windowID {
    HIAHWindowState *state = [[HIAHWindowState alloc] init];
    state.windowID = windowID;
    state.focusState = HIAHWindowFocusStateUnfocused;
    state.displayState = HIAHWindowDisplayStateNormal;
    state.dragState = HIAHWindowDragStateIdle;
    state.unfocusedAlpha = kDefaultUnfocusedAlpha;
    state.frameBeforeStateChange = CGRectZero;
    return state;
}

@end

#pragma mark - State Machine Implementation

@interface HIAHStateMachine ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, HIAHWindowState *> *windowStates;
@property (nonatomic, assign) HIAHDockState dockState;
@property (nonatomic, assign) NSInteger focusedWindowID;
@property (nonatomic, assign) BOOL windowsOverlappingDock;
@property (nonatomic, strong) NSTimer *autoCollapseTimer;
@property (nonatomic, assign) BOOL isTransitioning;  // Prevent rapid state changes
@end

@implementation HIAHStateMachine

#pragma mark - Singleton

+ (instancetype)shared {
    static HIAHStateMachine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HIAHStateMachine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _windowStates = [NSMutableDictionary dictionary];
        _dockState = HIAHDockStateNormal;
        _focusedWindowID = -1;
        _windowsOverlappingDock = NO;
        _dockAutoCollapseDelay = kDefaultAutoCollapseDelay;
        _unfocusedWindowAlpha = kDefaultUnfocusedAlpha;
    }
    return self;
}

- (void)dealloc {
    [_autoCollapseTimer invalidate];
}

#pragma mark - Dock State Management

- (void)setDockState:(HIAHDockState)state animated:(BOOL)animated {
    if (_dockState == state) return;
    if (_isTransitioning) return;  // Prevent rapid state changes
    
    _isTransitioning = YES;
    [self cancelDockAutoCollapse];
    _dockState = state;
    
    // Start auto-collapse timer if temporarily revealed
    if (state == HIAHDockStateTemporarilyRevealed) {
        self.autoCollapseTimer = [NSTimer scheduledTimerWithTimeInterval:self.dockAutoCollapseDelay
                                                                  target:self
                                                                selector:@selector(autoCollapseTimerFired)
                                                                userInfo:nil
                                                                 repeats:NO];
    }
    
    if ([self.delegate respondsToSelector:@selector(stateMachine:dockStateDidChange:)]) {
        [self.delegate stateMachine:self dockStateDidChange:state];
    }
}

- (void)autoCollapseTimerFired {
    if (_dockState == HIAHDockStateTemporarilyRevealed && _windowsOverlappingDock) {
        [self setDockState:HIAHDockStatePill animated:YES];
    }
}

- (void)dockTransitionDidComplete {
    _isTransitioning = NO;
}

- (void)cancelDockAutoCollapse {
    [self.autoCollapseTimer invalidate];
    self.autoCollapseTimer = nil;
}

- (void)updateDockForWindowFrames:(NSArray<NSValue *> *)frames inBounds:(CGRect)bounds {
    CGFloat dockTop = bounds.size.height - kDockOverlapThreshold;
    BOOL overlapping = NO;
    
    for (NSValue *frameValue in frames) {
        CGRect frame = [frameValue CGRectValue];
        // Check if window overlaps dock area or covers >80% of screen
        CGFloat coverage = (frame.size.width * frame.size.height) / (bounds.size.width * bounds.size.height);
        if (coverage > 0.8 || CGRectGetMaxY(frame) > dockTop) {
            overlapping = YES;
            break;
        }
    }
    
    BOOL wasOverlapping = _windowsOverlappingDock;
    _windowsOverlappingDock = overlapping;
    
    // State transitions based on overlap
    if (_dockState == HIAHDockStateNormal && overlapping) {
        [self setDockState:HIAHDockStatePill animated:YES];
    } else if (_dockState == HIAHDockStatePill && !overlapping) {
        [self setDockState:HIAHDockStateNormal animated:YES];
    } else if (_dockState == HIAHDockStateTemporarilyRevealed && !overlapping) {
        [self setDockState:HIAHDockStateNormal animated:YES];
    }
    
    if (wasOverlapping != overlapping) {
        if ([self.delegate respondsToSelector:@selector(stateMachineDidRequestDockUpdate:)]) {
            [self.delegate stateMachineDidRequestDockUpdate:self];
        }
    }
}

- (void)dockPillWasTapped {
    [self setDockState:HIAHDockStateTemporarilyRevealed animated:YES];
}

- (void)dockToggleWasTapped {
    [self cancelDockAutoCollapse];
    
    switch (_dockState) {
        case HIAHDockStateNormal:
        case HIAHDockStateTemporarilyRevealed:
            [self setDockState:HIAHDockStateLauncherOpen animated:YES];
            break;
        case HIAHDockStateLauncherOpen:
            [self setDockState:_windowsOverlappingDock ? HIAHDockStateTemporarilyRevealed : HIAHDockStateNormal animated:YES];
            break;
        case HIAHDockStatePill:
            [self setDockState:HIAHDockStateTemporarilyRevealed animated:YES];
            break;
    }
}

#pragma mark - Window State Management

- (HIAHWindowState *)registerWindowWithID:(NSInteger)windowID {
    HIAHWindowState *state = [HIAHWindowState stateWithWindowID:windowID];
    state.unfocusedAlpha = self.unfocusedWindowAlpha;
    self.windowStates[@(windowID)] = state;
    return state;
}

- (void)unregisterWindowWithID:(NSInteger)windowID {
    [self.windowStates removeObjectForKey:@(windowID)];
    
    // If this was the focused window, clear focus
    if (_focusedWindowID == windowID) {
        _focusedWindowID = -1;
    }
}

- (HIAHWindowState *)stateForWindowID:(NSInteger)windowID {
    return self.windowStates[@(windowID)];
}

- (void)focusWindowWithID:(NSInteger)windowID {
    // Check if window exists
    HIAHWindowState *targetState = self.windowStates[@(windowID)];
    if (!targetState) return;
    
    // Skip if already focused
    if (_focusedWindowID == windowID) return;
    
    _focusedWindowID = windowID;
    
    // ALWAYS update ALL window focus states and notify delegate
    // This ensures visual state is always in sync, even if state machine thinks
    // nothing changed (e.g., due to initialization timing)
    for (NSNumber *wid in self.windowStates) {
        HIAHWindowState *state = self.windowStates[wid];
        HIAHWindowFocusState newFocusState = ([wid integerValue] == windowID) 
            ? HIAHWindowFocusStateFocused 
            : HIAHWindowFocusStateUnfocused;
        
        state.focusState = newFocusState;
        
        // Always notify delegate to ensure visual state is applied
        if ([self.delegate respondsToSelector:@selector(stateMachine:windowFocusDidChange:toState:)]) {
            [self.delegate stateMachine:self windowFocusDidChange:[wid integerValue] toState:newFocusState];
        }
    }
    
    // Collapse dock if temporarily revealed and windows overlap
    if ((_dockState == HIAHDockStateTemporarilyRevealed || _dockState == HIAHDockStateLauncherOpen) && _windowsOverlappingDock) {
        [self setDockState:HIAHDockStatePill animated:YES];
    }
}

- (void)unfocusAllWindows {
    _focusedWindowID = -1;
    
    for (NSNumber *wid in self.windowStates) {
        HIAHWindowState *state = self.windowStates[wid];
        if (state.focusState != HIAHWindowFocusStateUnfocused) {
            state.focusState = HIAHWindowFocusStateUnfocused;
            if ([self.delegate respondsToSelector:@selector(stateMachine:windowFocusDidChange:toState:)]) {
                [self.delegate stateMachine:self windowFocusDidChange:[wid integerValue] toState:HIAHWindowFocusStateUnfocused];
            }
        }
    }
}

- (void)setDisplayState:(HIAHWindowDisplayState)state forWindowID:(NSInteger)windowID {
    HIAHWindowState *windowState = self.windowStates[@(windowID)];
    if (!windowState || windowState.displayState == state) return;
    
    windowState.displayState = state;
    
    if ([self.delegate respondsToSelector:@selector(stateMachine:windowDisplayDidChange:toState:)]) {
        [self.delegate stateMachine:self windowDisplayDidChange:windowID toState:state];
    }
}

- (void)setDragState:(HIAHWindowDragState)state forWindowID:(NSInteger)windowID {
    HIAHWindowState *windowState = self.windowStates[@(windowID)];
    if (!windowState || windowState.dragState == state) return;
    
    windowState.dragState = state;
    
    if ([self.delegate respondsToSelector:@selector(stateMachine:windowDragDidChange:toState:)]) {
        [self.delegate stateMachine:self windowDragDidChange:windowID toState:state];
    }
}

#pragma mark - Visual Effects

- (void)applyVisualStateToWindow:(UIView *)windowView withID:(NSInteger)windowID animated:(BOOL)animated {
    HIAHWindowState *state = self.windowStates[@(windowID)];
    if (!state) return;
    
    CGFloat targetAlpha = [self alphaForWindowID:windowID];
    CGFloat targetScale = 1.0;
    
    // Apply display state effects
    switch (state.displayState) {
        case HIAHWindowDisplayStateMinimized:
            targetAlpha = 0.0;
            targetScale = 0.1;
            break;
        case HIAHWindowDisplayStateNormal:
        case HIAHWindowDisplayStateMaximized:
        case HIAHWindowDisplayStateTiledLeft:
        case HIAHWindowDisplayStateTiledRight:
        case HIAHWindowDisplayStateRolledUp:
            // Use focus-based alpha
            break;
    }
    
    void (^applyChanges)(void) = ^{
        windowView.alpha = targetAlpha;
        if (targetScale != 1.0) {
            windowView.transform = CGAffineTransformMakeScale(targetScale, targetScale);
        } else {
            windowView.transform = CGAffineTransformIdentity;
        }
        
        // Apply subtle shadow change for focus
        if (state.focusState == HIAHWindowFocusStateFocused) {
            windowView.layer.shadowOpacity = 0.5;
            windowView.layer.shadowRadius = 15;
        } else {
            windowView.layer.shadowOpacity = 0.3;
            windowView.layer.shadowRadius = 10;
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:applyChanges completion:nil];
    } else {
        applyChanges();
    }
}

- (CGFloat)alphaForWindowID:(NSInteger)windowID {
    HIAHWindowState *state = self.windowStates[@(windowID)];
    if (!state) return 1.0;
    
    switch (state.focusState) {
        case HIAHWindowFocusStateFocused:
            return 1.0;
        case HIAHWindowFocusStateUnfocused:
            return state.unfocusedAlpha;
        case HIAHWindowFocusStateInactive:
            return state.unfocusedAlpha * 0.9;
    }
    return 1.0;
}

@end

