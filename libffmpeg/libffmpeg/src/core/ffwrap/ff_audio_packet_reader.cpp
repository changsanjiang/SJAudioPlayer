/**
    This file is part of @sj/ffmpeg.
    
    @sj/ffmpeg is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    @sj/ffmpeg is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License
    along with @sj/ffmpeg. If not, see <http://www.gnu.org/licenses/>.
 * */
//
//  AudioPacketReader.cpp
//  LWZFFmpegLib
//
//  Created by sj on 2025/5/16.
//

#include "ff_audio_packet_reader.hpp"
#include "ff_media_reader.hpp"
#include "ff_includes.hpp"
#include "ff_throw.hpp"

namespace FFAV {

AudioPacketReader::AudioPacketReader() {
    
}

AudioPacketReader::~AudioPacketReader() {
    reset();
}

void AudioPacketReader::prepare(const std::string &url, const std::map<std::string, std::string>& http_options) {
    std::lock_guard<std::mutex> lock(_mtx);
    if ( _read_thread ) {
        throw_error("AudioPacketReader::prepare - AudioPacketReader is already prepared.");
    }
    
    _url = url;
    _http_options = http_options;
    
    // 启动读取线程
    _read_thread = std::make_unique<std::thread>(&AudioPacketReader::ReadLoop, this);
}

void AudioPacketReader::start() {
    // 设置标记并通知读取线程
    _state.store(State::Reading);
    _cv.notify_all();
}

void AudioPacketReader::seekTo(int64_t seek_position) {
    // 设置seek位置并通知读取线程
    if ( _req_seek_time.exchange(seek_position) != seek_position ) {
        _cv.notify_all();
    }
}

void AudioPacketReader::stop() {
    // 设置标记并通知读取线程停止读取
    _state.store(State::Stopped);
    _cv.notify_all();
}

void AudioPacketReader::reset() {
    // 停止读取
    stop();
    
    std::unique_ptr<std::thread> read_thread;
    {
        std::lock_guard<std::mutex> lock(_mtx);
        if ( _media_reader ) {
            _media_reader->setInterrupted();
        }
        
        if ( _read_thread ) {
            read_thread = std::move(_read_thread);
        }
    }
    
    // 等待线程退出
    if ( read_thread && read_thread->joinable() ) {
        read_thread->join();
    }
    
    std::lock_guard<std::mutex> lock(_mtx);
    
    if ( _media_reader ) {
        delete _media_reader;
        _media_reader = nullptr;
    }
    
    // 重置所有状态
    _url.clear();
    _state.store(State::Pending);
    _stream_index = AVERROR_STREAM_NOT_FOUND;
    _req_seek_time.store(AV_NOPTS_VALUE);
    _seeking_time = AV_NOPTS_VALUE;
    _reached_eof = false;
    _packet_buffer_full.store(false);
    _ff_err.store(0);
}

void AudioPacketReader::setPacketBufferFull(bool is_full) {
    if ( _packet_buffer_full.exchange(is_full) != is_full ) {
        _cv.notify_all();
    }
}

void AudioPacketReader::setAudioStreamReadyCallback(AudioPacketReader::StreamReadyCallback callback) {
    _on_audio_stream_ready_callback = callback;
}

void AudioPacketReader::setReadPacketCallback(ReadPacketCallback callback) {
    _on_read_packet_callback = callback;
}

void AudioPacketReader::setErrorCallback(AudioPacketReader::ErrorCallback callback) {
    _on_error_callback = callback;
}

int AudioPacketReader::getError() {
    return _ff_err.load();
}

void AudioPacketReader::ReadLoop() {
    int ret = 0;
    {
        std::unique_lock<std::mutex> lock(_mtx);
        if ( _state.load() == State::Stopped ) { // check stop state
            return;
        }
        
        // init reader
        _media_reader = new MediaReader();
        lock.unlock();
        ret = _media_reader->open(_url, _http_options); // thread blocked; 可能会请求网络或文件io等, 这是个耗时操作;
        
        // re_lock
        lock.lock();
        if ( _state.load() == State::Stopped ) { // recheck stop state
            return;
        }
        
        if ( ret < 0 ) {
            _ff_err.store(ret);
            lock.unlock();
            if ( _on_error_callback ) _on_error_callback(this, ret); // notify error
            return;
        }
        
        AVStream* audio_stream = _media_reader->getBestStream(AVMEDIA_TYPE_AUDIO);
        if ( audio_stream == nullptr ) {
            ret = AVERROR_STREAM_NOT_FOUND;
            _ff_err.store(ret);
            lock.unlock();
            if ( _on_error_callback ) _on_error_callback(this, ret); // notify error
            return;
        }
        
        _stream_index = audio_stream->index;

        // open and init successful
        lock.unlock();
        if ( _on_audio_stream_ready_callback ) _on_audio_stream_ready_callback(this, audio_stream); // notify ready
    }
    
    // handle seek & read pkts
    
    AVPacket* pkt = av_packet_alloc();
    bool should_seek;
    bool should_restart;
    bool should_exit;
    bool error_occurred;
    
    do {
restart:
        ret = 0;
        should_seek = false;
        should_restart = false;
        should_exit = false;
        error_occurred = false;
        
        // wait conditions
        {
            std::unique_lock<std::mutex> lock(_mtx);
            _cv.wait(lock, [&] {
                // check state
                switch ( _state.load() ) {
                    case State::Pending: return false;
                    case State::Stopped: return true; // should read pkts or stop
                    case State::Reading: {
                        // check seek req
                        if ( _req_seek_time.load() != AV_NOPTS_VALUE || _seeking_time != AV_NOPTS_VALUE ) {
                            return true;
                        }
                        
                        return !_reached_eof && !_packet_buffer_full;
                    }
                }
            });
            
            // 确认状态是否需要退出线程
            if ( _state.load() == State::Stopped ) {
                should_exit = true;
            }
            // 确认是否需要seek
            else if ( _req_seek_time.load() != AV_NOPTS_VALUE ) {
                _seeking_time = _req_seek_time.exchange(AV_NOPTS_VALUE);
                should_seek = true;
            }
        }
        
        if ( should_exit ) {
            goto exit_thread;
        }
        
        // handle seek
        if ( should_seek ) {
            ret = _media_reader->seek(_seeking_time, -1); // thread blocked;  可能会请求网络或文件io等, 这是个耗时操作;
            
            // re_lock
            std::unique_lock<std::mutex> lock(_mtx);
            if ( _state.load() == State::Stopped ) { // recheck stop state
                should_exit = true;
            }
            // recheck seek req
            else if ( checkSeekReq() ) {
                should_restart = true; // reseek
            }
            // eof
            else if ( ret == AVERROR_EOF ) {
                // nothing
            }
            // error
            else if ( ret < 0 ) {
                _ff_err.store(ret);
                error_occurred = true;
                lock.unlock();
                if ( _on_error_callback ) _on_error_callback(this, ret); // notify error
            }
            // seek finished
            else {
                // reset flags
                _reached_eof = false;
            }
        }
        
        if ( should_exit || error_occurred ) {
            goto exit_thread;
        }
        
        if ( should_restart ) {
            goto restart;
        }
         
        // read packet
        av_packet_unref(pkt);
        ret = _media_reader->readPacket(pkt); // thread blocked;  可能会请求网络或文件io等, 这是个耗时操作;
        {
            std::unique_lock<std::mutex> lock(_mtx);
            // recheck stop
            if ( _state.load() == State::Stopped ) { // recheck stop state
                should_exit = true;;
            }
            // recheck seek req
            else if ( checkSeekReq() ) {
                should_restart = true; // reseek
            }
            // read success
            else if ( ret == 0 ) {
                if ( pkt->stream_index == _stream_index ) {
                    bool should_flush = _seeking_time != AV_NOPTS_VALUE;
                    if ( should_flush ) {
                        _seeking_time = AV_NOPTS_VALUE;
                    }
                    
                    lock.unlock();
                    if ( _on_read_packet_callback ) _on_read_packet_callback(this, pkt, should_flush); // notify read new packet
                }
            }
            // read eof
            else if ( ret == AVERROR_EOF ) {
                bool should_flush = _seeking_time != AV_NOPTS_VALUE;
                if ( should_flush ) {
                    _seeking_time = AV_NOPTS_VALUE;
                }
                
                // read eof
                _reached_eof = true;
                lock.unlock();
                if ( _on_read_packet_callback ) _on_read_packet_callback(this, nullptr, should_flush); // notify eof
            }
            // ret < 0;
            // read error
            else {
                _ff_err.store(ret);
                error_occurred = true;
                lock.unlock();
                if ( _on_error_callback ) _on_error_callback(this, ret); // notify error
            }
        }
        
        if ( should_exit || error_occurred ) {
            goto exit_thread;
        }
    } while (true);
    
exit_thread:
    av_packet_free(&pkt);
}

/// 需要seek时返回true;
bool AudioPacketReader::checkSeekReq() {
    int64_t req = _req_seek_time.load();
    if ( req != AV_NOPTS_VALUE ) {
        // 当 req == seeking 时 (重复请求) 不需要再次 seek 了;
        if ( req == _seeking_time ) {
            _req_seek_time.exchange(AV_NOPTS_VALUE);
            return false;
        }
        return true;
    }
    return false;
}

}
