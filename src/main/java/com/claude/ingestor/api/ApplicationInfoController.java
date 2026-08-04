package com.claude.ingestor.api;

import java.time.Clock;
import java.time.Instant;

import com.claude.ingestor.model.VersionInfo;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class ApplicationInfoController {

    private static final String VERSION = "0.1.0-SNAPSHOT";

    private final Instant startedAt;

    @Value("${spring.application.name:claude-history-ingestor}")
    private String applicationName;

    public ApplicationInfoController(Clock clock) {
        this.startedAt = Instant.now(clock);
    }

    @GetMapping("/info")
    public VersionInfo info() {
        return new VersionInfo(applicationName, VERSION, Runtime.version().toString(), startedAt.toString());
    }
}
