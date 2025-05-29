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

#include "task_scheduler.hpp"
#include <chrono>
#include <thread>

namespace FFAV {

std::shared_ptr<TaskScheduler> TaskScheduler::scheduleTask(Task task, int delay_in_seconds) {
    std::shared_ptr<TaskScheduler> scheduler = std::make_shared<TaskScheduler>();
    scheduler->task = task;
    scheduler->delay_in_seconds = delay_in_seconds;
    scheduler->future = std::async(std::launch::async, [scheduler] {
        std::this_thread::sleep_for(std::chrono::seconds(scheduler->delay_in_seconds));
        {
            std::lock_guard<std::mutex> lock(scheduler->mtx);
            if (scheduler->is_cancelled || scheduler->has_started) {
                return;
            }
            scheduler->has_started = true;
        }

        scheduler->task();

        {
            std::lock_guard<std::mutex> lock(scheduler->mtx);
            scheduler->has_finished = true;
        }

        scheduler->cv.notify_all(); 
    });
    return scheduler;
}

bool TaskScheduler::tryCancel() {
    std::lock_guard<std::mutex> lock(mtx);
    if ( has_started || has_finished ) {
        return false;
    }
    is_cancelled = true;
    return true;
}

void TaskScheduler::wait() {
    std::unique_lock<std::mutex> lock(mtx);
    cv.wait(lock, [this] { return has_finished || is_cancelled; });
}

}
