package com.claude.ingestor.repository;

import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.stereotype.Component;

@Component
public class JavaGradleDetector implements TechnologyDetector {

    @Override
    public String technologyName() {
        return "Java (Gradle)";
    }

    @Override
    public boolean matches(Path projectDir) {
        return Files.exists(projectDir.resolve("build.gradle")) || Files.exists(projectDir.resolve("build.gradle.kts"));
    }
}