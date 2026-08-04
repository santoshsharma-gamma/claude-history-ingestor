package com.claude.ingestor.repository;

import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.stereotype.Component;

@Component
public class JavaMavenDetector implements TechnologyDetector {

    @Override
    public String technologyName() {
        return "Java (Maven)";
    }

    @Override
    public boolean matches(Path projectDir) {
        return Files.exists(projectDir.resolve("pom.xml"));
    }
}
