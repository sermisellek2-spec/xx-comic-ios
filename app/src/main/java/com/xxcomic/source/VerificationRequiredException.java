package com.xxcomic.source;

import java.io.IOException;

public final class VerificationRequiredException extends IOException {
    public VerificationRequiredException(String message) {
        super(message);
    }
}
