// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugin.common;

import java.nio.ByteBuffer;
import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;

/**
 * A {@link MessageCodec} using UTF-8 encoded JSON messages.
 *
 * <p>This codec is guaranteed to be compatible with the corresponding
 * <a href="https://docs.flutter.io/flutter/services/JSONMessageCodec-class.html">JSONMessageCodec</a>
 * on the Dart side. These parts of the Flutter SDK are evolved synchronously.</p>
 *
 * <p>Supports the same Java values as {@link JSONObject#wrap(Object)}.</p>
 *
 * <p>On the Dart side, JSON messages are handled by the JSON facilities of the
 * <a href="https://api.dartlang.org/stable/dart-convert/JSON-constant.html">dart:convert</a>
 * package.</p>
 */
public final class JSONMessageCodec implements MessageCodec<Object> {
    // This codec must match the Dart codec of the same name in package flutter/services.
    public static final JSONMessageCodec INSTANCE = new JSONMessageCodec();

    private JSONMessageCodec() {
    }

    @Override
    public ByteBuffer encodeMessage(Object message) {
        if (message == null) {
            return null;
        }
        final Object wrapped = JSONUtil.wrap(message);
        if (wrapped instanceof String) {
          return StringCodec.INSTANCE.encodeMessage(JSONObject.quote((String) wrapped));
        } else {
          return StringCodec.INSTANCE.encodeMessage(wrapped.toString());
        }
    }

    @Override
    public Object decodeMessage(ByteBuffer message) {
        if (message == null) {
            return null;
        }
        try {
            final String json = StringCodec.INSTANCE.decodeMessage(message);
            final JSONTokener tokener = new JSONTokener(json);
            final Object value = tokener.nextValue();
            if (tokener.more()) {
                throw new IllegalArgumentException("Invalid JSON");
            }
            return value;
        } catch (JSONException e) {
            throw new IllegalArgumentException("Invalid JSON", e);
        }
    }
}
