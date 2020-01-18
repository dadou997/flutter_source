// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.embedding.engine.systemchannels;

import android.os.Build;
import android.support.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import io.flutter.Log;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.JSONMethodCodec;
import io.flutter.plugin.common.MethodChannel;

/**
 * Sends the platform's locales to Dart.
 */
public class LocalizationChannel {
  private static final String TAG = "LocalizationChannel";

  @NonNull
  public final MethodChannel channel;

  public LocalizationChannel(@NonNull DartExecutor dartExecutor) {
    this.channel = new MethodChannel(dartExecutor, "flutter/localization", JSONMethodCodec.INSTANCE);
  }

  /**
   * Send the given {@code locales} to Dart.
   */
  public void sendLocales(@NonNull List<Locale> locales) {
    Log.v(TAG, "Sending Locales to Flutter.");
    List<String> data = new ArrayList<>();
    for (Locale locale : locales) {
      Log.v(TAG, "Locale (Language: " + locale.getLanguage()
          + ", Country: " + locale.getCountry()
          + ", Variant: " + locale.getVariant() + ")");
      data.add(locale.getLanguage());
      data.add(locale.getCountry());
      // locale.getScript() was added in API 21.
      data.add(Build.VERSION.SDK_INT >= 21 ? locale.getScript() : "");
      data.add(locale.getVariant());
    }
    channel.invokeMethod("setLocale", data);
  }

}
