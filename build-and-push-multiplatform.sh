#!/bin/bash

################################################################################
# KIE Cloud Operator - Multiplatform Build and Push Script
# 
# This script builds and pushes multiplatform images (AMD64 + ARM64) for:
# - Operator image
# - Bundle image  
# - Index image
#
# Usage: ./build-and-push-multiplatform.sh <quay-username>
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
command -v docker >/dev/null 2>&1 || { print_error "Docker is required for multiplatform builds"; exit 1; }
command -v podman >/dev/null 2>&1 || print_warning "Podman not found, will use docker for all builds"
command -v opm >/dev/null 2>&1 || { print_error "opm is not installed. Please install Operator Package Manager"; exit 1; }

# Check Docker buildx
if ! docker buildx version &> /dev/null; then
    print_error "Docker buildx is required for multiplatform builds"
    print_info "Please install Docker Desktop or enable buildx"
    exit 1
fi

print_success "Docker buildx is available"

# Determine container runtime
if command -v podman >/dev/null 2>&1; then
    BUNDLE_RUNTIME="podman"
else
    BUNDLE_RUNTIME="docker"
fi

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
# Step 2: Build Multiplatform Operator Image
################################################################################
print_step "Step 2: Build Multiplatform Operator Image"

print_info "Building operator image for AMD64 and ARM64..."
make BUILDER=docker

if [ $? -eq 0 ]; then
    print_success "Multiplatform operator image built: quay.io/kiegroup/kie-cloud-operator:${VERSION}"
else
    print_error "Failed to build operator image"
    exit 1
fi

################################################################################
# Step 3: Tag and Push Operator Image
################################################################################
print_step "Step 3: Tag and Push Multiplatform Operator Image"

print_info "Tagging operator image for ${USERNAME}..."
docker tag quay.io/kiegroup/kie-cloud-operator:${VERSION} \
    quay.io/${USERNAME}/kie-cloud-operator:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Image tagged: quay.io/${USERNAME}/kie-cloud-operator:${VERSION}"
else
    print_error "Failed to tag operator image"
    exit 1
fi

print_info "Pushing multiplatform operator image to quay.io/${USERNAME}..."
docker push quay.io/${USERNAME}/kie-cloud-operator:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Multiplatform operator image pushed successfully"
else
    print_error "Failed to push operator image"
    print_warning "Make sure you are logged in to quay.io: docker login quay.io"
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
# Step 5: Build Multiplatform Bundle Image
################################################################################
print_step "Step 5: Build Multiplatform Bundle Image"

print_info "Building multiplatform bundle image with ${BUNDLE_RUNTIME}..."
make bundle-dev BUILDER=${BUNDLE_RUNTIME}

if [ $? -eq 0 ]; then
    print_success "Multiplatform bundle image built: quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}"
else
    print_error "Failed to build bundle image"
    # Restore CSV backup
    mv "${CSV_FILE}.backup" "${CSV_FILE}"
    exit 1
fi

################################################################################
# Step 6: Push Bundle Image
################################################################################
print_step "Step 6: Push Multiplatform Bundle Image"

print_info "Pushing multiplatform bundle image to quay.io/${USERNAME}..."
${BUNDLE_RUNTIME} push quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}

if [ $? -eq 0 ]; then
    print_success "Multiplatform bundle image pushed successfully"
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
print_step "Multiplatform Build and Push Complete!"

echo -e "${GREEN}Summary:${NC}"
echo -e "  Version: ${VERSION}"
echo -e "  Username: ${USERNAME}"
echo ""
echo -e "${GREEN}Multiplatform Images pushed:${NC}"
echo -e "  1. Operator: quay.io/${USERNAME}/kie-cloud-operator:${VERSION}"
echo -e "     Platforms: linux/amd64, linux/arm64"
echo -e "  2. Bundle:   quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}"
echo -e "     Platforms: linux/amd64, linux/arm64"
echo -e "  3. Index:    quay.io/${USERNAME}/rhpam-operator-index:${VERSION}"
echo -e "     Note: Index images are architecture-independent (metadata only)"
echo ""
echo -e "${BLUE}Verify multiplatform support:${NC}"
echo -e "  docker buildx imagetools inspect quay.io/${USERNAME}/kie-cloud-operator:${VERSION}"
echo -e "  docker buildx imagetools inspect quay.io/${USERNAME}/rhpam-operator-bundle:${VERSION}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Make images public on quay.io (if needed)"
echo -e "  2. Deploy using: ./deploy-operator.sh ${USERNAME}"
echo -e "  3. Or follow manual deployment steps in OPERATOR_DEPLOYMENT_GUIDE.md"
echo ""
print_info "CSV backup saved at: ${CSV_FILE}.backup"
print_info "To restore original CSV: mv ${CSV_FILE}.backup ${CSV_FILE}"

# Made with Bob