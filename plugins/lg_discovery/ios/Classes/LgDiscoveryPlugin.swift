import Flutter
import Foundation
import UIKit

/// iOS discovery helper.
///
/// Raw SSDP needs Apple's multicast entitlement, so Bonjour browsing for
/// `_lg-mrt._tcp` is the path that works without an entitlement. The service
/// is resolved to an IPv4 address where possible so the Dart layer can hand
/// the host straight to the SSAP client.
public class LgDiscoveryPlugin: NSObject, FlutterPlugin {
  private var browser: NetServiceBrowser?
  private var services: [NetService] = []
  private var resolved: [[String: Any]] = []
  private var pendingResult: FlutterResult?
  private var timeoutTimer: Timer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.smartremote/lg_discovery",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(LgDiscoveryPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "acquireMulticastLock", "releaseMulticastLock":
      // iOS has no multicast lock; raw multicast is gated by an entitlement,
      // not by a runtime lock.
      result(nil)
    case "browseBonjour":
      let arguments = call.arguments as? [String: Any]
      let timeoutMs = (arguments?["timeoutMs"] as? NSNumber)?.intValue ?? 4000
      startBrowse(timeoutMs: timeoutMs, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startBrowse(timeoutMs: Int, result: @escaping FlutterResult) {
    finish()
    pendingResult = result
    resolved = []
    services = []

    let browser = NetServiceBrowser()
    browser.delegate = self
    self.browser = browser
    browser.searchForServices(ofType: "_lg-mrt._tcp.", inDomain: "local.")

    let interval = max(Double(timeoutMs) / 1000.0, 0.2)
    timeoutTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
      [weak self] _ in
      self?.finish()
    }
  }

  /// Completes the pending call exactly once. Any services that never resolved
  /// are discarded rather than delaying the result past the caller's timeout.
  private func finish() {
    timeoutTimer?.invalidate()
    timeoutTimer = nil

    browser?.delegate = nil
    browser?.stop()
    browser = nil

    for service in services {
      service.delegate = nil
      service.stop()
    }
    services = []

    let result = pendingResult
    pendingResult = nil
    if let result = result {
      result(resolved)
    }
    resolved = []
  }

  private static func ipv4Address(from addresses: [Data]?) -> String? {
    guard let addresses = addresses else { return nil }

    for data in addresses {
      guard data.count >= MemoryLayout<sockaddr_in>.size else { continue }

      let address = data.withUnsafeBytes { raw -> sockaddr_in? in
        guard let base = raw.baseAddress else { return nil }
        let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
        guard family == sa_family_t(AF_INET) else { return nil }
        return base.assumingMemoryBound(to: sockaddr_in.self).pointee
      }

      guard let sockaddrIn = address else { continue }
      var sin = sockaddrIn.sin_addr
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      if inet_ntop(AF_INET, &sin, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
        return String(cString: buffer)
      }
    }
    return nil
  }
}

extension LgDiscoveryPlugin: NetServiceBrowserDelegate {
  public func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didFind service: NetService,
    moreComing: Bool
  ) {
    services.append(service)
    service.delegate = self
    service.resolve(withTimeout: 2.0)
  }

  public func netServiceBrowser(
    _ browser: NetServiceBrowser,
    didNotSearch errorDict: [String: NSNumber]
  ) {
    // Bonjour is unavailable (for example local network access was denied).
    // Return what we have rather than leaving the caller waiting.
    finish()
  }
}

extension LgDiscoveryPlugin: NetServiceDelegate {
  public func netServiceDidResolveAddress(_ sender: NetService) {
    let rawHost = sender.hostName?
      .trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
    let host = LgDiscoveryPlugin.ipv4Address(from: sender.addresses)
      ?? (rawHost.isEmpty ? "" : rawHost)
    guard !host.isEmpty else { return }

    let duplicate = resolved.contains {
      ($0["host"] as? String) == host && ($0["name"] as? String) == sender.name
    }
    guard !duplicate else { return }

    var entry: [String: Any] = ["name": sender.name, "host": host]
    if sender.port > 0 {
      entry["port"] = sender.port
    }
    resolved.append(entry)
  }

  public func netService(
    _ sender: NetService,
    didNotResolve errorDict: [String: NSNumber]
  ) {
    // Skip this service; the remaining ones and the deadline still apply.
  }
}
