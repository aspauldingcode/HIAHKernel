/**
 * HIAHFloatingWindow.h
 * Draggable, resizable floating window for iOS apps
 * Integrates with HIAHStateMachine for focus and visual state management
 */

#import <UIKit/UIKit.h>
#import "HIAHStateMachine.h"

NS_ASSUME_NONNULL_BEGIN

@class HIAHFloatingWindow;

@protocol HIAHFloatingWindowDelegate <NSObject>
@optional
- (void)floatingWindowDidClose:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidBecomeActive:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidMinimize:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidChangeFrame:(HIAHFloatingWindow *)window;
- (void)floatingWindowDidEndDrag:(HIAHFloatingWindow *)window;
- (void)floatingWindow:(HIAHFloatingWindow *)window isDraggingNearNotch:(BOOL)nearNotch;
- (void)floatingWindowDidUpdateFrameDuringDrag:(HIAHFloatingWindow *)window;
@end

@interface HIAHFloatingWindow : UIView

@property (nonatomic, assign, readonly) NSInteger windowID;
@property (nonatomic, copy) NSString *windowTitle;
@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, weak, nullable) id<HIAHFloatingWindowDelegate> delegate;
@property (nonatomic, assign) BOOL isMinimized;
@property (nonatomic, assign) BOOL isMaximized;
@property (nonatomic, assign, readonly) BOOL isRolledUp;
@property (nonatomic, assign, readonly) BOOL isFocused;
@property (nonatomic, strong, nullable) UIColor *titleBarColor;
@property (nonatomic, strong, nullable) UIImage *appIcon;
@property (nonatomic, weak, nullable) HIAHStateMachine *stateMachine;  // State machine integration

- (instancetype)initWithFrame:(CGRect)frame windowID:(NSInteger)windowID title:(NSString *)title;

/// Set the content view controller (the app's UI)
- (void)setContentViewController:(UIViewController *)viewController;

/// Bring window to front
- (void)bringToFront;

/// Minimize window (shrink to icon)
- (void)minimize;

/// Restore from minimized state
- (void)restore;

/// Toggle maximize/restore
- (void)toggleMaximize;

/// Tile window to left half of screen
- (void)tileLeft;

/// Tile window to right half of screen
- (void)tileRight;

/// Toggle rollup/unroll (collapse to titlebar)
- (void)toggleRollup;

/// Close window
- (void)close;

/// Capture snapshot of content
- (nullable UIImage *)captureSnapshot;

/// Update focus state (called by state machine)
- (void)setFocused:(BOOL)focused animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

