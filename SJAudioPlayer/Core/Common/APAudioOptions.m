//
//  APAudioOptions.m
//  SJAudioPlayer
//
//  Created by BlueDancer on 2021/4/24.
//

#import "APAudioOptions.h"

@implementation APAudioOptions
+ (instancetype)defaultOptions {
    return [self.alloc init];
}

- (instancetype)init {
    self = [super init];
    if ( self ) {
        _maximumCountOfBytesPerPCMBufferPackets = 8192;
        _minimumCountOfPCMBufferToBePlayable = 1;
        _maximumCountOfPCMBufferForPlayback = 25;
    }
    return self;
}
@end
