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

#include "network_reachability.hpp"
#include <stdexcept>
#include <atomic>
#include <cstdint>
#include <map>
#include <mutex>

namespace FFAV {

class NetworkReachabilityImpl;

class NetworkListener {
public:
    NetworkListener() = default;
    virtual ~NetworkListener() = default;
    virtual void setImpl(NetworkReachabilityImpl *impl) { }
};

class NetworkReachabilityImpl {
public:
    NetworkReachabilityImpl();
    NetworkReachability::Status getStatus();
    void setStatus(NetworkReachability::Status status);

    uint32_t addStatusChangeCallback(NetworkReachability::StatusChangeCallback callback);
    void removeStatusChangeCallback(uint32_t callback_id);
    
private:
    
    std::atomic<NetworkReachability::Status> _status { NetworkReachability::Status::UNAVAILABLE };
    std::mutex _mtx;
    std::map<uint32_t, NetworkReachability::StatusChangeCallback> _callbacks;
    uint32_t _next_callback_id { 0 };
    std::unique_ptr<NetworkListener> _listener;
};

} // namespace FFAV

#if defined (FFAV_PLATFORM_OHOS)
#include <network/netmanager/net_connection_type.h>
#include <network/netmanager/net_connection.h>

namespace FFAV {

class OHOSNetworkListener: public NetworkListener {
public:
    OHOSNetworkListener();
    ~OHOSNetworkListener();
    
    void setImpl(NetworkReachabilityImpl *impl) override;

private:
    /** 网络可用回调。 */
    static void OnNetworkAvailable(NetConn_NetHandle *netHandle);
    /** 网络断开回调。*/
    static void OnNetLost(NetConn_NetHandle *netHandle);
    /** 网络不可用回调，在指定的超时时间内网络未激活时触发该回调，如果未设置超时时间则不会触发该回调。*/
    static void OnNetUnavailable();
    
    static NetworkReachabilityImpl *_impl;
    
    uint32_t _oh_id;
};

NetworkReachabilityImpl* OHOSNetworkListener::_impl = nullptr;

OHOSNetworkListener::OHOSNetworkListener(): NetworkListener() {
    if ( _impl ) {
        throw std::runtime_error("NetworkReachabilityImpl is already initialized"); 
    }
    
    NetConn_NetConnCallback netConnCallback = { nullptr };
    netConnCallback.onNetworkAvailable = OnNetworkAvailable;
    netConnCallback.onNetUnavailable = OnNetUnavailable;
    netConnCallback.onNetLost = OnNetLost;
    OH_NetConn_RegisterDefaultNetConnCallback(&netConnCallback, &_oh_id);
}

OHOSNetworkListener::~OHOSNetworkListener() {
    OH_NetConn_UnregisterNetConnCallback(_oh_id);
}

void OHOSNetworkListener::setImpl(NetworkReachabilityImpl *impl) {
   _impl = impl;
}

void OHOSNetworkListener::OnNetworkAvailable(NetConn_NetHandle *netHandle) {
    if ( _impl ) {
        _impl->setStatus(NetworkReachability::Status::AVAILABLE);
    }
}

void OHOSNetworkListener::OnNetLost(NetConn_NetHandle *netHandle) {
    if ( _impl ) {
        _impl->setStatus(NetworkReachability::Status::LOST);
    }
}

void OHOSNetworkListener::OnNetUnavailable() {
    if ( _impl ) {
        _impl->setStatus(NetworkReachability::Status::UNAVAILABLE);
    }
}

} // namespace FFAV
#endif


#if defined (FFAV_PLATFORM_IOS)
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>
#import <dispatch/dispatch.h>

namespace FFAV {

class IOSNetworkListener : public NetworkListener {
public:
    IOSNetworkListener();
    ~IOSNetworkListener();
    
    void setImpl(NetworkReachabilityImpl *impl) override;

private:
    static void ReachabilityCallback(
        SCNetworkReachabilityRef target,
        SCNetworkReachabilityFlags flags,
        void* info
    );
    
    void handleFlags(SCNetworkReachabilityFlags flags);

    SCNetworkReachabilityRef _reachability = nullptr;
    dispatch_queue_t _reachability_queue = nullptr;
    NetworkReachabilityImpl *_impl = nullptr;
};

IOSNetworkListener::IOSNetworkListener(): NetworkListener() {
    sockaddr_in addr = {};
    addr.sin_len = sizeof(sockaddr_in);
    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    _reachability = SCNetworkReachabilityCreateWithAddress(nullptr, (sockaddr*)&addr);
    if (!_reachability) return;

    SCNetworkReachabilityContext context = {};
    context.version = 0;
    context.info = this;
    context.retain = nullptr;
    context.release = nullptr;
    context.copyDescription = nullptr;

    if ( !SCNetworkReachabilitySetCallback(_reachability, ReachabilityCallback, &context) ) {
        CFRelease(_reachability);
        _reachability = nullptr;
        return;
    }

    _reachability_queue = dispatch_queue_create("ffav.reachability", DISPATCH_QUEUE_SERIAL);
    
    if ( !SCNetworkReachabilitySetDispatchQueue(_reachability, _reachability_queue) ) {
        // 失败清理资源
        SCNetworkReachabilitySetCallback(_reachability, nullptr, nullptr);
        CFRelease(_reachability);
        _reachability = nullptr;
        _reachability_queue = nullptr;
        return;
    }
}

IOSNetworkListener::~IOSNetworkListener() {
    if ( _reachability ) {
        SCNetworkReachabilitySetDispatchQueue(_reachability, nullptr);
        SCNetworkReachabilitySetCallback(_reachability, nullptr, nullptr);
        CFRelease(_reachability);
        _reachability = nullptr;
    }

    if ( _reachability_queue ) {
        dispatch_release(_reachability_queue); // 仅适用于非 ARC 下的 Objective-C++
        _reachability_queue = nullptr;
    }
}

void IOSNetworkListener::setImpl(NetworkReachabilityImpl *impl) {
    _impl = impl;
    
    if ( impl ) {
        // 手动触发一次初始状态判断
        SCNetworkReachabilityFlags flags;
        if ( SCNetworkReachabilityGetFlags(_reachability, &flags) ) {
            handleFlags(flags);
        }
    }
}

void IOSNetworkListener::ReachabilityCallback(SCNetworkReachabilityRef,
                                                  SCNetworkReachabilityFlags flags,
                                                  void* info) {
    if ( info ) {
        static_cast<IOSNetworkListener*>(info)->handleFlags(flags);
    }
}

void IOSNetworkListener::handleFlags(SCNetworkReachabilityFlags flags) {
    if ( _impl ) {
        bool reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
        bool requiresConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
        
        if ( reachable && !requiresConnection ) {
            _impl->setStatus(NetworkReachability::Status::AVAILABLE);
        } else {
            _impl->setStatus(NetworkReachability::Status::UNAVAILABLE);
        }
    }
}

} // namespace FFAV

#endif


namespace FFAV {
 
NetworkReachabilityImpl::NetworkReachabilityImpl() {
#if defined (FFAV_PLATFORM_IOS)
    _listener = std::make_unique<IOSNetworkListener>();
    _listener->setImpl(this);
#elif defined (FFAV_PLATFORM_OHOS)
    _listener = std::make_unique<OHOSNetworkListener>();
    _listener->setImpl(this);
#endif
}

void NetworkReachabilityImpl::setStatus(NetworkReachability::Status status) {
    if ( _status.exchange(status) != status ) {
        std::map<uint32_t, NetworkReachability::StatusChangeCallback> copy_callbacks;
        {
            std::lock_guard<std::mutex> lock(_mtx);
            copy_callbacks = _callbacks;
        }
        
        for (const auto& pair : copy_callbacks) {
            pair.second(status);
        }
    }
}

NetworkReachability::Status NetworkReachabilityImpl::getStatus() {
    return _status.load();
}

uint32_t NetworkReachabilityImpl::addStatusChangeCallback(NetworkReachability::StatusChangeCallback callback) {
    std::lock_guard<std::mutex> lock(_mtx);
    int callback_id = _next_callback_id;
    _next_callback_id += 1;
    _callbacks[callback_id] = std::move(callback);
    return callback_id;
}

void NetworkReachabilityImpl::removeStatusChangeCallback(uint32_t callback_id) {
    std::lock_guard<std::mutex> lock(_mtx);
    _callbacks.erase(callback_id);
}

} // namespace FFAV


namespace FFAV {

static NetworkReachabilityImpl& SharedNetworkReachability() {
    static NetworkReachabilityImpl instance;
    return instance;
}

NetworkReachability::Status NetworkReachability::getStatus() {
    return SharedNetworkReachability().getStatus();
}

uint32_t NetworkReachability::addStatusChangeCallback(StatusChangeCallback callback) {
    return SharedNetworkReachability().addStatusChangeCallback(callback);
}

void NetworkReachability::removeStatusChangeCallback(uint32_t callback_id) {
    SharedNetworkReachability().removeStatusChangeCallback(callback_id);
}

} // namespace FFAV
