package io.flutter.plugin.platform;

import android.annotation.TargetApi;
import android.content.Context;
import android.hardware.display.DisplayManager;
import android.view.Display;
import android.view.inputmethod.InputMethodManager;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowDisplay;
import org.robolectric.shadows.ShadowDisplayManager;
import org.robolectric.shadows.ShadowInputMethodManager;

import static junit.framework.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.when;

@Config(manifest = Config.NONE, shadows = {ShadowInputMethodManager.class, ShadowDisplayManager.class, ShadowDisplay.class}, sdk = 27)
@RunWith(RobolectricTestRunner.class)
@TargetApi(27)
public class SingleViewPresentationTest {
    @Test
    public void returnsOuterContextInputMethodManager() {
        // There's a bug in Android Q caused by the IMM being instanced per display.
        // https://github.com/flutter/flutter/issues/38375. We need the context returned by
        // SingleViewPresentation to be consistent from its instantiation instead of defaulting to
        // what the system would have returned at call time.

        // It's not possible to set up the exact same conditions as the unit test in the bug here,
        // but we can make sure that we're wrapping the Context passed in at instantiation time and
        // returning the same InputMethodManager from it. This test passes in a Spy context instance
        // that initially returns a mock. Without the bugfix this test falls back to Robolectric's
        // system service instead of the spy's and fails.

        // Create an SVP under test with a Context that returns a local IMM mock.
        Context context = spy(RuntimeEnvironment.application);
        InputMethodManager expected = mock(InputMethodManager.class);
        when(context.getSystemService(Context.INPUT_METHOD_SERVICE)).thenReturn(expected);
        DisplayManager dm = (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
        SingleViewPresentation svp = new SingleViewPresentation(context, dm.getDisplay(0), null, null, null, false);

        // Get the IMM from the SVP's context.
        InputMethodManager actual = (InputMethodManager) svp.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);

        // This should be the mocked instance from construction, not the IMM from the greater
        // Android OS (or Robolectric's shadow, in this case).
        assertEquals(expected, actual);
    }

    @Test
    public void returnsOuterContextInputMethodManager_createDisplayContext() {
        // The IMM should also persist across display contexts created from the base context.

        // Create an SVP under test with a Context that returns a local IMM mock.
        Context context = spy(RuntimeEnvironment.application);
        InputMethodManager expected = mock(InputMethodManager.class);
        when(context.getSystemService(Context.INPUT_METHOD_SERVICE)).thenReturn(expected);
        Display display = ((DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE)).getDisplay(0);
        SingleViewPresentation svp = new SingleViewPresentation(context, display, null, null, null, false);

        // Get the IMM from the SVP's context.
        InputMethodManager actual = (InputMethodManager) svp.getContext().createDisplayContext(display).getSystemService(Context.INPUT_METHOD_SERVICE);

        // This should be the mocked instance from construction, not the IMM from the greater
        // Android OS (or Robolectric's shadow, in this case).
        assertEquals(expected, actual);
    }
}
