//
//  APDefines.h
//  SJAudioPlayer
//
//  Created by BlueDancer on 2021/4/14.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#ifndef APDefines_h
#define APDefines_h

#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSUInteger, APAudioPlaybackStatus) {
    // Paused
    APAudioPlaybackStatusPaused             = 1 << 0,
    APAudioPlaybackStatusEnded              = 1 << 1 | APAudioPlaybackStatusPaused, // 已暂停, 播放完毕
    APAudioPlaybackStatusError              = 1 << 2 | APAudioPlaybackStatusPaused, // 已暂停, 播放报错

    // Playing
    APAudioPlaybackStatusPlaying            = 1 << 8,
    APAudioPlaybackStatusEvaluating         = 1 << 9  | APAudioPlaybackStatusPlaying, // 已调用播放, 正在评估缓冲状态
    APAudioPlaybackStatusBuffering          = 1 << 10 | APAudioPlaybackStatusPlaying, // 已调用播放, 处于缓冲中
    APAudioPlaybackStatusNoItemToPlay       = 1 << 11 | APAudioPlaybackStatusPlaying, // 已调用播放, 但未设置item, 设置后将自动播放
};


typedef NS_ENUM(NSUInteger, APAudioItemStatus) {
    APAudioItemStatusUnknown = 0,
    APAudioItemStatusReadyToPlay = 1,
    APAudioItemStatusFailed = 2
};

typedef NS_OPTIONS(NSUInteger, APLogOptions) {
    APLogOptionContentDownloadLine = 1 << 0,
    
    APLogOptionAudioPlayer = 1 << 1,
    
    APLogOptionDefault = APLogOptionAudioPlayer,
};

typedef NS_ENUM(NSUInteger, APLogLevel) {
    APLogLevelDebug,
    APLogLevelError,
};

typedef struct {
    AVAudioFramePosition startPosition; // seeked frames
    AVAudioFramePosition offset; // previous PCMBuffer frames
} APAudioPCMBufferPosition; // PCMBufferPositionInAudio = startPosition + offset

#endif /* APDefines_h */
