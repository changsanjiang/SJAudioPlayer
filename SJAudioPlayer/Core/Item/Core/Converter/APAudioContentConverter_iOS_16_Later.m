//
//  APAudioContentConverter_iOS_16_Later.m
//  SJAudioPlayer
//
//  Created by 畅三江 on 2022/8/19.
//

#import "APAudioContentConverter_iOS_16_Later.h"
#import "APError.h"

@implementation APAudioContentConverter_iOS_16_Later {
    AVAudioConverter *_converter;
}

- (instancetype)initWithStreamFormat:(AVAudioFormat *)streamFormat {
    self = [super init];
    if ( self ) {
        _streamFormat = streamFormat;
        _outputFormat = [AVAudioFormat.alloc initStandardFormatWithSampleRate:44100 channels:2];
        _converter = [AVAudioConverter.alloc initFromFormat:_streamFormat toFormat:_outputFormat];
    }
    return self;
}

- (nullable AVAudioPCMBuffer *)convertPackets:(NSArray<id<APAudioContentPacket>> *)packets error:(NSError **)error {
    NSError *innerError = nil;
    AVAudioFrameCount frameCapacity = (AVAudioFrameCount)(_streamFormat.streamDescription->mFramesPerPacket * packets.count);
    AVAudioPCMBuffer *outputBuffer = [AVAudioPCMBuffer.alloc initWithPCMFormat:_outputFormat frameCapacity:frameCapacity];
    outputBuffer.frameLength = frameCapacity;
    __weak typeof(self) _self = self;
    __block NSInteger index = 0;
    [_converter convertToBuffer:outputBuffer error:&innerError withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
        __strong typeof(_self) self = _self;
        if ( !self ) {
            *outStatus = AVAudioConverterInputStatus_EndOfStream;
            return nil;
        }
        if ( index >= packets.count ) {
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
            return nil;
        }
        
        id<APAudioContentPacket> packet = packets[index];
        NSData *data = packet.data;
        
        AVAudioCompressedBuffer *inputBuffer = [[AVAudioCompressedBuffer alloc] initWithFormat:self->_streamFormat packetCapacity:1 maximumPacketSize:data.length];
        AudioBufferList *ioData = inputBuffer.mutableAudioBufferList;
        ioData->mNumberBuffers = 1;
        ioData->mBuffers[0].mDataByteSize = (UInt32)data.length;
        ioData->mBuffers[0].mNumberChannels = self->_streamFormat.streamDescription->mChannelsPerFrame;
        memcpy(ioData->mBuffers[0].mData, data.bytes, data.length);
        inputBuffer.packetCount = (AVAudioPacketCount)ioData->mNumberBuffers;
        if (@available(iOS 11.0, *)) {
            inputBuffer.byteLength = (UInt32)data.length;
        }
        if ( inputBuffer.packetDescriptions != NULL ) {
            inputBuffer.packetDescriptions->mStartOffset = packet.desc->mStartOffset;
            inputBuffer.packetDescriptions->mVariableFramesInPacket = packet.desc->mVariableFramesInPacket;
            inputBuffer.packetDescriptions->mDataByteSize = packet.desc->mDataByteSize;
        }
        index += 1;
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return inputBuffer;
    }];
    if ( innerError != nil ) {
        if ( error != NULL ) {
            *error = [NSError ap_errorWithCode:APContentConverterErrorFailedToCreatePCMBuffer userInfo:@{
                APErrorUserInfoErrorKey: innerError,
                NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentConverterErrorFailedToCreatePCMBuffer)
            }];
        }
        return nil;
    }
    outputBuffer.frameLength = frameCapacity;
    return outputBuffer;
}
@end
