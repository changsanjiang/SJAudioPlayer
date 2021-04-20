//
//  APTimer.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/17.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APTimer : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue start:(NSTimeInterval)start interval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(APTimer *timer))block;

@property (nonatomic, readonly, getter=isValid) BOOL valid;

- (void)resume;
- (void)suspend;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
