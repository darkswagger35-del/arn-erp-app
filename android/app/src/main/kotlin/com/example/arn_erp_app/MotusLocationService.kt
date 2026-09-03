package com.example.arn_erp_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import kotlin.math.max

class MotusLocationService : Service(), LocationListener {

    companion object {
        private const val CHANNEL_ID = "motus_live_location"
        private const val NOTIFICATION_ID = 4702
        private const val PREFS = "motus_native_location"
        private const val MIN_PUSH_INTERVAL_MS = 30_000L
        private const val GPS_INTERVAL_MS = 30_000L
        private const val NETWORK_INTERVAL_MS = 60_000L
        private const val GPS_DISTANCE_M = 20f
        private const val NETWORK_DISTANCE_M = 50f
    }

    private lateinit var locationManager: LocationManager
    private val networkExecutor = Executors.newSingleThreadExecutor()

    @Volatile private var lastPushElapsed = 0L
    @Volatile private var lastLocation: Location? = null

    private var supabaseUrl = ""
    private var apiKey = ""
    private var accessToken = ""
    private var refreshToken = ""

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        loadConfiguration(intent)

        if (!hasLocationPermission() ||
            supabaseUrl.isBlank() ||
            apiKey.isBlank() ||
            accessToken.isBlank()
        ) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(
            NOTIFICATION_ID,
            buildNotification("Canlı konum takibi aktif")
        )
        requestLocationUpdates()
        return START_STICKY
    }

    private fun loadConfiguration(intent: Intent?) {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val incomingUrl = intent?.getStringExtra("supabaseUrl").orEmpty()
        val incomingKey = intent?.getStringExtra("apiKey").orEmpty()
        val incomingAccess = intent?.getStringExtra("accessToken").orEmpty()
        val incomingRefresh = intent?.getStringExtra("refreshToken").orEmpty()

        if (incomingUrl.isNotBlank() && incomingKey.isNotBlank() && incomingAccess.isNotBlank()) {
            supabaseUrl = incomingUrl.trimEnd('/')
            apiKey = incomingKey
            accessToken = incomingAccess
            refreshToken = incomingRefresh

            prefs.edit()
                .putString("supabaseUrl", supabaseUrl)
                .putString("apiKey", apiKey)
                .putString("accessToken", accessToken)
                .putString("refreshToken", refreshToken)
                .apply()
        } else {
            supabaseUrl = prefs.getString("supabaseUrl", "").orEmpty().trimEnd('/')
            apiKey = prefs.getString("apiKey", "").orEmpty()
            accessToken = prefs.getString("accessToken", "").orEmpty()
            refreshToken = prefs.getString("refreshToken", "").orEmpty()
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @Suppress("MissingPermission")
    private fun requestLocationUpdates() {
        locationManager.removeUpdates(this)

        if (locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                GPS_INTERVAL_MS,
                GPS_DISTANCE_M,
                this,
                Looper.getMainLooper()
            )
        }

        if (locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
            locationManager.requestLocationUpdates(
                LocationManager.NETWORK_PROVIDER,
                NETWORK_INTERVAL_MS,
                NETWORK_DISTANCE_M,
                this,
                Looper.getMainLooper()
            )
        }

        // Servis başlar başlamaz mümkünse son bilinen konumu da gönder.
        val gps = runCatching {
            locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        }.getOrNull()
        val network = runCatching {
            locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        }.getOrNull()

        listOfNotNull(gps, network)
            .maxByOrNull { it.time }
            ?.let { onLocationChanged(it) }
    }

    override fun onLocationChanged(location: Location) {
        val previous = lastLocation
        // Aynı/çok eski noktaların gereksiz tekrarını azalt.
        if (previous != null && location.time < previous.time) return
        lastLocation = location

        val nowElapsed = SystemClock.elapsedRealtime()
        if (lastPushElapsed != 0L &&
            nowElapsed - lastPushElapsed < MIN_PUSH_INTERVAL_MS
        ) {
            return
        }
        lastPushElapsed = nowElapsed

        updateNotification("Son konum gönderiliyor…")
        networkExecutor.execute {
            val ok = pushLocation(location)
            if (ok) {
                updateNotification("Canlı takip aktif • son konum gönderildi")
            } else {
                updateNotification("Canlı takip aktif • bağlantı bekleniyor")
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) {
        if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) &&
            !locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        ) {
            updateNotification("Konum servisi kapalı")
        }
    }

    private fun pushLocation(location: Location): Boolean {
        if (postRpc(location, accessToken)) return true

        // Access token süresi dolduysa refresh token ile sessizce yenile ve tekrar dene.
        if (refreshToken.isNotBlank() && refreshSession()) {
            return postRpc(location, accessToken)
        }
        return false
    }

    private fun postRpc(location: Location, token: String): Boolean {
        var connection: HttpURLConnection? = null
        return try {
            val endpoint = URL("$supabaseUrl/rest/v1/rpc/technician_push_location_v1")
            connection = endpoint.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 12_000
            connection.readTimeout = 12_000
            connection.doOutput = true
            connection.setRequestProperty("apikey", apiKey)
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")

            val body = JSONObject().apply {
                put("p_latitude", location.latitude)
                put("p_longitude", location.longitude)
                if (location.hasAccuracy()) put("p_accuracy_m", location.accuracy.toDouble())
                else put("p_accuracy_m", JSONObject.NULL)
                if (location.hasSpeed()) put("p_speed_mps", max(0f, location.speed).toDouble())
                else put("p_speed_mps", JSONObject.NULL)
                if (location.hasBearing()) put("p_heading_deg", max(0f, location.bearing).toDouble())
                else put("p_heading_deg", JSONObject.NULL)
                put("p_source", "android-fgs")
            }

            connection.outputStream.use { stream ->
                stream.write(body.toString().toByteArray(Charsets.UTF_8))
            }

            val code = connection.responseCode
            code in 200..299
        } catch (_: Throwable) {
            false
        } finally {
            connection?.disconnect()
        }
    }

    private fun refreshSession(): Boolean {
        var connection: HttpURLConnection? = null
        return try {
            val endpoint = URL("$supabaseUrl/auth/v1/token?grant_type=refresh_token")
            connection = endpoint.openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 12_000
            connection.readTimeout = 12_000
            connection.doOutput = true
            connection.setRequestProperty("apikey", apiKey)
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")

            val body = JSONObject().put("refresh_token", refreshToken)
            connection.outputStream.use { stream ->
                stream.write(body.toString().toByteArray(Charsets.UTF_8))
            }

            if (connection.responseCode !in 200..299) return false

            val response = BufferedReader(
                InputStreamReader(connection.inputStream, Charsets.UTF_8)
            ).use { it.readText() }

            val json = JSONObject(response)
            val newAccess = json.optString("access_token")
            val newRefresh = json.optString("refresh_token", refreshToken)
            if (newAccess.isBlank()) return false

            accessToken = newAccess
            refreshToken = newRefresh

            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("accessToken", accessToken)
                .putString("refreshToken", refreshToken)
                .apply()
            true
        } catch (_: Throwable) {
            false
        } finally {
            connection?.disconnect()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "MOTUS Canlı Konum",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Tekniker mesai içi canlı konum takibi"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE else 0
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MOTUS konum takibi")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onDestroy() {
        runCatching { locationManager.removeUpdates(this) }
        networkExecutor.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
