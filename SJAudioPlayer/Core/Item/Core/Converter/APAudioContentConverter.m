//
//  APAudioContentConverter.m
//  SJAudioPlayer_Example
//
//  Created by 畅三江 on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioContentConverter.h"
#import "APError.h"

#define APStatusCode_FinishFillBuffer (100)
 
@interface APBufferFiller : NSObject

@end

@implementation APBufferFiller {
    NSArray<id<APAudioContentPacket>> *_packets;
    AVAudioPacketCount _currentPosition;
    AVAudioFormat *_sourceFormat;
}

- (instancetype)initWithPackets:(NSArray<id<APAudioContentPacket>> *)packets sourceFormat:(AVAudioFormat *)sourceFormat {
    self = [super init];
    if ( self ) {
        _packets = packets.copy;
        _sourceFormat = sourceFormat;
    }
    return self;
}

- (OSStatus)fillBufferWithNumberOfDataPackets:(UInt32 *)ioNumberDataPackets bufferList:(AudioBufferList *)ioData desc:(AudioStreamPacketDescription **)outDataPacketDescription {
    if ( _currentPosition == _packets.count ) {
        *ioNumberDataPackets = 0;
        return APStatusCode_FinishFillBuffer;
    }
    
    id<APAudioContentPacket>packet = _packets[_currentPosition];
    
    //
    NSUInteger length = packet.data.length;
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mData = (void *)packet.data.bytes;
    ioData->mBuffers[0].mDataByteSize = (UInt32)length;
    ioData->mBuffers[0].mNumberChannels = _sourceFormat.streamDescription->mChannelsPerFrame;
    
    //
    if ( _sourceFormat.streamDescription->mFormatID != kAudioFormatLinearPCM ) {
        if ( outDataPacketDescription != NULL && *outDataPacketDescription == NULL ) {
            *outDataPacketDescription = packet.desc;
        }
    }
    
    _currentPosition += 1;
    *ioNumberDataPackets = 1;
    return noErr;
}
@end

static OSStatus
_mAudioConverterComplexInputDataProc(AudioConverterRef inAudioConverter,
                           UInt32 *ioNumberDataPackets,
                           AudioBufferList *ioData,
                           AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription,
                           void * __nullable inUserData) {
  APBufferFiller *filler = (__bridge APBufferFiller *)inUserData;
  return [filler fillBufferWithNumberOfDataPackets:ioNumberDataPackets bufferList:ioData desc:outDataPacketDescription];
}

@implementation APAudioContentConverter {
    AudioConverterRef _converter;
}

- (instancetype)initWithStreamFormat:(AVAudioFormat *)streamFormat {
    self = [super init];
    if ( self ) {
        _streamFormat = streamFormat;
        _outputFormat = [AVAudioFormat.alloc initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:44100 channels:2 interleaved:NO];
    }
    return self;
}

- (void)dealloc {
    if ( _converter != nil )
        AudioConverterDispose(_converter);
}

- (nullable AVAudioPCMBuffer *)convertPackets:(NSArray<id<APAudioContentPacket>> *)packets error:(NSError **)error {
    if ( _converter == nil ) {
        OSStatus status = AudioConverterNew(_streamFormat.streamDescription, _outputFormat.streamDescription, &_converter);
        if ( status != noErr ) {
            if ( error != NULL ) {
                *error = [NSError ap_errorWithCode:APContentConverterErrorUnableToCreateConverter userInfo:@{
                    APErrorUserInfoInputFormatKey : _streamFormat,
                    APErrorUserInfoOutputFormatKey : _outputFormat,
                    APErrorUserInfoErrorStatusKey : @(status),
                    NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentConverterErrorUnableToCreateConverter, status)
                }];
            }
            return nil;
        }
    }
    
    AVAudioFrameCount nAllFrames = (AVAudioFrameCount)(_streamFormat.streamDescription->mFramesPerPacket * packets.count);
    AVAudioPacketCount nAllPackets = (AVAudioPacketCount)(nAllFrames / _outputFormat.streamDescription->mFramesPerPacket);
    AVAudioPCMBuffer *buffer = [AVAudioPCMBuffer.alloc initWithPCMFormat:_outputFormat frameCapacity:nAllFrames];
    if ( buffer == nil ) {
        if ( error != NULL ) {
            *error = [NSError ap_errorWithCode:APContentConverterErrorFailedToCreatePCMBuffer userInfo:@{
                APErrorUserInfoOutputFormatKey : _outputFormat,
                APErrorUserInfoPCMFrameCapacityKey : @(nAllFrames),
                NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentConverterErrorFailedToCreatePCMBuffer),
            }];
        }
        return nil;
    }
    buffer.frameLength = nAllFrames;
    
    APBufferFiller *filler = [APBufferFiller.alloc initWithPackets:packets sourceFormat:_streamFormat];
    AudioConverterFillComplexBuffer(_converter, _mAudioConverterComplexInputDataProc, (__bridge void *)filler, &nAllPackets, buffer.mutableAudioBufferList, nil);
    return buffer;
}
@end
