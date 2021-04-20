//
//  APAudioContentReader.h
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioInterfaces.h"

NS_ASSUME_NONNULL_BEGIN

@interface APAudioContentReader : NSObject<APAudioContentReader>

+ (instancetype)contentReaderWithURL:(NSURL *)URL delegate:(id<APAudioContentReaderDelegate>)delegate queue:(dispatch_queue_t)queue;

@property (nonatomic, weak, nullable) id<APAudioContentReaderDelegate> delegate;
@property (nonatomic, readonly) UInt64 countOfBytesTotalLength;
@property (nonatomic, readonly) UInt64 offset;

- (void)seekToOffset:(UInt64)offsetInBytes;
- (void)retry;
- (void)resume;
- (void)suspend;

@end

NS_ASSUME_NONNULL_END
