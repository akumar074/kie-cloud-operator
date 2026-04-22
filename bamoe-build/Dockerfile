# Multi-architecture Dockerfile for BAMOE KIE Server
# Uses different base images based on target platform
# For amd64: registry.redhat.io/ibm-bamoe/bamoe-kieserver-rhel9:8.0.9-5
# For arm64: quay.io/r_anand/bamoe-kieserver-rhel9:8.0.9

ARG TARGETARCH
ARG BASE_IMAGE_AMD64=registry.redhat.io/ibm-bamoe/bamoe-kieserver-rhel9:8.0.9-5
ARG BASE_IMAGE_ARM64=quay.io/r_anand/bamoe-kieserver-rhel9:8.0.9

# Stage for amd64
FROM --platform=linux/amd64 ${BASE_IMAGE_AMD64} AS base-amd64

# Stage for arm64
FROM --platform=linux/arm64 ${BASE_IMAGE_ARM64} AS base-arm64

# Final stage - select based on TARGETARCH
FROM base-${TARGETARCH} AS final

# Remove the old JAR files
RUN rm -f /deployments/ROOT.war/WEB-INF/lib/kie-server-services-openshift-7.67.2.Final-redhat-00045.jar && \
    rm -f /deployments/ROOT.war/WEB-INF/lib/kie-server-services-common-7.67.2.Final-redhat-00045.jar && \
    rm -f /deployments/ROOT.war/WEB-INF/lib/kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar && \
    rm -f /deployments/ROOT.war/WEB-INF/lib/drools-core-7.67.2.Final-redhat-00045.jar && \
    rm -f /deployments/ROOT.war/WEB-INF/lib/drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar

# Copy the updated JAR files (relative to build context)
COPY kie-server-services-openshift-7.67.2.Final-redhat-00045.jar /deployments/ROOT.war/WEB-INF/lib/kie-server-services-openshift-7.67.2.Final-redhat-00045.jar
COPY kie-server-services-common-7.67.2.Final-redhat-00045.jar /deployments/ROOT.war/WEB-INF/lib/kie-server-services-common-7.67.2.Final-redhat-00045.jar
COPY kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar /deployments/ROOT.war/WEB-INF/lib/kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar
COPY drools-core-7.67.2.Final-redhat-00045.jar /deployments/ROOT.war/WEB-INF/lib/drools-core-7.67.2.Final-redhat-00045.jar
COPY drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar /deployments/ROOT.war/WEB-INF/lib/drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar

# Switch to 'root' user and remove artifacts and modules
USER root
RUN [ ! -d /tmp/scripts ] || rm -rf /tmp/scripts
RUN [ ! -d /tmp/artifacts ] || rm -rf /tmp/artifacts

# Clear package manager metadata
RUN microdnf clean all && [ ! -d /var/cache/yum ] || rm -rf /var/cache/yum

# Define the user
USER 185

# Define the working directory
WORKDIR /home/jboss

# Define run cmd
CMD ["/opt/eap/bin/openshift-launch.sh"]