FROM registry.access.redhat.com/ubi8/openjdk-11:latest

USER root
WORKDIR /opt/wiremock

# Copy the JAR files
COPY wiremock-standalone.jar /opt/wiremock/
COPY custom-wiremock-transformer.jar /opt/wiremock/

# Set permissions
RUN chgrp -R 0 /opt/wiremock && \
    chmod -R g=u /opt/wiremock

# Set the user to a non-root user (OpenShift requirement)
USER 1001

# Expose the default WireMock port
EXPOSE 8080

# Command to run WireMock with your custom transformer
ENTRYPOINT ["java", "-cp", "wiremock-standalone.jar:custom-wiremock-transformer.jar", "com.github.tomakehurst.wiremock.standalone.WiremockServerRunner", "--extensions", "com.dfs.StringManipulationTransfromer", "--global-response-templating"] 