//
//  AVAudioPlayerNode+AP.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "AVAudioPlayerNode+AP.h"

@implementation AVAudioPlayerNode (AP)

- (BOOL)ap_isPlaying {
    return self.engine.isRunning && self.isPlaying;
}

- (AVAudioFramePosition)ap_currentFramePosition {
    if ( self.ap_isPlaying ) {
        AVAudioTime *nodeTime = self.lastRenderTime;
        AVAudioTime *playerTime = [self playerTimeForNodeTime:nodeTime];
        return playerTime.sampleTime;
    }
    return 0;
}
@end
