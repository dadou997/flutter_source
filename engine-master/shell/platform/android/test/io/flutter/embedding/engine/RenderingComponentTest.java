package io.flutter.embedding.engine;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import java.util.concurrent.atomic.AtomicInteger;

import io.flutter.embedding.engine.renderer.FlutterRenderer;
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

@Config(manifest=Config.NONE)
@RunWith(RobolectricTestRunner.class)
public class RenderingComponentTest {
  @Test
  public void flutterUiDisplayListenersCanRemoveThemselvesWhenInvoked() {
    // Setup test.
    FlutterJNI flutterJNI = new FlutterJNI();
    FlutterRenderer flutterRenderer = new FlutterRenderer(flutterJNI);

    AtomicInteger listenerInvocationCount = new AtomicInteger(0);
    FlutterUiDisplayListener listener = new FlutterUiDisplayListener() {
      @Override
      public void onFlutterUiDisplayed() {
        // This is the behavior we're testing, but we also verify that this method
        // was invoked to ensure that this test behavior executed.
        flutterRenderer.removeIsDisplayingFlutterUiListener(this);

        // Track the invocation to ensure this method is called once, and only once.
        listenerInvocationCount.incrementAndGet();
      }

      @Override
      public void onFlutterUiNoLongerDisplayed() {}
    };
    flutterRenderer.addIsDisplayingFlutterUiListener(listener);

    // Execute behavior under test.
    // Pretend we are the native side and tell FlutterJNI that Flutter has rendered a frame.
    flutterJNI.onFirstFrame();

    // Verify results.
    // If we got to this point without an exception, and if our listener was called one time,
    // then the behavior under test is correct.
    assertEquals(1, listenerInvocationCount.get());
  }

  @Test
  public void flutterUiDisplayListenersAddedAfterFirstFrameAreAutomaticallyInvoked() {
    // Setup test.
    FlutterJNI flutterJNI = new FlutterJNI();
    FlutterRenderer flutterRenderer = new FlutterRenderer(flutterJNI);

    FlutterUiDisplayListener listener = mock(FlutterUiDisplayListener.class);

    // Pretend we are the native side and tell FlutterJNI that Flutter has rendered a frame.
    flutterJNI.onFirstFrame();

    // Execute behavior under test.
    flutterRenderer.addIsDisplayingFlutterUiListener(listener);

    // Verify results.
    verify(listener, times(1)).onFlutterUiDisplayed();
  }

  @Test
  public void flutterUiDisplayListenersAddedAfterFlutterUiDisappearsAreNotInvoked() {
    // Setup test.
    FlutterJNI flutterJNI = new FlutterJNI();
    FlutterRenderer flutterRenderer = new FlutterRenderer(flutterJNI);

    FlutterUiDisplayListener listener = mock(FlutterUiDisplayListener.class);

    // Pretend we are the native side and tell FlutterJNI that Flutter has rendered a frame.
    flutterJNI.onFirstFrame();

    // Pretend that rendering has stopped.
    flutterJNI.onRenderingStopped();

    // Execute behavior under test.
    flutterRenderer.addIsDisplayingFlutterUiListener(listener);

    // Verify results.
    verify(listener, never()).onFlutterUiDisplayed();
  }
}
