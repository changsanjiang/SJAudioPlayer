//
//  APAudioStreamParser.m
//  SJAudioPlayer_Example
//
//  Created by BlueDancer on 2021/4/13.
//  Copyright © 2021 changsanjiang@gmail.com. All rights reserved.
//

#import "APAudioStreamParser.h"
#import "APAudioContentPacket.h"
#import "APError.h"

@implementation APAudioStreamParser {
    AudioFileStreamID _streamParser;
    NSMutableArray<APAudioContentPacket *> *_foundPackets;
    UInt64 _nBytesTotalFoundPackets;
    UInt64 _nCountTotalFoundPackets;
}

- (void)dealloc {
    if ( _streamParser != 0 )
        AudioFileStreamClose(_streamParser);
}

- (BOOL)process:(NSData *)data isDiscontinuous:(BOOL)isDiscontinuous error:(NSError **)error {
    if ( _streamParser == 0 ) {
        OSStatus status = AudioFileStreamOpen((__bridge void *)self, _mAudioFileStream_PropertyListenerProc, _mAudioFileStream_PacketsProc, kAudioFileMP3Type, &_streamParser);
        if ( status != noErr ) {
            if ( error != NULL ) {
                *error = [NSError ap_errorWithCode:APContentParserErrorCouldNotOpenStream userInfo:@{
                    NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentParserErrorCouldNotOpenStream)
                }];
            }
            return NO;
        }
    }
    
    OSStatus status = AudioFileStreamParseBytes(_streamParser, (UInt32)data.length, data.bytes, isDiscontinuous);
    if ( status != noErr ) {
        if ( error != NULL ) {
            *error = [NSError ap_errorWithCode:APContentParserErrorFailedToParseBytes userInfo:@{
                APErrorUserInfoErrorStatusKey : @(status),
                NSLocalizedDescriptionKey : APErrorLocalizedDescription(APContentParserErrorFailedToParseBytes, status)
            }];
        }
        return NO;
    }
    return YES;
}

- (void)removeAllFoundPackets {
    _countOfBytesFoundPackets = 0;
    [_foundPackets removeAllObjects];
}

- (void)removeFoundPacketsInRange:(NSRange)range {
    [_foundPackets removeObjectsInRange:range];
    for ( id<APAudioContentPacket> packet in _foundPackets ) {
        _countOfBytesFoundPackets += packet.data.length;
    }
}

- (BOOL)offsetAtPacket:(AVAudioPacketCount)index outOffset:(UInt64 *)outOffset isEstimated:(BOOL *)isEstimated {
    AudioFileStreamSeekFlags flags = 0;
    SInt64 offset = 0;
    OSStatus status = AudioFileStreamSeek(_streamParser, index, &offset, &flags);
    if ( status != noErr ) {
        return NO;
    }
    
    if ( outOffset != NULL ) {
        *outOffset = offset + _audioDataOffset;
    }
    
    if ( isEstimated != NULL ) {
        *isEstimated = (flags & kAudioFileStreamSeekFlag_OffsetIsEstimated);
    }
    return YES;
}

- (nullable NSArray<id<APAudioContentPacket>> *)foundPackets {
    return _foundPackets.count != 0 ? _foundPackets.copy : nil;
}

- (double)bitRate {
    if ( _format == nil || _nCountTotalFoundPackets == 0 ) {
        return 0;
    }
    double averagePacketByteSize = (double)_nBytesTotalFoundPackets / (double)_nCountTotalFoundPackets;
    return averagePacketByteSize / _durationPerPacket * 8;
}

#pragma mark - mark

- (void)_streamParserFoundProperty:(AudioFilePropertyID)propertyID flags:(AudioFileStreamPropertyFlags *)flags {
    switch ( propertyID ) {
        case kAudioFileStreamProperty_DataFormat: {
            AudioStreamBasicDescription desc;
            UInt32 typeSize = sizeof(desc);
            AudioFileStreamGetProperty(_streamParser, propertyID, &typeSize, &desc);
            _format = [AVAudioFormat.alloc initWithStreamDescription:&desc];
            _durationPerPacket = desc.mFramesPerPacket / desc.mSampleRate;
        }
            break;
        case kAudioFileStreamProperty_DataOffset: {
            UInt32 typeSize = sizeof(SInt64);
            AudioFileStreamGetProperty(_streamParser, propertyID, &typeSize, &_audioDataOffset);
        }
            break;
        default:
            break;
    }
}

- (void)_streamParserFoundPackets:(UInt32)inNumberBytes numberOfPackets:(UInt32)inNumberPackets inputData:(const void *)inFillBuffer packetDescriptions:(AudioStreamPacketDescription * __nullable)inPacketDescriptions {
    if ( _foundPackets == nil )
        _foundPackets = NSMutableArray.array;
     
    BOOL isCompressed = inPacketDescriptions != NULL;
    if ( isCompressed ) {
        for ( UInt32 i = 0 ; i < inNumberPackets ; ++ i ) {
            AudioStreamPacketDescription packetDesc = inPacketDescriptions[i];
            SInt64 packetStart = packetDesc.mStartOffset;
            SInt64 packetSize = packetDesc.mDataByteSize;
            NSData *data = [NSData dataWithBytes:inFillBuffer + packetStart length:(NSUInteger)packetSize];
            APAudioContentPacket *packet = [APAudioContentPacket.alloc initWithData:data];
            _countOfBytesFoundPackets += packetSize;
            _nBytesTotalFoundPackets += packetSize;
            _nCountTotalFoundPackets += 1;
            [_foundPackets addObject:packet];
        }
    }
    else {
        UInt32 bytesPerPacket = _format.streamDescription->mBytesPerPacket;
        for ( UInt32 i = 0 ; i < inNumberPackets ; ++ i ) {
            SInt64 packetStart = i * bytesPerPacket;
            SInt64 packetSize = bytesPerPacket;
            // 对于WAV和FLAC等未压缩格式, 我们不需要任何数据包描述
            NSData *data = [NSData dataWithBytes:inFillBuffer + packetStart length:(NSUInteger)packetSize];
            APAudioContentPacket *packet = [APAudioContentPacket.alloc initWithData:data];
            _countOfBytesFoundPackets += packetSize;
            _nBytesTotalFoundPackets += packetSize;
            _nCountTotalFoundPackets += 1;
            [_foundPackets addObject:packet];
        }
    }
}

#pragma mark - mark

static void
_mAudioFileStream_PropertyListenerProc(
                                           void *                           inClientData,
                                           AudioFileStreamID                inAudioFileStream,
                                           AudioFileStreamPropertyID        inPropertyID,
                                           AudioFileStreamPropertyFlags *   ioFlags) {
    APAudioStreamParser *self = (__bridge APAudioStreamParser *)inClientData;
    [self _streamParserFoundProperty:inPropertyID flags:ioFlags];
}

static void
_mAudioFileStream_PacketsProc(
                                  void *                                    inClientData,
                                  UInt32                                    inNumberBytes,
                                  UInt32                                    inNumberPackets,
                                  const void *                              inFillBuffer,
                                  AudioStreamPacketDescription * __nullable inPacketDescriptions) {
    APAudioStreamParser *self = (__bridge APAudioStreamParser *)inClientData;
    [self _streamParserFoundPackets:inNumberBytes numberOfPackets:inNumberPackets inputData:inFillBuffer packetDescriptions:inPacketDescriptions];
}
@end
