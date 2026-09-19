package com.xxcomic;

import org.junit.Test;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.HashMap;
import java.util.Map;
import static org.junit.Assert.assertNull;

public class ActivityRequestCodeTest {
    @Test
    public void activityResultsCannotRouteAnImportToAnotherOperation() throws Exception {
        Map<Integer, String> owners = new HashMap<>();
        for (Field field : MainActivity.class.getDeclaredFields()) {
            String name = field.getName();
            if (field.getType() != int.class || !Modifier.isStatic(field.getModifiers())
                    || !(name.startsWith("REQUEST_CODE_") || name.endsWith("_REQUEST"))) continue;
            field.setAccessible(true);
            String previous = owners.put(field.getInt(null), name);
            assertNull(name + " shares an activity result code with " + previous, previous);
        }
    }
}
