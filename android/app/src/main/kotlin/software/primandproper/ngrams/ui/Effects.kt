package software.primandproper.ngrams.ui

import android.os.Build
import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.sin

/**
 * Whether the system has animations removed, Android's closest match to iOS's Reduce Motion. Compose already
 * finishes its own animations at once then; this is for the waits and moves the games time by hand.
 */
@Composable
fun reduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** What a haptic says happened. */
enum class Haptic {
    /** A letter or tile picked. */
    PICK,

    /** A hint taken. */
    HINT,

    /** A word found, a puzzle solved, or a star earned. */
    SUCCESS,

    /** A guess or word turned away. */
    ERROR,
}

/** Plays a [Haptic], or nothing when the system's touch feedback is off. */
@Composable
fun rememberHaptics(): (Haptic) -> Unit {
    val view = LocalView.current
    return remember(view) { { haptic -> view.performHapticFeedback(haptic.constant) } }
}

private val Haptic.constant: Int
    get() {
        // CONFIRM and REJECT arrived in Android 11; older versions get the nearest older effect.
        val modern = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
        return when (this) {
            Haptic.PICK -> HapticFeedbackConstants.KEYBOARD_TAP
            Haptic.HINT -> HapticFeedbackConstants.CLOCK_TICK
            Haptic.SUCCESS -> if (modern) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK
            Haptic.ERROR -> if (modern) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
        }
    }

/** Calls [onChange] each time [value] changes after the first composition, with the value before and after. */
@Composable
fun <T> OnChange(
    value: T,
    onChange: (old: T, new: T) -> Unit,
) {
    var last by remember { mutableStateOf(value) }
    val callback by rememberUpdatedState(onChange)
    LaunchedEffect(value) {
        if (value != last) {
            callback(last, value)
            last = value
        }
    }
}

/**
 * Shakes side to side whenever [trigger] goes up while [active], unless animations are removed. Views that take turns
 * shaking share one trigger and pass [active], so a view turning active never sees the trigger jump.
 */
fun Modifier.shake(
    trigger: Int,
    active: Boolean = true,
): Modifier =
    composed {
        val shake = remember { Animatable(0f) }
        val still = reduceMotion()
        val shaking by rememberUpdatedState(active && !still)
        LaunchedEffect(trigger) {
            if (trigger > 0 && shaking) {
                shake.snapTo(0f)
                shake.animateTo(1f, tween(400, easing = LinearEasing))
            }
        }
        graphicsLayer { translationX = 10.dp.toPx() * sin(shake.value * PI * 4).toFloat() }
    }

/** Hops up and lands, [delayMillis] after [trigger] changes, unless animations are removed. */
fun Modifier.hop(
    trigger: Int,
    delayMillis: Long,
): Modifier =
    composed {
        val lift = remember { Animatable(0f) }
        val first = remember { trigger }
        val still = reduceMotion()
        LaunchedEffect(trigger) {
            if (trigger != first && !still) {
                delay(delayMillis)
                lift.animateTo(18f, tween(150, easing = FastOutSlowInEasing))
                lift.animateTo(0f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMedium))
            }
        }
        graphicsLayer { translationY = -lift.value.dp.toPx() }
    }
