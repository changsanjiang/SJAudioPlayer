//
//  APTimer.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/17.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APTimer.h"
#import <objc/runtime.h>

@implementation APTimer {
    dispatch_semaphore_t _semaphore;
    dispatch_source_t _timer;
    NSTimeInterval _timeInterval;
    BOOL _repeats;
    BOOL _valid;
    BOOL _suspend;
}

/// @param start 启动后延迟多少秒回调block
- (instancetype)initWithQueue:(dispatch_queue_t)queue start:(NSTimeInterval)start interval:(NSTimeInterval)interval repeats:(BOOL)repeats block:(void (^)(APTimer *timer))block {
    self = [super init];
    if ( self ) {
        _repeats = repeats;
        _timeInterval = interval;
        _valid = YES;
        _suspend = YES;
        _semaphore = dispatch_semaphore_create(1);
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (start * NSEC_PER_SEC)), (interval * NSEC_PER_SEC), 0);
        __weak typeof(self) _self = self;
        dispatch_source_set_event_handler(_timer, ^{
            __strong typeof(_self) self = _self;
            if ( self == nil ) return;
            block(self);
            if ( !repeats )
                [self invalidate];
        });
    }
    return self;
}

- (void)resume {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if ( _valid && _suspend ) {
        _suspend = NO;
        dispatch_resume(_timer);
    }
    dispatch_semaphore_signal(_semaphore);
}

- (void)suspend {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if ( _valid && !_suspend ) {
        _suspend = YES;
        dispatch_suspend(_timer);
    }
    dispatch_semaphore_signal(_semaphore);
}

- (void)invalidate {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if ( _valid ) {
        dispatch_source_cancel(_timer);
        if ( _suspend )
            dispatch_resume(_timer);
        _timer = NULL;
        _valid = NO;
    }
    dispatch_semaphore_signal(_semaphore);
}

- (BOOL)isValid {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    BOOL isValid = _valid;
    dispatch_semaphore_signal(_semaphore);
    return isValid;
}

- (void)dealloc {
    [self invalidate];
}

@end
