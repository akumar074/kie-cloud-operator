#!/bin/bash

# Build and push script for both BAMOE KIE Server and Business Central images
# This script executes both build scripts sequentially

set -e

echo "=========================================="
echo "Building All BAMOE Custom Images"
echo "=========================================="
echo ""

# Build and push KIE Server
echo "=========================================="
echo "Step 1/2: Building KIE Server Image"
echo "=========================================="
echo ""

if [ -f "./build-push-kie-server.sh" ]; then
    ./build-push-kie-server.sh
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ KIE Server build and push completed successfully"
    else
        echo ""
        echo "✗ KIE Server build and push failed"
        exit 1
    fi
else
    echo "✗ build-push-kie-server.sh not found"
    exit 1
fi

echo ""
echo "=========================================="
echo "Step 2/2: Building Business Central Image"
echo "=========================================="
echo ""

# Build and push Business Central
if [ -f "./build-push-businesscentral.sh" ]; then
    ./build-push-businesscentral.sh
    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Business Central build and push completed successfully"
    else
        echo ""
        echo "✗ Business Central build and push failed"
        exit 1
    fi
else
    echo "✗ build-push-businesscentral.sh not found"
    exit 1
fi

echo ""
echo "=========================================="
echo "All Builds Complete!"
echo "=========================================="
echo ""
echo "Images built and pushed:"
echo "  1. quay.io/abkuma/bamoe-kieserver-rhel9:8.0.9"
echo "  2. quay.io/abkuma/bamoe-businesscentral-rhel9:8.0.9"
echo ""
echo "Both images are now available in the registry."
echo ""

# Made with Bob