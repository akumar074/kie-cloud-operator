#!/bin/bash

################################################################################
# KIE Cloud Operator - Build and Push Script
# 
# This script automates the build process from Environment Setup to Push Index Image
# as documented in OPERATOR_DEPLOYMENT_GUIDE.md
#
# Usage: ./build-and-push.sh <quay-username>
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${GREEN}===================================================${NC}"
    echo -e "${GREEN}$1${NC}"
    echo -e "${GREEN}===================================================${NC}\n"
}

# Check if username is provided
if [ -z "$1" ]; then
    print_error "Username not provided!"
    echo "Usage: $0 <quay-username>"
    echo "Example: $0 myusername"
    exit 1
fi

USERNAME=$1
print_info "Using Quay.io username: ${USERNAME}"

################################################################################
# Step 1: Environment Setup
################################################################################
print_step "Step 1: Environment Setup"

# Check required tools
print_info "Checking required tools..."

command -v go >/dev/null 2>&1 || { print_error "Go is not installed. Please install Go v1.18.x"; exit 1; }
command -v operator-sdk >/dev/null 2>&1 || { print_error "operator-sdk is not installed. Please install operator-sdk v0.19.2"; exit 1; }
command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1 || { print_error "Neither Docker nor Podman is installed"; exit 1; }
command -v opm >/dev/null 2>&1 || { print_error "opm is not installed. Please install Operator Package Manager"; exit 1; }

# Determine available container runtimes
DOCKER_AVAILABLE=false
PODMAN_AVAILABLE=false

if command -v docker >/dev/null 2>&1; then
    DOCKER_AVAILABLE=true
fi

if command -v podman >/dev/null 2>&1; then
    PODMAN_AVAILABLE=true
fi

if [ "$DOCKER_AVAILABLE" = false ] && [ "$PODMAN_AVAILABLE" = false ]; then
    print_error "Neither Docker nor Podman is installed"
    exit 1
fi

# Use docker for operator image (as per documentation)
if [ "$DOCKER_AVAILABLE" = true ]; then
    OPERATOR_RUNTIME="docker"
else
    OPERATOR_RUNTIME="podman"
    print_warning "Docker not available, using podman for operator image"
fi

# Use podman for bundle and index images (as per documentation)
if [ "$PODMAN_AVAILABLE" = true ]; then
    BUNDLE_RUNTIME="podman"
else
    BUNDLE_RUNTIME="docker"
    print_warning "Podman not available, using docker for bundle/index images"
fi

print_info "Operator image will use: ${OPERATOR_RUNTIME}"
print_info "Bundle/Index images will use: ${BUNDLE_RUNTIME}"

# Get operator version
print_info "Getting operator version..."
VERSION=$(go run getversion.go)
if [ -z "$VERSION" ]; then
    print_error "Failed to get version"
    exit 1
fi
print_success "Version: ${VERSION}"

# Export environment variables
export USERNAME
export VERSION

################################################################################
# Step 2: Build Operator Image
################################################################################
print_step "Step 2: Build Operator Image"

print_info "Building operator image with ${OPERATOR_RUNTIME}..."
make BUILDER=${OPERATOR_RUNTIME}

if [ $? -eq 0 ]; then
    print_success "Operator image built: quay.io/kiegroup/kie-cloud-operator:${VERSION}"
else
    print_error "Failed to build operator image"
    exit 1
fi

################################################################################
# Step 3: Tag and Push Operator Image
################################################################################
print_step "Step 3: Tag and Push Operator Image"

print_info "Tagging operator image for ${USERNAME}..."
${OPERATOR_RUNTIME} tag quay.io/kiegroup/kie-cloud-operator:${VERSION} \
    quay.io/${USERNAME}/kie-cloud-operator:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Image tagged: quay.io/${USERNAME}/kie-cloud-operator:${VERSION}"
else
    print_error "Failed to tag operator image"
    exit 1
fi

print_info "Pushing operator image to quay.io/${USERNAME}..."
${OPERATOR_RUNTIME} push quay.io/${USERNAME}/kie-cloud-operator:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Operator image pushed successfully"
else
    print_error "Failed to push operator image"
    print_warning "Make sure you are logged in to quay.io: ${OPERATOR_RUNTIME} login quay.io"
    exit 1
fi

################################################################################
# Step 4: Update CSV with Custom Image
################################################################################
print_step "Step 4: Update CSV with Custom Image"

CSV_FILE="deploy/olm-catalog/dev/${VERSION}-1/manifests/bamoe-businessautomation-operator.clusterserviceversion.yaml"

if [ ! -f "$CSV_FILE" ]; then
    print_error "CSV file not found: ${CSV_FILE}"
    exit 1
fi

print_info "Updating CSV file: ${CSV_FILE}"

# Backup original CSV
cp "${CSV_FILE}" "${CSV_FILE}.backup"
print_info "Backup created: ${CSV_FILE}.backup"

# Update the image reference in CSV
sed -i.tmp "s|image: quay.io/kiegroup/kie-cloud-operator:${VERSION}|image: quay.io/${USERNAME}/kie-cloud-operator:${VERSION}|g" "${CSV_FILE}"
rm -f "${CSV_FILE}.tmp"

# Verify the change
if grep -q "quay.io/${USERNAME}/kie-cloud-operator:${VERSION}" "${CSV_FILE}"; then
    print_success "CSV updated with custom image reference"
else
    print_error "Failed to update CSV file"
    # Restore backup
    mv "${CSV_FILE}.backup" "${CSV_FILE}"
    exit 1
fi

################################################################################
# Step 5: Build Bundle Image
################################################################################
print_step "Step 5: Build Bundle Image"

print_info "Building bundle image with ${BUNDLE_RUNTIME}..."
make bundle-dev BUILDER=${BUNDLE_RUNTIME}

if [ $? -eq 0 ]; then
    print_success "Bundle image built: quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}"
else
    print_error "Failed to build bundle image"
    # Restore CSV backup
    mv "${CSV_FILE}.backup" "${CSV_FILE}"
    exit 1
fi

################################################################################
# Step 6: Push Bundle Image
################################################################################
print_step "Step 6: Push Bundle Image"

print_info "Pushing bundle image to quay.io/${USERNAME}..."
${BUNDLE_RUNTIME} push quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Bundle image pushed successfully"
else
    print_error "Failed to push bundle image"
    exit 1
fi

################################################################################
# Step 7: Build Index Image
################################################################################
print_step "Step 7: Build Index Image"

print_info "Building catalog index image..."
opm index add \
    --bundles quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION} \
    --tag quay.io/${USERNAME}/rhpam-operator-index:${VERSION} \
    --container-tool ${BUNDLE_RUNTIME}

if [ $? -eq 0 ]; then
    print_success "Index image built: quay.io/${USERNAME}/rhpam-operator-index:${VERSION}"
else
    print_error "Failed to build index image"
    exit 1
fi

################################################################################
# Step 8: Push Index Image
################################################################################
print_step "Step 8: Push Index Image"

print_info "Pushing index image to quay.io/${USERNAME}..."
${BUNDLE_RUNTIME} push quay.io/${USERNAME}/rhpam-operator-index:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Index image pushed successfully"
else
    print_error "Failed to push index image"
    exit 1
fi

################################################################################
# Summary
################################################################################
print_step "Build and Push Complete!"

echo -e "${GREEN}Summary:${NC}"
echo -e "  Version: ${VERSION}"
echo -e "  Username: ${USERNAME}"
echo ""
echo -e "${GREEN}Images pushed:${NC}"
echo -e "  1. Operator: quay.io/${USERNAME}/kie-cloud-operator:${VERSION}"
echo -e "  2. Bundle:   quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}"
echo -e "  3. Index:    quay.io/${USERNAME}/rhpam-operator-index:${VERSION}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Make images public on quay.io (if needed)"
echo -e "  2. Deploy using: ./deploy-operator.sh ${USERNAME}"
echo -e "  3. Or follow manual deployment steps in OPERATOR_DEPLOYMENT_GUIDE.md"
echo ""
print_info "CSV backup saved at: ${CSV_FILE}.backup"
print_info "To restore original CSV: mv ${CSV_FILE}.backup ${CSV_FILE}"

# Made with Bob
