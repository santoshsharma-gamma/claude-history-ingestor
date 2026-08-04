package com.claude.ingestor.config;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

/**
 * Provides a {@link RestClient} pre-configured with OpenObserve's base URL
 * and Basic-auth header, so the Phase 6 sender can simply inject it and
 * call {@code .post().uri("/api/{org}/v1/logs")} without repeating any
 * connection setup.
 *
 * Nothing calls this bean yet in Phase 1 — it's wired up now so later
 * phases only need to add behavior, not plumbing.
 */
@Configuration
public class RestClientConfig {

    @Bean
    public RestClient openObserveRestClient(OpenObserveProperties props) {
        String credentials = props.user() + ":" + props.password();
        String basicAuth = "Basic "
                + Base64.getEncoder().encodeToString(credentials.getBytes(StandardCharsets.UTF_8));

        return RestClient.builder()
                .baseUrl(props.baseUrl())
                .defaultHeader("Authorization", basicAuth)
                .defaultHeader("Content-Type", "application/json")
                .build();
    }
}
