#!/bin/bash

# Build and push script for BAMOE KIE Server with OpenShift Deployment support
# This script builds a custom KIE Server image with updated JAR files

set -e

# Configuration
IMAGE_NAME="quay.io/abkuma/bamoe-kieserver-rhel9"
IMAGE_TAG="8.0.9"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "Building BAMOE KIE Server Custom Image"
echo "=========================================="
echo "Image: ${FULL_IMAGE}"
echo ""

# Define JAR file paths
SERVICES_JAR="/home/abkuma/Workspace/droolsjbpm-integration/kie-server-parent/kie-server-services/kie-server-services-openshift/target/kie-server-services-openshift-7.67.2.Final-redhat-00045.jar"
SERVICES_COMMON_JAR="$HOME/.m2/repository/org/kie/server/kie-server-services-common/7.67.2.Final-redhat-00045/kie-server-services-common-7.67.2.Final-redhat-00045.jar"
CONTROLLER_JAR="$HOME/.m2/repository/org/kie/server/kie-server-controller-openshift/7.67.2.Final-redhat-00045/kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar"
DROOLS_CORE_JAR="$HOME/.m2/repository/org/drools/drools-core/7.67.2.Final-redhat-00045/drools-core-7.67.2.Final-redhat-00045.jar"
DROOLS_PROTOBUF_JAR="$HOME/.m2/repository/org/drools/drools-serialization-protobuf/7.67.2.Final-redhat-00045/drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar"

# Check if all JAR files exist
echo "Checking for required JAR files..."
MISSING_JARS=0

if [ ! -f "${SERVICES_JAR}" ]; then
    echo "✗ Services JAR not found: ${SERVICES_JAR}"
    echo "  Build with: cd /home/abkuma/Workspace/droolsjbpm-integration/kie-server-parent/kie-server-services/kie-server-services-openshift && mvn clean install -DskipTests"
    MISSING_JARS=1
else
    echo "✓ Services JAR found"
fi

if [ ! -f "${SERVICES_COMMON_JAR}" ]; then
    echo "✗ Services Common JAR not found: ${SERVICES_COMMON_JAR}"
    MISSING_JARS=1
else
    echo "✓ Services Common JAR found"
fi

if [ ! -f "${CONTROLLER_JAR}" ]; then
    echo "✗ Controller JAR not found: ${CONTROLLER_JAR}"
    MISSING_JARS=1
else
    echo "✓ Controller JAR found"
fi

if [ ! -f "${DROOLS_CORE_JAR}" ]; then
    echo "✗ Drools Core JAR not found: ${DROOLS_CORE_JAR}"
    MISSING_JARS=1
else
    echo "✓ Drools Core JAR found"
fi

if [ ! -f "${DROOLS_PROTOBUF_JAR}" ]; then
    echo "✗ Drools Protobuf JAR not found: ${DROOLS_PROTOBUF_JAR}"
    MISSING_JARS=1
else
    echo "✓ Drools Protobuf JAR found"
fi

if [ ${MISSING_JARS} -eq 1 ]; then
    echo ""
    echo "ERROR: One or more JAR files not found"
    echo "Please build the required projects first"
    exit 1
fi

echo ""

# Copy JARs to current directory for Docker build context
echo "Copying JARs to build context..."
cp "${SERVICES_JAR}" ./kie-server-services-openshift-7.67.2.Final-redhat-00045.jar
cp "${SERVICES_COMMON_JAR}" ./kie-server-services-common-7.67.2.Final-redhat-00045.jar
cp "${CONTROLLER_JAR}" ./kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar
cp "${DROOLS_CORE_JAR}" ./drools-core-7.67.2.Final-redhat-00045.jar
cp "${DROOLS_PROTOBUF_JAR}" ./drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar

if [ $? -eq 0 ]; then
    echo "✓ All JARs copied to build context"
else
    echo "✗ Failed to copy JAR files"
    exit 1
fi

echo ""

# Check if buildx is available
echo "Checking Docker buildx availability..."
if ! docker buildx version &> /dev/null; then
    echo "✗ Docker buildx is not available"
    echo "Please install Docker buildx or use Docker Desktop which includes it"
    exit 1
fi
echo "✓ Docker buildx is available"

# Create or use existing buildx builder
echo ""
echo "Setting up buildx builder..."
BUILDER_NAME="multiarch-builder"

if ! docker buildx inspect ${BUILDER_NAME} &> /dev/null; then
    echo "Creating new buildx builder: ${BUILDER_NAME}"
    docker buildx create --name ${BUILDER_NAME} --use --bootstrap
else
    echo "Using existing buildx builder: ${BUILDER_NAME}"
    docker buildx use ${BUILDER_NAME}
fi

if [ $? -eq 0 ]; then
    echo "✓ Buildx builder ready"
else
    echo "✗ Failed to setup buildx builder"
    exit 1
fi

echo ""
echo "=========================================="
echo "Building and Pushing Multi-Platform Image"
echo "=========================================="
echo "Platforms: linux/amd64, linux/arm64"
echo ""
echo "Base Images:"
echo "  - AMD64: registry.redhat.io/ibm-bamoe/bamoe-kieserver-rhel9:8.0.9-5"
echo "  - ARM64: quay.io/r_anand/bamoe-kieserver-rhel9:8.0.9"
echo ""

# Build and push multi-platform image
echo "Building and pushing ${FULL_IMAGE}..."
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --tag "${FULL_IMAGE}" \
    --push \
    .

if [ $? -eq 0 ]; then
    echo "✓ Multi-platform image built and pushed successfully: ${FULL_IMAGE}"
else
    echo "✗ Docker buildx build failed"
    # Clean up before exit
    rm -f ./kie-server-services-openshift-7.67.2.Final-redhat-00045.jar
    rm -f ./kie-server-services-common-7.67.2.Final-redhat-00045.jar
    rm -f ./kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar
    rm -f ./drools-core-7.67.2.Final-redhat-00045.jar
    rm -f ./drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar
    exit 1
fi

# Clean up the copied JARs
echo ""
echo "Cleaning up..."
rm -f ./kie-server-services-openshift-7.67.2.Final-redhat-00045.jar
rm -f ./kie-server-services-common-7.67.2.Final-redhat-00045.jar
rm -f ./kie-server-controller-openshift-7.67.2.Final-redhat-00045.jar
rm -f ./drools-core-7.67.2.Final-redhat-00045.jar
rm -f ./drools-serialization-protobuf-7.67.2.Final-redhat-00045.jar
echo "✓ Build context cleaned"

echo ""
echo "=========================================="
echo "Build and Push Complete!"
echo "=========================================="
echo "Image: ${FULL_IMAGE}"
echo "Platforms: linux/amd64, linux/arm64"
echo ""
echo "To use this image:"
echo "  docker pull ${FULL_IMAGE}"
echo "  docker run -p 8080:8080 ${FULL_IMAGE}"
echo ""
echo "To verify multi-platform support:"
echo "  docker buildx imagetools inspect ${FULL_IMAGE}"
echo ""

# Made with Bob
