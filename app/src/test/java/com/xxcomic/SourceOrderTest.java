package com.xxcomic;

import org.json.JSONArray;
import org.junit.Test;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import static org.junit.Assert.assertEquals;

public class SourceOrderTest {
    private final List<String> defaults = Arrays.asList("baozi", "copy", "manwa");

    @Test public void oldInstallAndInvalidPreferenceKeepDefaultOrder() {
        assertEquals(defaults, SourceOrder.normalize(SourceOrder.decode(""), defaults));
        assertEquals(defaults, SourceOrder.normalize(SourceOrder.decode("broken"), defaults));
    }

    @Test public void upgradeAppendsNewSourcesAndDropsRemovedAndDuplicateIds() {
        assertEquals(Arrays.asList("manwa", "baozi", "copy", "new"),
                SourceOrder.normalize(Arrays.asList("removed", "manwa", "manwa", "baozi"),
                        Arrays.asList("baozi", "copy", "manwa", "new")));
    }

    @Test public void disabledSourceRetainsPositionWhenEnabledAgain() {
        List<String> saved = Arrays.asList("manwa", "copy", "baozi");
        assertEquals(Arrays.asList("manwa", "baozi"), SourceOrder.apply(
                Arrays.asList("baozi", "manwa"), saved, id -> id));
        assertEquals(saved, SourceOrder.apply(defaults, saved, id -> id));
        assertEquals(Arrays.asList("manwa", "copy", "baozi"), saved);
    }

    @Test public void jsonRoundTripPreservesDraggedOrder() {
        List<String> dragged = Arrays.asList("copy", "manwa", "baozi");
        assertEquals(dragged, SourceOrder.decode(new JSONArray(dragged).toString()));
    }

    @Test public void malformedEntriesCannotCreatePhantomSources() {
        assertEquals(Arrays.asList("copy", "baozi", "manwa"), SourceOrder.normalize(
                SourceOrder.decode("[null,42,{},\"\",\"copy\",\"copy\",\"deleted\"]"), defaults));
    }

    @Test public void sourceNamesDoNotAffectOrderOrLoseSourceObjects() {
        String[] first = {"baozi", "renamed"}, second = {"copy", "same name"};
        assertEquals(Arrays.asList(second, first), SourceOrder.apply(
                Arrays.asList(first, second), Arrays.asList("copy", "baozi"), row -> row[0]));
    }

    @Test public void allDisabledAndResetAreValid() {
        assertEquals(Collections.emptyList(), SourceOrder.apply(Collections.<String>emptyList(), defaults, id -> id));
        assertEquals(defaults, SourceOrder.normalize(defaults, defaults));
    }
}
