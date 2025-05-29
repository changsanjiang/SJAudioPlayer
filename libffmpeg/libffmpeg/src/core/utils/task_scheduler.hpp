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

#ifndef FFMPEG_HARMONY_OS_TASKSCHEDULER_H
#define FFMPEG_HARMONY_OS_TASKSCHEDULER_H

#include <future>
#include <mutex>
#include <memory>
#include <functional>
#include <condition_variable>

namespace FFAV {

class TaskScheduler {
public:
    using Task = std::function<void()>;
    static std::shared_ptr<TaskScheduler> scheduleTask(Task task, int delay_in_seconds);
    
    // 尝试取消任务, 取消成功后返回 true, 如果任务已经执行则返回 false;
    bool tryCancel();
    // 等待任务完成, 如果任务已取消或执行完成则直接返回;
    void wait();
    
private:
    std::mutex mtx;
    std::condition_variable cv;
    
    Task task;
    int delay_in_seconds;
    std::future<void> future;
    bool is_cancelled { false };
    bool has_started { false };
    bool has_finished { false };
};

}

#endif //FFMPEG_HARMONY_OS_TASKSCHEDULER_H
