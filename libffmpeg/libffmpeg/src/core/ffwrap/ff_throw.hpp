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
//  ff_throw.hpp
//  LWZFFmpegLib
//
//  Created by sj on 2025/5/22.
//

#ifndef FFAV_Throw_hpp
#define FFAV_Throw_hpp

#include <stdexcept>
#include <string>

namespace FFAV {

[[noreturn]]
inline void throw_error(const char* err_msg) {
    printf("ERROR: %s\n", err_msg);
    throw std::runtime_error(err_msg);
}

[[noreturn]]
inline void throw_error(const std::string& err_msg) {
    throw_error(err_msg.c_str());
}

[[noreturn]]
inline void throw_error_fmt(const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    printf("ERROR: %s\n", buf);
    throw std::runtime_error(buf);
}

}
#endif /* FFAV_Throw_hpp */
