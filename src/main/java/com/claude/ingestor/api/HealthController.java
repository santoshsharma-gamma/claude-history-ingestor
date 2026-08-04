package com.claude.ingestor.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * A minimal, always-fast health check at {@code /api/health}, separate from
 * Actuator's {@code /actuator/health} (which is also enabled and will grow
 * more meaningful checks — e.g. "can we reach OpenObserve" — in a later
 * phase).
 */
@RestController
@RequestMapping("/api")
public class HealthController {

    @GetMapping("/health")
    public HealthResponse health() {
        return new HealthResponse("UP");
    }

    public record HealthResponse(String status) {
    }
}
