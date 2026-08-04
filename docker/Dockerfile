# syntax=docker/dockerfile:1

# --- Build stage ---
# Uses the official Maven+Temurin image so this builds identically to a
# local `mvn clean package` - no reliance on anything already installed
# on the host besides Docker itself.
FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /build

# Copy just the POM first and resolve dependencies before copying source,
# so editing a Java file doesn't invalidate the (slow) dependency-download
# Docker layer - only editing pom.xml does.
COPY pom.xml .
RUN mvn -B dependency:go-offline

COPY src ./src

# -DskipTests: keeps image builds fast and independent of test runs (which
# should happen via `mvn clean verify` / CI, not as a side effect of
# building a container image). There are no tests yet as of Phase 11
# anyway (see the README's running note on that) - this flag is a no-op
# today and forward-looking for when Phase 12 adds some.
RUN mvn -B clean package -DskipTests

# --- Runtime stage ---
# JRE only (not the full JDK) - smaller image, and this app never compiles
# anything at runtime.
FROM eclipse-temurin:21-jre-jammy

RUN useradd --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app
COPY --from=build /build/target/claude-history-ingestor-*.jar app.jar

# /data is where OFFSET_STORE_PATH points by default in docker-compose.yml -
# created and owned by the non-root user up front so the app doesn't need
# root just to create its own offset-store directory on first run.
RUN mkdir -p /data && chown -R appuser:appuser /app /data

USER appuser
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]