package io.chameleon.ultra

import io.flutter.embedding.android.FlutterActivity
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins
import com.polidea.rxandroidble2.exceptions.BleException

import android.os.Bundle
import android.view.InputDevice
import android.view.MotionEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity: FlutterActivity() {
    // Wear OS rotary input (rotating bezel / crown). Flutter ignores non-pointer
    // motion sources, so forward them to Dart. Never fires on phones.
    private var rotarySink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "io.chameleon.ultra/rotary")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    rotarySink = events
                }

                override fun onCancel(arguments: Any?) {
                    rotarySink = null
                }
            })
    }

    override fun dispatchGenericMotionEvent(ev: MotionEvent): Boolean {
        if (ev.action == MotionEvent.ACTION_SCROLL &&
            ev.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)
        ) {
            rotarySink?.success(-ev.getAxisValue(MotionEvent.AXIS_SCROLL).toDouble())
            return true
        }
        return super.dispatchGenericMotionEvent(ev)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RxJavaPlugins.setErrorHandler { throwable ->
            if (throwable is UndeliverableException && throwable.cause is BleException) {
                return@setErrorHandler // ignore BleExceptions since we do not have subscriber
            } else {
                throw throwable
            }
        }
    }
}
