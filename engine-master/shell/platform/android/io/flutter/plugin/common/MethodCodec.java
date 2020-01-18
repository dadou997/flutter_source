// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugin.common;

import java.nio.ByteBuffer;

/**
 * A codec for method calls and enveloped results.
 *
 * Method calls are encoded as binary messages with enough structure that the codec can
 * extract a method name String and an arguments Object. These data items are used to populate a
 * {@link MethodCall}.
 *
 * All operations throw {@link IllegalArgumentException}, if conversion fails.
 */
public interface MethodCodec {
    /**
     * Encodes a message call into binary.
     *
     * @param methodCall a {@link MethodCall}.
     * @return a {@link ByteBuffer} containing the encoding between position 0 and
     * the current position.
     */
    ByteBuffer encodeMethodCall(MethodCall methodCall);

    /**
     * Decodes a message call from binary.
     *
     * @param methodCall the binary encoding of the method call as a {@link ByteBuffer}.
     * @return a {@link MethodCall} representation of the bytes between the given buffer's current
     * position and its limit.
     */
    MethodCall decodeMethodCall(ByteBuffer methodCall);

    /**
     * Encodes a successful result into a binary envelope message.
     *
     * @param result The result value, possibly null.
     * @return a {@link ByteBuffer} containing the encoding between position 0 and
     * the current position.
     */
    ByteBuffer encodeSuccessEnvelope(Object result);

    /**
     * Encodes an error result into a binary envelope message.
     *
     * @param errorCode An error code String.
     * @param errorMessage An error message String, possibly null.
     * @param errorDetails Error details, possibly null.
     * @return a {@link ByteBuffer} containing the encoding between position 0 and
     * the current position.
     */
    ByteBuffer encodeErrorEnvelope(String errorCode, String errorMessage, Object errorDetails);

    /**
     * Decodes a result envelope from binary.
     *
     * @param envelope the binary encoding of a result envelope as a {@link ByteBuffer}.
     * @return the enveloped result Object.
     * @throws FlutterException if the envelope was an error envelope.
     */
    Object decodeEnvelope(ByteBuffer envelope);
}
