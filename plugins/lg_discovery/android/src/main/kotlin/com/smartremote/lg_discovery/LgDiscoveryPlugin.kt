package com.smartremote.lg_discovery

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Holds the Wi-Fi multicast lock for exactly one discovery sweep.
 *
 * Android drops multicast packets to apps that do not hold a MulticastLock, so
 * SSDP replies are unreliable without it. The lock is acquired by the Dart
 * sweep hook and released in a `finally`; it is also released when the engine
 * detaches, so a crashed sweep cannot leak it.
 */
class LgDiscoveryPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        releaseLock()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "acquireMulticastLock" -> result.success(acquireLock())
            "releaseMulticastLock" -> {
                releaseLock()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Returns true when a lock is held. Missing Wi-Fi hardware or a denied
     * permission is not fatal: the sweep still runs, and manual entry is always
     * available.
     */
    private fun acquireLock(): Boolean {
        val existing = multicastLock
        if (existing != null && existing.isHeld) return true

        return try {
            val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return false
            val lock = wifi.createMulticastLock(LOCK_TAG)
            lock.setReferenceCounted(false)
            lock.acquire()
            multicastLock = lock
            true
        } catch (_: SecurityException) {
            false
        } catch (_: UnsupportedOperationException) {
            false
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun releaseLock() {
        val lock = multicastLock
        multicastLock = null
        try {
            if (lock != null && lock.isHeld) lock.release()
        } catch (_: RuntimeException) {
            // Already released or the Wi-Fi service went away.
        }
    }

    companion object {
        private const val CHANNEL = "com.smartremote/lg_discovery"
        private const val LOCK_TAG = "smart_remote_discovery"
    }
}
