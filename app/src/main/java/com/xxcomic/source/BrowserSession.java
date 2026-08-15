package com.xxcomic.source;

import java.io.IOException;

public interface BrowserSession {
    String fetch(String url) throws IOException;
}
