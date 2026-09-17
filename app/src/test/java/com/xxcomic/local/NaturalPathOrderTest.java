package com.xxcomic.local;

import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;

public class NaturalPathOrderTest {
    @Test
    public void ordersNumericNamesNaturally() {
        List<String> paths = new ArrayList<>(Arrays.asList("第10话/1.jpg", "第2话/10.jpg", "第2话/2.jpg"));
        Collections.sort(paths, new NaturalPathOrder());
        assertEquals(Arrays.asList("第2话/2.jpg", "第2话/10.jpg", "第10话/1.jpg"), paths);
    }

    @Test
    public void ordersFlatNumbersNaturally() {
        List<String> paths = new ArrayList<>(Arrays.asList("10.png", "1.png", "2.png", "20.png", "02.png"));
        Collections.sort(paths, new NaturalPathOrder());
        // "1.png", "2.png", "02.png", "10.png", "20.png"
        assertEquals(Arrays.asList("1.png", "2.png", "02.png", "10.png", "20.png"), paths);
    }

    @Test
    public void ordersMultipleSegmentsWithMixedCharacters() {
        List<String> paths = new ArrayList<>(Arrays.asList(
                "vol1/ch10/page1.jpg",
                "vol1/ch2/page1.jpg",
                "vol1/ch1/page10.jpg",
                "vol1/ch1/page2.jpg",
                "vol2/ch1/page1.jpg"
        ));
        Collections.sort(paths, new NaturalPathOrder());
        assertEquals(Arrays.asList(
                "vol1/ch1/page2.jpg",
                "vol1/ch1/page10.jpg",
                "vol1/ch2/page1.jpg",
                "vol1/ch10/page1.jpg",
                "vol2/ch1/page1.jpg"
        ), paths);
    }
}
