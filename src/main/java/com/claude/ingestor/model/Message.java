package com.claude.ingestor.model;

import java.util.List;

public record Message(
        MessageRole role,
        String model,
        List<ContentBlock> content,
        TokenUsage usage
) {
}

