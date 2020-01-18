package io.flutter.plugin.common;

import io.flutter.plugin.common.StandardMessageCodec;
import java.nio.ByteBuffer;
import java.util.ArrayList;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

import static org.junit.Assert.assertEquals;

@Config(manifest=Config.NONE)
@RunWith(RobolectricTestRunner.class)
public class StandardMessageCodecTest {
    // Data types defined as per StandardMessageCodec.Java
    // XXX Please consider exposing these so that tests can access them
    private static final byte NULL = 0;
    private static final byte TRUE = 1;
    private static final byte FALSE = 2;
    private static final byte INT = 3;
    private static final byte LONG = 4;
    private static final byte BIGINT = 5;
    private static final byte DOUBLE = 6;
    private static final byte STRING = 7;
    private static final byte BYTE_ARRAY = 8;
    private static final byte INT_ARRAY = 9;
    private static final byte LONG_ARRAY = 10;
    private static final byte DOUBLE_ARRAY = 11;
    private static final byte LIST = 12;
    private static final byte MAP = 13;

    @Test
    public void itEncodesNullLiterals() {
        // Setup message codec
        StandardMessageCodec codec = new StandardMessageCodec();
        
        // Attempt to encode message with a null literal inside a list
        // A list with a null is used instead of just a null literal because if
        // only null is encoded, then no message is returned; null is returned instead
        ArrayList<Object> messageContent = new ArrayList();
        messageContent.add(null);
        ByteBuffer message = codec.encodeMessage(messageContent);
        message.flip();
        ByteBuffer expected = ByteBuffer.allocateDirect(3);
        expected.put(new byte[]{LIST, 1, NULL});
        expected.flip();
        assertEquals(expected, message);
    }

    @Test
    public void itEncodesNullObjects() {
        // An example class that equals null
        class ExampleNullObject {
            @Override
            public boolean equals(Object other) {
                return other == null || other == this;
            }
            
            @Override
            public int hashCode() {
                return 0;
            }
        }
        
        // Setup message codec
        StandardMessageCodec codec = new StandardMessageCodec();
        
        // Same as itEncodesNullLiterals but with objects that equal null instead
        ArrayList<Object> messageContent = new ArrayList();
        messageContent.add(new ExampleNullObject());
        ByteBuffer message = codec.encodeMessage(messageContent);
        message.flip();
        ByteBuffer expected = ByteBuffer.allocateDirect(3);
        expected.put(new byte[]{LIST, 1, NULL});
        expected.flip();
        assertEquals(expected, message);
    }
}
