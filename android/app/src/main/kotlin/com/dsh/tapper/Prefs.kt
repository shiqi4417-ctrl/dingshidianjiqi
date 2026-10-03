package com.dsh.tapper

import android.content.Context

/** 配置持久化：写入 SharedPreferences，进程/设备重启后仍生效。 */
object Prefs {
    private const val FILE = "scheduled_tapper"
    private const val KEY_CONFIG = "config_json"

    @Synchronized
    fun load(ctx: Context): Config =
        Config.fromJson(ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getString(KEY_CONFIG, null))

    @Synchronized
    fun save(ctx: Context, cfg: Config) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CONFIG, cfg.toJson().toString())
            .apply()
    }

    /**
     * 同步写盘版 [save]。
     *
     * 背景（修复 BUG）：普通配置写入用 `.apply()`（异步落盘）在日常没问题；但「退出 APP 时
     * 复位定时任务」这一步发生在进程即将结束/被杀的时刻，异步的 `.apply()` 可能还没真正写到
     * 磁盘进程就没了，导致下次进入时仍是开启状态。这里用 `.commit()`（同步写盘）确保写盘完成。
     */
    @Synchronized
    fun saveSync(ctx: Context, cfg: Config) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CONFIG, cfg.toJson().toString())
            .commit()
    }
}
