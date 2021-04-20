//
//  APAudioContentPacket.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioContentPacket.h"

@implementation APAudioContentPacket
- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if ( self ) {
        _data = data;
        _desc = malloc(sizeof(AudioStreamPacketDescription));
        if ( _desc != NULL ) {
            memset(_desc, 0, sizeof(AudioStreamPacketDescription));
            _desc->mDataByteSize = (UInt32)data.length;
        }
    }
    return self;
}

- (void)dealloc {
    if ( _desc != NULL ) free(_desc);
}
@end
