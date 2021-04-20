//
//  APAudioContentPacket.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface APAudioContentPacket : NSObject<APAudioContentPacket>
- (instancetype)initWithData:(NSData *)data;
@property (nonatomic, strong, readonly) NSData *data;
@property (nonatomic, readonly) AudioStreamPacketDescription *desc;
@end

NS_ASSUME_NONNULL_END
