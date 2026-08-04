package com.claude.ingestor.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * Connection details for the OpenObserve instance events get shipped to.
 *
 * Bound from the {@code openobserve.*} keys in application.yml. {@code user}
 * and {@code password} default to empty strings (rather than being left
 * unset) so the app can still boot in Phase 1 before real credentials are
 * configured — the {@link RestClientConfig} bean depends on these being
 * non-null.
 */
@ConfigurationProperties(prefix = "openobserve")
public record OpenObserveProperties(

        @DefaultValue("http://localhost:5080") String baseUrl,
        @DefaultValue("default") String org,
        @DefaultValue("claude_code_history") String stream,
        @DefaultValue("") String user,
        @DefaultValue("") String password,
        @DefaultValue("500") int batchSize
) {
}
