# syntax=docker/dockerfile:1

# ---------- Stage 1: build (JDK + Maven, ~600MB, thrown away) ----------
FROM maven:3.9.11-eclipse-temurin-21 AS build

WORKDIR /build

# Layer 1: pom.xml alone -> `dependency:go-offline` downloads EVERY
# dependency into ~/.m2 and caches it in its own layer.
# Changing a Java file later only re-runs the compile, not the download.
# (Before this: every code change re-downloaded Maven for ~71s.)
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Layer 2: sources -> only this layer (and compile) is invalidated by code changes
COPY src ./src
RUN mvn -B -q clean package -DskipTests

# ---------- Stage 2: runtime (JRE only, ~250MB) ------------------------
# The build tools never reach production: smaller image = faster pull,
# smaller attack surface.
FROM eclipse-temurin:21-jre

WORKDIR /app

RUN useradd --create-home --uid 10001 appuser
COPY --from=build --chown=appuser:appuser /build/target/roadmap-service-1.0.0.jar app.jar

USER appuser

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
