/**
 * HIAHStateMachine.h
 * Centralized state machine for HIAH Desktop window management
 * Controls dock states, window focus, and visual effects
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - State Enums

/// Dock visibility and interaction states
typedef NS_ENUM(NSInteger, HIAHDockState) {
    HIAHDockStateNormal,              // Dock visible, launcher closed
    HIAHDockStateLauncherOpen,        // Dock visible, launcher expanded
    HIAHDockStatePill,                // Dock minimized to pill (windows overlapping)
    HIAHDockStateTemporarilyRevealed  // User opened from pill, will auto-collapse
};

/// Window focus states
typedef NS_ENUM(NSInteger, HIAHWindowFocusState) {
    HIAHWindowFocusStateUnfocused,    // Window is not focused (dimmed)
    HIAHWindowFocusStateFocused,      // Window is currently focused
    HIAHWindowFocusStateInactive      // Window belongs to inactive app
};

/// Window display states
typedef NS_ENUM(NSInteger, HIAHWindowDisplayState) {
    HIAHWindowDisplayStateNormal,     // Normal window display
    HIAHWindowDisplayStateMinimized,  // Window minimized to dock
    HIAHWindowDisplayStateMaximized,  // Window maximized to fill screen
    HIAHWindowDisplayStateRolledUp,   // Window collapsed to title bar
    HIAHWindowDisplayStateTiledLeft,  // Window tiled to left half
    HIAHWindowDisplayStateTiledRight  // Window tiled to right half
};

/// Window drag states
typedef NS_ENUM(NSInteger, HIAHWindowDragState) {
    HIAHWindowDragStateIdle,          // Not being dragged
    HIAHWindowDragStateDragging,      // Currently being dragged
    HIAHWindowDragStateResizing,      // Currently being resized
    HIAHWindowDragStateNearDropZone   // Dragged near transfer drop zone
};

#pragma mark - Window State Container

/// Complete state for a single window
@interface HIAHWindowState : NSObject
@property (nonatomic, assign) NSInteger windowID;
@property (nonatomic, assign) HIAHWindowFocusState focusState;
@property (nonatomic, assign) HIAHWindowDisplayState displayState;
@property (nonatomic, assign) HIAHWindowDragState dragState;
@property (nonatomic, assign) CGRect frameBeforeStateChange;
@property (nonatomic, assign) CGFloat unfocusedAlpha;
+ (instancetype)stateWithWindowID:(NSInteger)windowID;
@end

#pragma mark - State Machine Delegate

@class HIAHStateMachine;

@protocol HIAHStateMachineDelegate <NSObject>
@optional
- (void)stateMachine:(HIAHStateMachine *)sm dockStateDidChange:(HIAHDockState)newState;
- (void)stateMachine:(HIAHStateMachine *)sm windowFocusDidChange:(NSInteger)windowID toState:(HIAHWindowFocusState)state;
- (void)stateMachine:(HIAHStateMachine *)sm windowDisplayDidChange:(NSInteger)windowID toState:(HIAHWindowDisplayState)state;
- (void)stateMachine:(HIAHStateMachine *)sm windowDragDidChange:(NSInteger)windowID toState:(HIAHWindowDragState)state;
- (void)stateMachineDidRequestDockUpdate:(HIAHStateMachine *)sm;
@end

#pragma mark - State Machine

@interface HIAHStateMachine : NSObject

/// Singleton instance
+ (instancetype)shared;

/// Delegate for state change notifications
@property (nonatomic, weak, nullable) id<HIAHStateMachineDelegate> delegate;

/// Current dock state
@property (nonatomic, assign, readonly) HIAHDockState dockState;

/// Currently focused window ID (-1 if none)
@property (nonatomic, assign, readonly) NSInteger focusedWindowID;

/// Auto-collapse delay for temporarily revealed dock (seconds)
@property (nonatomic, assign) NSTimeInterval dockAutoCollapseDelay;

/// Alpha value for unfocused windows (0.0-1.0)
@property (nonatomic, assign) CGFloat unfocusedWindowAlpha;

/// Whether windows are currently overlapping dock area
@property (nonatomic, assign, readonly) BOOL windowsOverlappingDock;

#pragma mark - Dock State Management

/// Transition dock to a new state
- (void)setDockState:(HIAHDockState)state animated:(BOOL)animated;

/// Update dock based on window positions
- (void)updateDockForWindowFrames:(NSArray<NSValue *> *)frames inBounds:(CGRect)bounds;

/// Handle pill tap
- (void)dockPillWasTapped;

/// Handle dock toggle button tap
- (void)dockToggleWasTapped;

/// Cancel any pending auto-collapse
- (void)cancelDockAutoCollapse;

/// Notify that dock transition animation completed (internal use)
- (void)dockTransitionDidComplete;

#pragma mark - Window State Management

/// Register a new window
- (HIAHWindowState *)registerWindowWithID:(NSInteger)windowID;

/// Unregister a window
- (void)unregisterWindowWithID:(NSInteger)windowID;

/// Get state for a window
- (nullable HIAHWindowState *)stateForWindowID:(NSInteger)windowID;

/// Set focus to a window (unfocuses others)
- (void)focusWindowWithID:(NSInteger)windowID;

/// Remove focus from all windows
- (void)unfocusAllWindows;

/// Set display state for a window
- (void)setDisplayState:(HIAHWindowDisplayState)state forWindowID:(NSInteger)windowID;

/// Set drag state for a window
- (void)setDragState:(HIAHWindowDragState)state forWindowID:(NSInteger)windowID;

#pragma mark - Visual Effects

/// Apply visual state to a window view based on current state
- (void)applyVisualStateToWindow:(UIView *)windowView withID:(NSInteger)windowID animated:(BOOL)animated;

/// Get the appropriate alpha for a window based on focus state
- (CGFloat)alphaForWindowID:(NSInteger)windowID;

@end

NS_ASSUME_NONNULL_END

