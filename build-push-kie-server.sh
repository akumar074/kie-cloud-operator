#!/bin/bash

# Build and push script for BAMOE KIE Server with OpenShift Deployment support
# This script builds a custom KIE Server image with updated kie-server-services-openshift JAR

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

# Check if JAR file exists
JAR_FILE="/home/abkuma/Workspace/droolsjbpm-integration/kie-server-parent/kie-server-services/kie-server-services-openshift/target/kie-server-services-openshift-7.67.2.Final-redhat-00045.jar"
if [ ! -f "${JAR_FILE}" ]; then
    echo "ERROR: JAR file not found: ${JAR_FILE}"
    echo "Please build the project first using:"
    echo "  cd /home/abkuma/Workspace/droolsjbpm-integration/kie-server-parent/kie-server-services/kie-server-services-openshift"
    echo "  mvn clean install -DskipTests"
    exit 1
fi

echo "✓ JAR file found: ${JAR_FILE}"
echo ""

# Copy JAR to current directory for Docker build context
echo "Copying JAR to build context..."
cp "${JAR_FILE}" ./kie-server-services-openshift-7.67.2.Final-redhat-00045.jar

if [ $? -eq 0 ]; then
    echo "✓ JAR copied to build context"
else
    echo "✗ Failed to copy JAR file"
    exit 1
fi

echo ""

# Build the Docker image
echo "Building Docker image..."
docker build -t "${FULL_IMAGE}" .

if [ $? -eq 0 ]; then
    echo "✓ Docker image built successfully: ${FULL_IMAGE}"
else
    echo "✗ Docker build failed"
    exit 1
fi

# Clean up the copied JAR
echo ""
echo "Cleaning up..."
rm -f ./kie-server-services-openshift-7.67.2.Final-redhat-00045.jar
echo "✓ Build context cleaned"

echo ""
echo "=========================================="
echo "Pushing image to registry"
echo "=========================================="

# Push the image
echo "Pushing ${FULL_IMAGE}..."
docker push "${FULL_IMAGE}"

if [ $? -eq 0 ]; then
    echo "✓ Image pushed successfully to ${FULL_IMAGE}"
else
    echo "✗ Docker push failed"
    echo "Make sure you are logged in to quay.io: docker login quay.io"
    exit 1
fi

echo ""
echo "=========================================="
echo "Build and Push Complete!"
echo "=========================================="
echo "Image: ${FULL_IMAGE}"
echo ""
echo "To use this image:"
echo "  docker pull ${FULL_IMAGE}"
echo "  docker run -p 8080:8080 ${FULL_IMAGE}"
echo ""

# Made with Bob
