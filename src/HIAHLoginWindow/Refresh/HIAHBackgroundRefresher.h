#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIAHBackgroundRefresher : NSObject

+ (instancetype)sharedRefresher;
- (void)performRefreshWithCompletion:
    (void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
