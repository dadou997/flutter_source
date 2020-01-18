package io.flutter.embedding.android;

import android.app.Activity;
import android.arch.lifecycle.Lifecycle;
import android.content.Context;
import android.os.Bundle;
import android.support.annotation.NonNull;
import android.support.annotation.Nullable;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.invocation.InvocationOnMock;
import org.mockito.stubbing.Answer;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.FlutterJNI;
import io.flutter.embedding.engine.FlutterShellArgs;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.platform.PlatformPlugin;

import static org.junit.Assert.assertNotNull;
import static org.mockito.Matchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.spy;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.withSettings;

@Config(manifest=Config.NONE)
@RunWith(RobolectricTestRunner.class)
public class FlutterAndroidComponentTest {
  @Test
  public void pluginsReceiveFlutterPluginBinding() {
    // ---- Test setup ----
    // Place a FlutterEngine in the static cache.
    FlutterLoader mockFlutterLoader = mock(FlutterLoader.class);
    FlutterJNI mockFlutterJni = mock(FlutterJNI.class);
    when(mockFlutterJni.isAttached()).thenReturn(true);
    FlutterEngine cachedEngine = spy(new FlutterEngine(RuntimeEnvironment.application, mockFlutterLoader, mockFlutterJni));
    FlutterEngineCache.getInstance().put("my_flutter_engine", cachedEngine);

    // Add mock plugin.
    FlutterPlugin mockPlugin = mock(FlutterPlugin.class);
    cachedEngine.getPlugins().add(mockPlugin);

    // Create a fake Host, which is required by the delegate.
    FlutterActivityAndFragmentDelegate.Host fakeHost = new FakeHost(cachedEngine);

    // Create the real object that we're testing.
    FlutterActivityAndFragmentDelegate delegate = new FlutterActivityAndFragmentDelegate(fakeHost);

    // --- Execute the behavior under test ---
    // Push the delegate through all lifecycle methods all the way to destruction.
    delegate.onAttach(RuntimeEnvironment.application);

    // Verify that the plugin is attached to the FlutterEngine.
    ArgumentCaptor<FlutterPlugin.FlutterPluginBinding> pluginBindingCaptor = ArgumentCaptor.forClass(FlutterPlugin.FlutterPluginBinding.class);
    verify(mockPlugin, times(1)).onAttachedToEngine(pluginBindingCaptor.capture());
    FlutterPlugin.FlutterPluginBinding binding = pluginBindingCaptor.getValue();
    assertNotNull(binding.getApplicationContext());
    assertNotNull(binding.getBinaryMessenger());
    assertNotNull(binding.getTextureRegistry());
    assertNotNull(binding.getPlatformViewRegistry());

    delegate.onActivityCreated(null);
    delegate.onCreateView(null, null, null);
    delegate.onStart();
    delegate.onResume();
    delegate.onPause();
    delegate.onStop();
    delegate.onDestroyView();
    delegate.onDetach();

    // Verify the plugin was detached from the FlutterEngine.
    pluginBindingCaptor = ArgumentCaptor.forClass(FlutterPlugin.FlutterPluginBinding.class);
    verify(mockPlugin, times(1)).onDetachedFromEngine(pluginBindingCaptor.capture());
    binding = pluginBindingCaptor.getValue();
    assertNotNull(binding.getApplicationContext());
    assertNotNull(binding.getBinaryMessenger());
    assertNotNull(binding.getTextureRegistry());
    assertNotNull(binding.getPlatformViewRegistry());
  }

  @Test
  public void activityAwarePluginsReceiveActivityBinding() {
    // ---- Test setup ----
    // Place a FlutterEngine in the static cache.
    FlutterLoader mockFlutterLoader = mock(FlutterLoader.class);
    FlutterJNI mockFlutterJni = mock(FlutterJNI.class);
    when(mockFlutterJni.isAttached()).thenReturn(true);
    FlutterEngine cachedEngine = spy(new FlutterEngine(RuntimeEnvironment.application, mockFlutterLoader, mockFlutterJni));
    FlutterEngineCache.getInstance().put("my_flutter_engine", cachedEngine);

    // Add mock plugin.
    FlutterPlugin mockPlugin = mock(FlutterPlugin.class, withSettings().extraInterfaces(ActivityAware.class));
    ActivityAware activityAwarePlugin = (ActivityAware) mockPlugin;
    ActivityPluginBinding.OnSaveInstanceStateListener mockSaveStateListener = mock(ActivityPluginBinding.OnSaveInstanceStateListener.class);

    // Add a OnSaveStateListener when the Activity plugin binding is made available.
    doAnswer(new Answer() {
      @Override
      public Object answer(InvocationOnMock invocation) throws Throwable {
        ActivityPluginBinding binding = (ActivityPluginBinding) invocation.getArguments()[0];
        binding.addOnSaveStateListener(mockSaveStateListener);
        return null;
      }
    }).when(activityAwarePlugin).onAttachedToActivity(any(ActivityPluginBinding.class));

    cachedEngine.getPlugins().add(mockPlugin);

    // Create a fake Host, which is required by the delegate.
    FlutterActivityAndFragmentDelegate.Host fakeHost = new FakeHost(cachedEngine);

    FlutterActivityAndFragmentDelegate delegate = new FlutterActivityAndFragmentDelegate(fakeHost);

    // --- Execute the behavior under test ---
    // Push the delegate through all lifecycle methods all the way to destruction.
    delegate.onAttach(RuntimeEnvironment.application);

    // Verify plugin was given an ActivityPluginBinding.
    ArgumentCaptor<ActivityPluginBinding> pluginBindingCaptor = ArgumentCaptor.forClass(ActivityPluginBinding.class);
    verify(activityAwarePlugin, times(1)).onAttachedToActivity(pluginBindingCaptor.capture());
    ActivityPluginBinding binding = pluginBindingCaptor.getValue();
    assertNotNull(binding.getActivity());
    assertNotNull(binding.getLifecycle());

    delegate.onActivityCreated(null);

    // Verify that after Activity creation, the plugin was allowed to restore state.
    verify(mockSaveStateListener, times(1)).onRestoreInstanceState(any(Bundle.class));

    delegate.onCreateView(null, null, null);
    delegate.onStart();
    delegate.onResume();
    delegate.onPause();
    delegate.onStop();
    delegate.onSaveInstanceState(mock(Bundle.class));

    // Verify that the plugin was allowed to save state.
    verify(mockSaveStateListener, times(1)).onSaveInstanceState(any(Bundle.class));

    delegate.onDestroyView();
    delegate.onDetach();

    // Verify that the plugin was detached from the Activity.
    verify(activityAwarePlugin, times(1)).onDetachedFromActivity();
  }

  private static class FakeHost implements FlutterActivityAndFragmentDelegate.Host {
    final FlutterEngine cachedEngine;
    Activity activity;
    Lifecycle lifecycle = mock(Lifecycle.class);

    private FakeHost(@NonNull FlutterEngine flutterEngine) {
      cachedEngine = flutterEngine;
    }

    @NonNull
    @Override
    public Context getContext() {
      return RuntimeEnvironment.application;
    }


    @Nullable
    @Override
    public Activity getActivity() {
      if (activity == null) {
        activity = Robolectric.setupActivity(Activity.class);
      }
      return activity;
    }

    @NonNull
    @Override
    public Lifecycle getLifecycle() {
      return lifecycle;
    }

    @NonNull
    @Override
    public FlutterShellArgs getFlutterShellArgs() {
      return new FlutterShellArgs(new String[]{});
    }

    @Nullable
    @Override
    public String getCachedEngineId() {
      return "my_flutter_engine";
    }

    @Override
    public boolean shouldDestroyEngineWithHost() {
      return true;
    }

    @NonNull
    @Override
    public String getDartEntrypointFunctionName() {
      return "main";
    }

    @NonNull
    @Override
    public String getAppBundlePath() {
      return "/fake/path";
    }

    @Nullable
    @Override
    public String getInitialRoute() {
      return "/";
    }

    @NonNull
    @Override
    public FlutterView.RenderMode getRenderMode() {
      return FlutterView.RenderMode.surface;
    }

    @NonNull
    @Override
    public FlutterView.TransparencyMode getTransparencyMode() {
      return FlutterView.TransparencyMode.transparent;
    }

    @Nullable
    @Override
    public SplashScreen provideSplashScreen() {
      return null;
    }

    @Nullable
    @Override
    public FlutterEngine provideFlutterEngine(@NonNull Context context) {
      return cachedEngine;
    }

    @Nullable
    @Override
    public PlatformPlugin providePlatformPlugin(@Nullable Activity activity, @NonNull FlutterEngine flutterEngine) {
      return null;
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {}

    @Override
    public void cleanUpFlutterEngine(@NonNull FlutterEngine flutterEngine) {}

    @Override
    public boolean shouldAttachEngineToActivity() {
      return true;
    }

    @Override
    public void onFlutterUiDisplayed() {}

    @Override
    public void onFlutterUiNoLongerDisplayed() {}
  }
}
