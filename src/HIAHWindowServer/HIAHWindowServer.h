/**
 * HIAHWindowServer.h
 * Window Server for managing multiple app windows under HIAHKernel
 * 
 * Multi-window management for iOS apps
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class HIAHWindowSession;
@class HIAHKernel;

typedef NSInteger HIAHWindowID;

@protocol HIAHWindowServerDelegate <NSObject>
- (void)windowServerDidUpdateWindows;
@end

@interface HIAHWindowServer : UIWindow

@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, UIViewController *> *windows;
@property (nonatomic, strong, readonly) NSMutableArray<NSNumber *> *windowOrder;
@property (nonatomic, weak, nullable) id<HIAHWindowServerDelegate> delegate;
@property (nonatomic, strong, readonly) UIWindowScene *serverWindowScene;

+ (instancetype)sharedWithWindowScene:(UIWindowScene *)windowScene;
+ (instancetype)shared;

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene;

- (HIAHWindowID)openWindowForProcess:(pid_t)pid 
                         executablePath:(NSString *)executablePath
                         bundleIdentifier:(nullable NSString *)bundleIdentifier
                              completion:(void (^)(HIAHWindowID windowID, NSError * _Nullable error))completion;

- (BOOL)closeWindowWithID:(HIAHWindowID)windowID;
- (void)activateWindowWithID:(HIAHWindowID)windowID animated:(BOOL)animated;
- (void)focusWindowWithID:(HIAHWindowID)windowID;
- (void)closeAllWindows; // Cleanup all windows and destroy scenes

- (nullable UIViewController *)windowForID:(HIAHWindowID)windowID;

@end

NS_ASSUME_NONNULL_END

