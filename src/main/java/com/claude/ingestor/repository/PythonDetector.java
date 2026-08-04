package com.claude.ingestor.repository;

import java.nio.file.Files;
import java.nio.file.Path;
import org.springframework.stereotype.Component;

@Component
public class PythonDetector implements TechnologyDetector {

    @Override
    public String technologyName() {
        return "Python";
    }

    @Override
    public boolean matches(Path projectDir) {
        return Files.exists(projectDir.resolve("requirements.txt")) || Files.exists(projectDir.resolve("pyproject.toml"));
    }
}