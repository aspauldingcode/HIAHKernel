#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIAHVPNManager : NSObject
+ (instancetype)sharedManager;
@property(nonatomic, assign, readonly) BOOL isVPNActive;
- (void)setupVPNManager;
- (void)startVPNWithCompletion:
    (void (^_Nullable)(NSError *_Nullable error))completion;
- (void)stopVPN;
@end

NS_ASSUME_NONNULL_END
