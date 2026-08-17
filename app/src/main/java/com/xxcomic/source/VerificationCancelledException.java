package com.xxcomic.source;

import java.io.IOException;

public final class VerificationCancelledException extends IOException {
    public VerificationCancelledException(String message) {
        super(message);
    }
}
