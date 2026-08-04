package com.claude.ingestor.repository;

import com.claude.ingestor.util.Json;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * Detects a Node.js project via {@code package.json}, then refines the
 * result by checking {@code dependencies}/{@code devDependencies} for
 * {@code react} or {@code vue} - matching the roadmap's own example
 * ({@code package.json} → React). Falls back to the generic "Node.js" if
 * {@code package.json} doesn't parse (malformed, unusual encoding, etc) or
 * doesn't mention either framework - a project directory that merely
 * *has* a package.json is still worth reporting as something, even if
 * the more specific framework can't be determined.
 */
@Component
public class NodeJsDetector implements TechnologyDetector {

    @Override
    public String technologyName() {
        // Used by matches()-only callers; refine() below returns the more
        // specific name when package.json content is actually inspected.
        return "Node.js";
    }

    @Override
    public boolean matches(Path projectDir) {
        return Files.exists(projectDir.resolve("package.json"));
    }

    /**
     * Returns the most specific technology name this detector can
     * determine for {@code projectDir}: {@code "React"}, {@code "Vue"}, or
     * the generic {@code "Node.js"} if neither is detected or
     * {@code package.json} can't be read/parsed.
     */
    public String refine(Path projectDir) {
        Path packageJson = projectDir.resolve("package.json");
        try {
            String content = Files.readString(packageJson, StandardCharsets.UTF_8);
            Object parsed = Json.parse(content);
            if (parsed instanceof Map<?, ?> root) {
                if (mentionsDependency(root, "react")) {
                    return "React";
                }
                if (mentionsDependency(root, "vue")) {
                    return "Vue";
                }
            }
        } catch (IOException | Json.JsonParseException e) {
            // Fall through to the generic name - a malformed package.json
            // shouldn't stop this repo from being reported as Node.js at all.
        }
        return "Node.js";
    }

    private boolean mentionsDependency(Map<?, ?> root, String name) {
        return hasKey(root.get("dependencies"), name) || hasKey(root.get("devDependencies"), name);
    }

    private boolean hasKey(Object depsSection, String name) {
        return depsSection instanceof Map<?, ?> deps && deps.containsKey(name);
    }
}