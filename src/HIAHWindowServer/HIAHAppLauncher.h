/**
 * HIAHAppLauncher.h
 * App launcher dock for HIAHKernel window manager
 * Uses HIAHStateMachine for state management
 */

#import <UIKit/UIKit.h>
#import "HIAHStateMachine.h"

NS_ASSUME_NONNULL_BEGIN

@class HIAHAppLauncher;

@protocol HIAHAppLauncherDelegate <NSObject>
- (void)appLauncher:(HIAHAppLauncher *)launcher didSelectApp:(NSString *)appName bundleID:(NSString *)bundleID;
@optional
- (void)appLauncher:(HIAHAppLauncher *)launcher didRequestRestoreWindow:(NSInteger)windowID;
@end

@interface HIAHAppLauncher : UIView <UICollectionViewDataSource, UICollectionViewDelegate>

@property (nonatomic, weak, nullable) id<HIAHAppLauncherDelegate> delegate;
@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *availableApps;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *minimizedWindows;

- (instancetype)initWithFrame:(CGRect)frame;

/// Add a minimized window to the dock
- (void)addMinimizedWindow:(NSInteger)windowID title:(NSString *)title snapshot:(nullable UIImage *)snapshot;

/// Remove a minimized window from the dock
- (void)removeMinimizedWindow:(NSInteger)windowID;

/// Update dock visuals for current state (called by state machine delegate)
- (void)applyDockState:(HIAHDockState)state animated:(BOOL)animated;

/// Update dock frame for current state and bounds
- (void)updateFrameForState:(HIAHDockState)state;

/// Refresh app list (call after installing new apps)
- (void)refreshApps;

@end

NS_ASSUME_NONNULL_END
