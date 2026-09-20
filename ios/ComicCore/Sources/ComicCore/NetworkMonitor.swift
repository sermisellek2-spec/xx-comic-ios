import Foundation
#if canImport(Network)
import Network
#endif

public protocol NetworkMonitoring: AnyObject, Sendable {
    var isConnected: Bool { get }
    var isWifi: Bool { get }
    var onStatusChange: (@Sendable (_ isConnected: Bool, _ isWifi: Bool) -> Void)? { get set }
    func start()
    func stop()
}

#if canImport(Network)
public final class SystemNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.xxcomic.networkmonitor")
    private let lock = NSLock()
    private var _isConnected: Bool = true
    private var _isWifi: Bool = true
    public var onStatusChange: (@Sendable (_ isConnected: Bool, _ isWifi: Bool) -> Void)?

    public init() {
        self.monitor = NWPathMonitor()
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    public var isWifi: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isWifi
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            let connected = (path.status == .satisfied)
            let wifi = path.usesInterfaceType(.wifi)
            let changed = (connected != self._isConnected || wifi != self._isWifi)
            self._isConnected = connected
            self._isWifi = wifi
            let callback = self.onStatusChange
            self.lock.unlock()
            if changed {
                callback?(connected, wifi)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }
}
#endif

public final class MockNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected: Bool
    private var _isWifi: Bool
    public var onStatusChange: (@Sendable (_ isConnected: Bool, _ isWifi: Bool) -> Void)?

    public init(isConnected: Bool = true, isWifi: Bool = true) {
        self._isConnected = isConnected
        self._isWifi = isWifi
    }

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    public var isWifi: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isWifi
    }

    public func setStatus(isConnected: Bool, isWifi: Bool) {
        lock.lock()
        let changed = (isConnected != self._isConnected || isWifi != self._isWifi)
        self._isConnected = isConnected
        self._isWifi = isWifi
        let callback = self.onStatusChange
        lock.unlock()
        if changed {
            callback?(isConnected, isWifi)
        }
    }

    public func start() {}
    public func stop() {}
}
