/**
 * HIAHeDisplayMode.h
 * External Display Mode - Samsung DeX-style experience
 * 
 * When external display connected:
 * - External display becomes the desktop workspace
 * - iPhone screen becomes trackpad + keyboard input
 * - Virtual cursor rendered on external display
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HIAHeDisplayModeState) {
    HIAHeDisplayModeDisabled,      // No external display, normal mode
    HIAHeDisplayModeActive,        // External display connected, eDisplay active
    HIAHeDisplayModeTransitioning  // Switching between modes
};

@class HIAHeDisplayMode;

#pragma mark - Virtual Cursor

@interface HIAHVirtualCursor : UIView
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, assign) CGFloat sensitivity;
@property (nonatomic, assign) BOOL isClicking;
@property (nonatomic, assign) BOOL isRightClicking;

- (void)moveTo:(CGPoint)point animated:(BOOL)animated;
- (void)moveByDelta:(CGPoint)delta;
- (void)animateClick;
- (void)animateRightClick;
@end

#pragma mark - Input Controller (Trackpad + Keyboard on iPhone)

@protocol HIAHInputControllerDelegate <NSObject>
- (void)inputController:(id)controller didMoveCursorByDelta:(CGPoint)delta;
- (void)inputControllerDidTap:(id)controller;
- (void)inputControllerDidDoubleTap:(id)controller;
- (void)inputControllerDidTwoFingerTap:(id)controller;  // Right click
- (void)inputController:(id)controller didScrollByDelta:(CGPoint)delta;
- (void)inputController:(id)controller didPinchWithScale:(CGFloat)scale;
- (void)inputController:(id)controller didTypeText:(NSString *)text;
- (void)inputControllerDidPressReturn:(id)controller;
- (void)inputControllerDidPressBackspace:(id)controller;
@end

@interface HIAHInputController : UIViewController <UITextFieldDelegate>
@property (nonatomic, weak, nullable) id<HIAHInputControllerDelegate> delegate;
@property (nonatomic, assign) CGFloat trackpadSensitivity;
@property (nonatomic, assign) BOOL naturalScrolling;
@property (nonatomic, assign) BOOL tapToClick;
@property (nonatomic, strong, readonly) UIView *trackpadArea;
@property (nonatomic, strong, readonly) UIView *keyboardArea;

- (void)showKeyboard;
- (void)hideKeyboard;
- (void)setStatusText:(NSString *)text;
@end

#pragma mark - eDisplay Mode Manager

@protocol HIAHeDisplayModeDelegate <NSObject>
@optional
/// Called when eDisplay mode detects an external screen and is about to activate.
/// Delegate should create the window and call activateWithExternalScreen:existingWindow:desktopViewController:
- (void)eDisplayMode:(HIAHeDisplayMode *)mode willActivateOnScreen:(UIScreen *)externalScreen;

/// Called after eDisplay mode has fully activated
- (void)eDisplayModeDidActivate:(HIAHeDisplayMode *)mode onScreen:(UIScreen *)externalScreen;
- (void)eDisplayModeDidDeactivate:(HIAHeDisplayMode *)mode;
- (void)eDisplayMode:(HIAHeDisplayMode *)mode cursorDidMoveTo:(CGPoint)position;
- (void)eDisplayMode:(HIAHeDisplayMode *)mode didReceiveTapAtCursor:(CGPoint)position;
- (void)eDisplayMode:(HIAHeDisplayMode *)mode didReceiveRightTapAtCursor:(CGPoint)position;
- (void)eDisplayMode:(HIAHeDisplayMode *)mode didReceiveDoubleTapAtCursor:(CGPoint)position;
- (void)eDisplayMode:(HIAHeDisplayMode *)mode didScrollByDelta:(CGPoint)delta;
- (void)eDisplayMode:(HIAHeDisplayMode *)mode didTypeText:(NSString *)text;
@end

@interface HIAHeDisplayMode : NSObject <HIAHInputControllerDelegate>

+ (instancetype)shared;

@property (nonatomic, weak, nullable) id<HIAHeDisplayModeDelegate> delegate;
@property (nonatomic, assign, readonly) HIAHeDisplayModeState state;
@property (nonatomic, strong, readonly, nullable) UIScreen *externalScreen;
@property (nonatomic, strong, readonly, nullable) UIWindow *externalWindow;
@property (nonatomic, strong, readonly, nullable) HIAHVirtualCursor *cursor;
@property (nonatomic, strong, readonly, nullable) HIAHInputController *inputController;
@property (nonatomic, assign, readonly) CGPoint cursorPosition;

/// Check if external display is available
@property (nonatomic, assign, readonly) BOOL hasExternalDisplay;

/// Manually activate/deactivate eDisplay mode
- (void)activateWithExternalScreen:(UIScreen *)screen;
- (void)activateWithExternalScreen:(UIScreen *)screen existingWindow:(UIWindow *)window; // Use existing window if provided
- (void)activateWithExternalScreen:(UIScreen *)screen existingWindow:(UIWindow *)window desktopViewController:(id)desktopVC; // Use existing window and desktop VC
- (void)deactivate;

/// Cancel activation (called by delegate if activation should be aborted)
- (void)cancelActivation;

/// Called by AppDelegate when screens change
- (void)handleScreensDidChange;

/// Get the view to host the desktop on (external window's root view)
- (nullable UIView *)desktopHostView;

/// Cursor control
- (void)setCursorPosition:(CGPoint)position;
- (UIView * _Nullable)viewAtCursorPosition;

@end

NS_ASSUME_NONNULL_END

