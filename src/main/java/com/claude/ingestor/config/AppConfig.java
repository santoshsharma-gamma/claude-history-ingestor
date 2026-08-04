package com.claude.ingestor.config;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * General-purpose beans shared across the app. Kept deliberately small in
 * Phase 1; later phases (enrichment, analytics) will add beans here rather
 * than growing the config classes in an unstructured way.
 */
@Configuration
public class AppConfig {

    /**
     * A single injectable clock (UTC) so later phases (offset tracking,
     * analytics, "today's" queries) don't scatter {@code Instant.now()}
     * calls that are awkward to control in tests.
     */
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }
}
