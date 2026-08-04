package com.claude.ingestor.repository;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.stream.Stream;
import org.springframework.stereotype.Component;

@Component
public class TerraformDetector implements TechnologyDetector {

    @Override
    public String technologyName() {
        return "Terraform";
    }

    @Override
    public boolean matches(Path projectDir) {
        try (Stream<Path> entries = Files.list(projectDir)) {
            return entries.anyMatch(p -> p.getFileName().toString().endsWith(".tf"));
        } catch (IOException e) {
            return false;
        }
    }
}