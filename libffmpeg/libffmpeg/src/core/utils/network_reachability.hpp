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
// Created on 2025/3/3.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef FFAV_NetworkReachability_hpp
#define FFAV_NetworkReachability_hpp

#include "stdint.h"
#include <functional>

namespace FFAV {

class NetworkReachability final {
public:
    enum class Status {
        UNAVAILABLE,
        AVAILABLE,
        LOST
    };

    static constexpr uint32_t UnregisteredCallbackId = static_cast<uint32_t>(-1);
    using StatusChangeCallback = std::function<void(Status status)>;

    static Status getStatus();
    
    static uint32_t addStatusChangeCallback(StatusChangeCallback callback);
    static void removeStatusChangeCallback(uint32_t callback_id);

private:
    NetworkReachability() = delete;
    ~NetworkReachability() = delete;
    NetworkReachability(const NetworkReachability&) = delete;
    NetworkReachability& operator=(const NetworkReachability&) = delete;
};

}

#endif //FFAV_NetworkReachability_hpp
