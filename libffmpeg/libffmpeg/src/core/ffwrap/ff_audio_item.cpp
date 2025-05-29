//
// Created on 2025/4/28.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#include "ff_audio_item.hpp"
#include <stdint.h>
#include "ff_audio_packet_reader.hpp"
#include "ff_audio_transcoder.hpp"
#include "../utils/network_reachability.hpp"
#include "../utils/task_scheduler.hpp"

namespace FFAV {

AudioItem::AudioItem(const std::string& url, const AudioItem::Options& options):
    _url(url),
    _http_options(options.http_options),
    _network_status_change_callback_id(NetworkReachability::UnregisteredCallbackId),
    _start_time_pos(options.start_time_pos > 0 ? options.start_time_pos : AV_NOPTS_VALUE),
    _output_sample_rate(options.output_sample_rate),
    _output_sample_format(options.output_sample_format),
    _output_channels(options.output_channels)
{
    
}

AudioItem::~AudioItem() {
    std::unique_lock<std::mutex> lock(mtx);

    if ( _network_status_change_callback_id != NetworkReachability::UnregisteredCallbackId ) {
        NetworkReachability::removeStatusChangeCallback(_network_status_change_callback_id);
    }
    
    if ( _reset_reader_task ) {
        _reset_reader_task->tryCancel();
        _reset_reader_task.reset();
    }
    
    if ( _reader ) {
        delete _reader;
        _reader = nullptr;
    }
    
    if ( _transcoder ) {
        delete _transcoder;
        _transcoder = nullptr;
    }
}

void AudioItem::prepare() {
    std::unique_lock<std::mutex> lock(mtx);
    if ( _reader ) { // return if created
        return;
    }
    
    _reader = new AudioPacketReader();
    _reader->setAudioStreamReadyCallback(std::bind(&AudioItem::onStreamReady, this, std::placeholders::_1, std::placeholders::_2));
    _reader->setReadPacketCallback(std::bind(&AudioItem::onReadPacket, this, std::placeholders::_1, std::placeholders::_2, std::placeholders::_3));
    _reader->setErrorCallback(std::bind(&AudioItem::onReadError, this, std::placeholders::_1, std::placeholders::_2));
    _reader->prepare(_url, _http_options);
}

void AudioItem::seekTo(int64_t time) {
    if ( time < 0 ) time = 0;
    
    std::unique_lock<std::mutex> lock(mtx);
    if ( !_reader ) { // prepare if not created
        _start_time_pos = time;
        lock.unlock();
        prepare();
        return;
    }
    
    if ( _ff_err.load() < 0 ) { // return if err
        return;
    }
    
    _seeking = true;
    _start_time_pos = time;

    if ( _reader->getError() < 0 ) { // reset if reader err
        if ( _reset_reader_task ) {
            _reset_reader_task->tryCancel();
            _reset_reader_task.reset();
        }
        
        _reader->reset();
        _reader->prepare(_url, _http_options);
        return;
    }
    
    _reader->seekTo(time);
}

int AudioItem::tryTranscode(void **out_data, int frame_capacity, int64_t *out_pts, bool *out_eof) {
    std::unique_lock<std::mutex> lock(mtx);
    if ( !_transcoder || _seeking ) {
        return 0;
    }
    
    int ret = _transcoder->tryTranscode(out_data, frame_capacity, out_pts, out_eof);
    if ( !_transcoder->isPacketBufferFull() ) {
        _reader->setPacketBufferFull(false);
    }
    return ret;
}

void AudioItem::setStreamReadyCallback(StreamReadyCallback callback) {
    std::unique_lock<std::mutex> lock(mtx);
    _on_stream_ready_callback = callback;
}

void AudioItem::setBufferedTimeChangeCallback(BufferedTimeChangeCallback callback) {
    std::unique_lock<std::mutex> lock(mtx);
    _on_buffered_time_change_callback = callback;
}

void AudioItem::setErrorCallback(ErrorCallback callback) {
    std::unique_lock<std::mutex> lock(mtx);
    _on_error_callback = callback;
}

int AudioItem::getOutputSampleRate() {
    return _output_sample_rate;
}

AVSampleFormat AudioItem::getOutputSampleFormat() {
    return _output_sample_format;
}

int AudioItem::getOutputChannels() {
    return _output_channels;
}

int AudioItem::getError() {
    return _ff_err.load();
}

void AudioItem::onStreamReady(AudioPacketReader *reader, AVStream *stream) {
    std::unique_lock<std::mutex> lock(mtx);
    if ( _transcoder ) { // reader reseted;
        int64_t seek_time;
        if ( _seeking ) { // 说明用户执行了 seek 操作, 是在 seek 中触发的 reset;
            seek_time = _start_time_pos;     // 需要从seek的位置开始读取数据包;
            _flush_packet_only = false;
        }
        else {                                        // 否则, 是由 _reset_reader_task 或网络状态回调触发的 reset;
            int64_t end_pts = _transcoder->getFifoEndPts(); // 需要尽量从当前 fifo 的尾部开始准备;
            seek_time = end_pts != AV_NOPTS_VALUE ? av_rescale_q(end_pts, (AVRational){ 1, _output_sample_rate }, AV_TIME_BASE_Q) : AV_NOPTS_VALUE;
            // 确定是否仅清空 pkt 相关的缓存;
            // 如果 fifo 记录的位置有效, 则设置标记 _flush_packet_only 为 true, 将来告诉 _transcoder 执行 flush 操作时, 仅需要清空 pkt 相关的缓存, 后续转码的数据需要对齐到 fifo 中;
            _flush_packet_only = seek_time != AV_NOPTS_VALUE;
        }
        
        lock.unlock();
        if ( seek_time != AV_NOPTS_VALUE ) reader->seekTo(seek_time);
        reader->start();
        return;
    }
    
    int ret = 0;
    auto transcoder = new AudioTranscoder();
    ret = transcoder->init(stream, _output_sample_rate, _output_sample_format, _output_channels);
    if ( ret < 0 ) {
        _ff_err.store(ret);
        lock.unlock();
        delete transcoder;
        if ( _on_error_callback ) _on_error_callback(ret);
        return;
    }
    _transcoder = transcoder;
    _stream_time_base = stream->time_base;
    _duration = stream->duration;
    
    lock.unlock();
    reader->start();
    if ( _on_stream_ready_callback ) _on_stream_ready_callback(_duration, _stream_time_base);
}

void AudioItem::onReadPacket(AudioPacketReader *reader, AVPacket *pkt, bool should_flush) { // eof 时 packet 为 nullptr;
    std::unique_lock<std::mutex> lock(mtx);
    if ( !should_flush && _seeking ) {
        return;
    }
    
    auto flush_mode = AudioTranscoder::FlushMode::None;
    if ( should_flush ) {
        flush_mode = _flush_packet_only ? AudioTranscoder::FlushMode::PacketOnly : AudioTranscoder::FlushMode::Full; // 确定是否需要仅清空 pkt 相关的缓存或全部缓存;
        _flush_packet_only = false;
        _seeking = false;
        _reader->setPacketBufferFull(false);
    }
    
    int ret = _transcoder->enqueue(pkt, flush_mode);
    if ( ret < 0 ) {
        _ff_err.store(ret);
        lock.unlock();
        if ( _on_error_callback ) _on_error_callback(ret);
        return;
    }
    
    if ( _transcoder->isPacketBufferFull() ) {
        _reader->setPacketBufferFull(true);
    }
    
    auto buffered_time = pkt != nullptr ? _transcoder->getLastPresentationPacketEndPts() : _duration;
    auto changed_buffered_time = false;
    if ( buffered_time != _buffered_time ) {
        _buffered_time = buffered_time;
        changed_buffered_time = true;
    }
    
    lock.unlock();
    if ( changed_buffered_time && _on_buffered_time_change_callback ) _on_buffered_time_change_callback(buffered_time, _stream_time_base);
}

void AudioItem::onReadError(AudioPacketReader *reader, int ff_err) {
    std::unique_lock<std::mutex> lock(mtx);
    if ( ff_err == AVERROR_DECODER_NOT_FOUND ||
         ff_err == AVERROR_DEMUXER_NOT_FOUND ||
         ff_err == AVERROR_PROTOCOL_NOT_FOUND ||
         ff_err == AVERROR_STREAM_NOT_FOUND ||
         ff_err == AVERROR_HTTP_UNAUTHORIZED ||
         ff_err == AVERROR_HTTP_FORBIDDEN ||
         ff_err == AVERROR_HTTP_NOT_FOUND ||
         ff_err == AVERROR_HTTP_OTHER_4XX ) {
        _ff_err.store(ff_err);
        lock.unlock();
        if ( _on_error_callback ) _on_error_callback(ff_err);
        return;
    }
    
    auto network_status = NetworkReachability::getStatus();
    if ( network_status != NetworkReachability::Status::AVAILABLE ) {
        if ( _network_status_change_callback_id == NetworkReachability::UnregisteredCallbackId ) {
            _network_status_change_callback_id = NetworkReachability::addStatusChangeCallback([&](NetworkReachability::Status network_status) {
                if ( network_status != NetworkReachability::Status::AVAILABLE ) {
                    return;
                }
                
                prepareReaderAgainIfError();
            });
        }
        return;
    }
    
    _reset_reader_task = TaskScheduler::scheduleTask([&] {
        prepareReaderAgainIfError();
    }, 2); // 2s
}

void AudioItem::prepareReaderAgainIfError() {
    std::unique_lock<std::mutex> lock(mtx);
    if ( _reader->getError() == 0 ) { // 错误返回0时, 表示已重置过, 此时直接 return 即可;
        return;
    }
    
    // prepare again
    _reader->reset();
    _reader->prepare(_url, _http_options);
}

}
