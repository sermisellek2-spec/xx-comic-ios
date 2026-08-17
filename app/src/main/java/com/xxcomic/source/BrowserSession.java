package com.xxcomic.source;

import java.io.IOException;

public interface BrowserSession {
    String fetch(String url) throws IOException;

    default String fetchInteractive(String url) throws IOException {
        return fetch(url);
    }
}
