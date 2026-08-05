package com.claude.ingestor;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Entry point for the Claude history ingestor.
 *
 * Phase 1 goal: get the app booting with configuration wired up and a
 * couple of health/info endpoints responding. Later phases add the file
 * watcher, parser, enrichment, analytics, and the OpenObserve sender on
 * top of this skeleton.
 */
@SpringBootApplication
// Scans the whole com.claude.ingestor tree (this class's own package),
// not just .config - @ConfigurationProperties classes also live in
// .offset (OffsetStoreProperties) and .parser (ParserProperties), and a
// narrower scan would leave those unregistered as beans. (This was in
// fact a real bug through Phases 3-5: the scan was previously scoped to
// "com.claude.ingestor.config" only, which is why it's called out here
// explicitly rather than just silently fixed.)
@ConfigurationPropertiesScan
@EnableScheduling // added in Phase 6, for OpenObserveBatchingListener's periodic flush
public class ClaudeHistoryApplication {

    public static void main(String[] args) {
        SpringApplication.run(ClaudeHistoryApplication.class, args);
    }
}
