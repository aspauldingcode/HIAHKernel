/**
 * HIAHWindowSession.h
 * Window session protocol for app windows
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSInteger HIAHWindowID;

@protocol HIAHWindowSession <NSObject>

@property (nonatomic, readonly) NSString *windowName;
@property (nonatomic, readonly) pid_t processPID;
@property (nonatomic, readonly) NSString *executablePath;
@property (nonatomic, readonly) BOOL isFullscreen;

- (BOOL)openWindowWithScene:(UIWindowScene *)windowScene withSessionIdentifier:(HIAHWindowID)identifier;
- (void)closeWindowWithScene:(UIWindowScene *)windowScene withFrame:(CGRect)rect;
- (nullable UIImage *)snapshotWindow;
- (void)activateWindow;
- (void)deactivateWindow;
- (void)windowChangesSizeToRect:(CGRect)rect;

@end

NS_ASSUME_NONNULL_END

