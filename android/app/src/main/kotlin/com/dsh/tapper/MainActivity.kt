package com.dsh.tapper

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
    }

    /**
     * 按返回键退出（isFinishing=true）时，视为「停止运行 APP」：
     * 连同 [OverlayService.stopSchedulingFromAppExit] 一起停用全部定时任务。
     *
     * 注意：横竖屏旋转也会 destroy Activity，但此时 isFinishing=false，
     * 不会误关定时任务（旋转不应打扰后台常驻）。
     */
    override fun onDestroy() {
        if (isFinishing) {
            LogBus.add(applicationContext, "WARN", "检测到：按返回键退出应用，正在停用全部定时任务")
            OverlayService.stopSchedulingFromAppExit(applicationContext)
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(TapperPlugin())
    }

    /**
     * Android 13(API 33) 起通知需要运行时授权。
     * 前台服务本身不依赖该权限也能运行，但通知被隐藏会降低「常驻」的可靠性
     * （部分厂商 ROM 对无可见通知的后台服务回收更激进），因此主动申请一次。
     */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFICATIONS
            )
        }
    }

    companion object {
        private const val REQ_NOTIFICATIONS = 0x5402
    }
}
