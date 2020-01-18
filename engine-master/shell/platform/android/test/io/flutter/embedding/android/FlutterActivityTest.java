package io.flutter.embedding.android;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.support.annotation.NonNull;
import android.support.annotation.Nullable;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;

import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterJNI;
import io.flutter.embedding.engine.loader.FlutterLoader;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

@Config(manifest=Config.NONE)
@RunWith(RobolectricTestRunner.class)
public class FlutterActivityTest {
  @Test
  public void itCreatesDefaultIntentWithExpectedDefaults() {
    Intent intent = FlutterActivity.createDefaultIntent(RuntimeEnvironment.application);
    ActivityController<FlutterActivity> activityController = Robolectric.buildActivity(FlutterActivity.class, intent);
    FlutterActivity flutterActivity = activityController.get();
    flutterActivity.setDelegate(new FlutterActivityAndFragmentDelegate(flutterActivity));

    assertEquals("main", flutterActivity.getDartEntrypointFunctionName());
    assertEquals("/", flutterActivity.getInitialRoute());
    assertArrayEquals(new String[]{}, flutterActivity.getFlutterShellArgs().toArray());
    assertTrue(flutterActivity.shouldAttachEngineToActivity());
    assertNull(flutterActivity.getCachedEngineId());
    assertTrue(flutterActivity.shouldDestroyEngineWithHost());
    assertEquals(BackgroundMode.opaque, flutterActivity.getBackgroundMode());
    assertEquals(FlutterView.RenderMode.surface, flutterActivity.getRenderMode());
    assertEquals(FlutterView.TransparencyMode.opaque, flutterActivity.getTransparencyMode());
  }

  @Test
  public void itDestroysNewEngineWhenIntentIsMissingParameter() {
    // All clients should use the static members of FlutterActivity to construct an
    // Intent. Missing extras is an error. However, Flutter has number of tests that
    // don't seem to use the static members of FlutterActivity to construct the
    // launching Intent, so this test explicitly verifies that even illegal Intents
    // result in the automatic destruction of a non-cached FlutterEngine, which prevents
    // the breakage of memory usage benchmark tests.
    Intent intent = new Intent(RuntimeEnvironment.application, FlutterActivity.class);
    ActivityController<FlutterActivity> activityController = Robolectric.buildActivity(FlutterActivity.class, intent);
    FlutterActivity flutterActivity = activityController.get();
    flutterActivity.setDelegate(new FlutterActivityAndFragmentDelegate(flutterActivity));

    assertTrue(flutterActivity.shouldDestroyEngineWithHost());
  }

  @Test
  public void itDoesNotDestroyFlutterEngineWhenProvidedByHost() {
    Intent intent = new Intent(RuntimeEnvironment.application, FlutterActivityWithProvidedEngine.class);
    ActivityController<FlutterActivityWithProvidedEngine> activityController = Robolectric.buildActivity(FlutterActivityWithProvidedEngine.class, intent);
    activityController.create();
    FlutterActivityWithProvidedEngine flutterActivity = activityController.get();

    assertFalse(flutterActivity.shouldDestroyEngineWithHost());
  }

  @Test
  public void itCreatesNewEngineIntentWithRequestedSettings() {
    Intent intent = FlutterActivity.withNewEngine()
        .initialRoute("/custom/route")
        .backgroundMode(BackgroundMode.transparent)
        .build(RuntimeEnvironment.application);
    ActivityController<FlutterActivity> activityController = Robolectric.buildActivity(FlutterActivity.class, intent);
    FlutterActivity flutterActivity = activityController.get();
    flutterActivity.setDelegate(new FlutterActivityAndFragmentDelegate(flutterActivity));

    assertEquals("/custom/route", flutterActivity.getInitialRoute());
    assertArrayEquals(new String[]{}, flutterActivity.getFlutterShellArgs().toArray());
    assertTrue(flutterActivity.shouldAttachEngineToActivity());
    assertNull(flutterActivity.getCachedEngineId());
    assertTrue(flutterActivity.shouldDestroyEngineWithHost());
    assertEquals(BackgroundMode.transparent, flutterActivity.getBackgroundMode());
    assertEquals(FlutterView.RenderMode.texture, flutterActivity.getRenderMode());
    assertEquals(FlutterView.TransparencyMode.transparent, flutterActivity.getTransparencyMode());
  }

  @Test
  public void itCreatesCachedEngineIntentThatDoesNotDestroyTheEngine() {
    Intent intent = FlutterActivity.withCachedEngine("my_cached_engine")
        .destroyEngineWithActivity(false)
        .build(RuntimeEnvironment.application);
    ActivityController<FlutterActivity> activityController = Robolectric.buildActivity(FlutterActivity.class, intent);
    FlutterActivity flutterActivity = activityController.get();

    assertArrayEquals(new String[]{}, flutterActivity.getFlutterShellArgs().toArray());
    assertTrue(flutterActivity.shouldAttachEngineToActivity());
    assertEquals("my_cached_engine", flutterActivity.getCachedEngineId());
    assertFalse(flutterActivity.shouldDestroyEngineWithHost());
  }

  @Test
  public void itCreatesCachedEngineIntentThatDestroysTheEngine() {
    Intent intent = FlutterActivity.withCachedEngine("my_cached_engine")
        .destroyEngineWithActivity(true)
        .build(RuntimeEnvironment.application);
    ActivityController<FlutterActivity> activityController = Robolectric.buildActivity(FlutterActivity.class, intent);
    FlutterActivity flutterActivity = activityController.get();

    assertArrayEquals(new String[]{}, flutterActivity.getFlutterShellArgs().toArray());
    assertTrue(flutterActivity.shouldAttachEngineToActivity());
    assertEquals("my_cached_engine", flutterActivity.getCachedEngineId());
    assertTrue(flutterActivity.shouldDestroyEngineWithHost());
  }

  static class FlutterActivityWithProvidedEngine extends FlutterActivity {
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
      super.delegate = new FlutterActivityAndFragmentDelegate(this);
      super.delegate.setupFlutterEngine();
    }

    @Nullable
    @Override
    public FlutterEngine provideFlutterEngine(@NonNull Context context) {
      FlutterJNI flutterJNI = mock(FlutterJNI.class);
      when(flutterJNI.isAttached()).thenReturn(true);

      return new FlutterEngine(
          context,
          mock(FlutterLoader.class),
          flutterJNI,
          new String[]{},
          true
        );
    }
  }
}
