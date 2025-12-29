#import <Foundation/Foundation.h>

@interface HIAHJITManager : NSObject
+ (instancetype)sharedManager;
- (void)enableJITForPID:(pid_t)pid
             completion:
                 (void (^)(BOOL success, NSError *_Nullable error))completion;
- (void)mountDeveloperDiskImageWithCompletion:
    (void (^)(BOOL success, NSError *_Nullable error))completion;
@end
