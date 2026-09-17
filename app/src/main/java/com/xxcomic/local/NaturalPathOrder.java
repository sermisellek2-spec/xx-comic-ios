package com.xxcomic.local;

import java.io.Serializable;
import java.math.BigInteger;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public class NaturalPathOrder implements Comparator<String>, Serializable {
    private static final long serialVersionUID = 1L;

    @Override
    public int compare(String p1, String p2) {
        if (p1 == null && p2 == null) return 0;
        if (p1 == null) return -1;
        if (p2 == null) return 1;
        if (p1.equals(p2)) return 0;

        String norm1 = normalize(p1);
        String norm2 = normalize(p2);

        String[] segs1 = norm1.split("/");
        String[] segs2 = norm2.split("/");

        int minSegs = Math.min(segs1.length, segs2.length);
        for (int i = 0; i < minSegs; i++) {
            int cmp = compareSegment(segs1[i], segs2[i]);
            if (cmp != 0) return cmp;
        }

        if (segs1.length != segs2.length) {
            return Integer.compare(segs1.length, segs2.length);
        }

        int caseInsensitive = norm1.compareToIgnoreCase(norm2);
        if (caseInsensitive != 0) return caseInsensitive;
        return norm1.compareTo(norm2);
    }

    private static String normalize(String path) {
        String s = path.replace('\\', '/');
        while (s.startsWith("/")) s = s.substring(1);
        while (s.endsWith("/")) s = s.substring(0, s.length() - 1);
        return s;
    }

    private static int compareSegment(String s1, String s2) {
        if (s1.equals(s2)) return 0;

        List<String> chunks1 = splitChunks(s1);
        List<String> chunks2 = splitChunks(s2);

        int minChunks = Math.min(chunks1.size(), chunks2.size());
        for (int i = 0; i < minChunks; i++) {
            String c1 = chunks1.get(i);
            String c2 = chunks2.get(i);

            boolean isNum1 = isDigits(c1);
            boolean isNum2 = isDigits(c2);

            if (isNum1 && isNum2) {
                BigInteger b1 = new BigInteger(c1);
                BigInteger b2 = new BigInteger(c2);
                int numCmp = b1.compareTo(b2);
                if (numCmp != 0) return numCmp;
                // If numeric values are equal (e.g., "01" vs "1"), shorter string (fewer leading zeroes) comes first
                int lenCmp = Integer.compare(c1.length(), c2.length());
                if (lenCmp != 0) return lenCmp;
            } else if (isNum1) {
                // Digits before non-digits
                return -1;
            } else if (isNum2) {
                return 1;
            } else {
                int textCmp = c1.compareToIgnoreCase(c2);
                if (textCmp != 0) return textCmp;
                int caseCmp = c1.compareTo(c2);
                if (caseCmp != 0) return caseCmp;
            }
        }

        return Integer.compare(chunks1.size(), chunks2.size());
    }

    private static List<String> splitChunks(String s) {
        List<String> chunks = new ArrayList<>();
        int len = s.length();
        int i = 0;
        while (i < len) {
            char c = s.charAt(i);
            boolean digit = Character.isDigit(c);
            int start = i;
            while (i < len && Character.isDigit(s.charAt(i)) == digit) {
                i++;
            }
            chunks.add(s.substring(start, i));
        }
        return chunks;
    }

    private static boolean isDigits(String s) {
        if (s == null || s.isEmpty()) return false;
        for (int i = 0; i < s.length(); i++) {
            if (!Character.isDigit(s.charAt(i))) return false;
        }
        return true;
    }
}
