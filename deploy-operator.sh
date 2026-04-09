#!/bin/bash

################################################################################
# KIE Cloud Operator - Deployment Script
# 
# This script automates the deployment process as documented in 
# OPERATOR_DEPLOYMENT_GUIDE.md
#
# Usage: ./deploy-operator.sh <quay-username> [namespace]
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
    echo "Usage: $0 <quay-username> [namespace]"
    echo "Example: $0 myusername test-deploy"
    exit 1
fi

USERNAME=$1
NAMESPACE=${2:-test-deploy}
VERSION=$(go run getversion.go)

print_info "Using Quay.io username: ${USERNAME}"
print_info "Target namespace: ${NAMESPACE}"
print_info "Operator version: ${VERSION}"

# Check if oc is installed
command -v oc >/dev/null 2>&1 || { print_error "OpenShift CLI (oc) is not installed"; exit 1; }

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    print_error "Not logged in to OpenShift cluster"
    echo "Please login using: oc login <cluster-url>"
    exit 1
fi

print_success "Connected to OpenShift cluster: $(oc whoami --show-server)"

################################################################################
# Step 0: Cleanup Existing Resources
################################################################################
print_step "Step 0: Cleanup Existing Resources"

# Check and cleanup existing catalog source
if oc get catalogsource my-operator-manifests -n openshift-marketplace &> /dev/null; then
    print_warning "Found existing catalog source 'my-operator-manifests', removing it..."
    oc delete catalogsource my-operator-manifests -n openshift-marketplace
    if [ $? -eq 0 ]; then
        print_success "Existing catalog source removed"
        # Wait for catalog source pod to terminate
        print_info "Waiting for catalog source pod to terminate..."
        sleep 5
    else
        print_error "Failed to remove existing catalog source"
        exit 1
    fi
else
    print_info "No existing catalog source found"
fi

# Check and cleanup existing subscription in target namespace
if oc get namespace ${NAMESPACE} &> /dev/null; then
    if oc get subscription bamoe-businessautomation-operator -n ${NAMESPACE} &> /dev/null; then
        print_warning "Found existing subscription 'bamoe-businessautomation-operator', removing it..."
        oc delete subscription bamoe-businessautomation-operator -n ${NAMESPACE}
        if [ $? -eq 0 ]; then
            print_success "Existing subscription removed"
        else
            print_error "Failed to remove existing subscription"
            exit 1
        fi
    else
        print_info "No existing subscription found in namespace ${NAMESPACE}"
    fi
    
    # Check and cleanup existing CSV
    EXISTING_CSV=$(oc get csv -n ${NAMESPACE} -o jsonpath='{.items[?(@.spec.displayName=="IBM Business Automation (DEV)")].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$EXISTING_CSV" ]; then
        print_warning "Found existing CSV '${EXISTING_CSV}', removing it..."
        oc delete csv ${EXISTING_CSV} -n ${NAMESPACE}
        if [ $? -eq 0 ]; then
            print_success "Existing CSV removed"
            # Wait for operator pod to terminate
            print_info "Waiting for operator pod to terminate..."
            sleep 5
        else
            print_error "Failed to remove existing CSV"
            exit 1
        fi
    else
        print_info "No existing CSV found in namespace ${NAMESPACE}"
    fi
else
    print_info "Namespace ${NAMESPACE} does not exist yet"
fi

################################################################################
# Step 1: Create Catalog Source
################################################################################
print_step "Step 1: Create Catalog Source"

print_info "Creating catalog source in openshift-marketplace..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: my-operator-manifests
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/${USERNAME}/rhpam-operator-index:${VERSION}
  displayName: My Operator Catalog
  publisher: grpc
EOF

if [ $? -eq 0 ]; then
    print_success "Catalog source created"
else
    print_error "Failed to create catalog source"
    exit 1
fi

print_info "Waiting for catalog source pod to be ready..."
sleep 5

# Wait for catalog source pod
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    POD_STATUS=$(oc get pods -n openshift-marketplace -l olm.catalogSource=my-operator-manifests -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
    if [ "$POD_STATUS" = "Running" ]; then
        print_success "Catalog source pod is running"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_warning "Catalog source pod not ready after ${TIMEOUT}s, continuing anyway..."
fi

################################################################################
# Step 2: Create Target Namespace
################################################################################
print_step "Step 2: Create Target Namespace"

if oc get namespace ${NAMESPACE} &> /dev/null; then
    print_warning "Namespace ${NAMESPACE} already exists"
else
    print_info "Creating namespace ${NAMESPACE}..."
    oc create namespace ${NAMESPACE}
    print_success "Namespace created"
fi

################################################################################
# Step 3: Create OperatorGroup
################################################################################
print_step "Step 3: Create OperatorGroup"

# Check if OperatorGroup already exists
if oc get operatorgroup ${NAMESPACE}-og -n ${NAMESPACE} &> /dev/null; then
    print_warning "OperatorGroup '${NAMESPACE}-og' already exists, keeping it"
else
    print_info "Creating OperatorGroup in ${NAMESPACE}..."
    
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${NAMESPACE}-og
  namespace: ${NAMESPACE}
spec:
  targetNamespaces:
  - ${NAMESPACE}
EOF

    if [ $? -eq 0 ]; then
        print_success "OperatorGroup created"
    else
        print_error "Failed to create OperatorGroup"
        exit 1
    fi
fi

################################################################################
# Step 4: Create Subscription
################################################################################
print_step "Step 4: Create Subscription"

print_info "Creating subscription in ${NAMESPACE}..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: bamoe-businessautomation-operator
  namespace: ${NAMESPACE}
spec:
  channel: 8.x-stable
  name: bamoe-businessautomation-operator
  source: my-operator-manifests
  sourceNamespace: openshift-marketplace
EOF

if [ $? -eq 0 ]; then
    print_success "Subscription created"
else
    print_error "Failed to create subscription"
    exit 1
fi

################################################################################
# Step 5: Wait for Operator Installation
################################################################################
print_step "Step 5: Wait for Operator Installation"

print_info "Waiting for CSV to be created..."
sleep 10

TIMEOUT=300
ELAPSED=0
CSV_NAME=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    CSV_NAME=$(oc get csv -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$CSV_NAME" ]; then
        print_success "CSV found: ${CSV_NAME}"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

if [ -z "$CSV_NAME" ]; then
    print_error "CSV not created after ${TIMEOUT}s"
    print_info "Checking subscription status..."
    oc describe subscription bamoe-businessautomation-operator -n ${NAMESPACE}
    exit 1
fi

print_info "Waiting for CSV to reach Succeeded phase..."
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    CSV_PHASE=$(oc get csv ${CSV_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$CSV_PHASE" = "Succeeded" ]; then
        print_success "CSV phase: Succeeded"
        break
    elif [ "$CSV_PHASE" = "Failed" ]; then
        print_error "CSV installation failed"
        oc describe csv ${CSV_NAME} -n ${NAMESPACE}
        exit 1
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

if [ "$CSV_PHASE" != "Succeeded" ]; then
    print_error "CSV did not reach Succeeded phase after ${TIMEOUT}s"
    print_info "Current phase: ${CSV_PHASE}"
    oc describe csv ${CSV_NAME} -n ${NAMESPACE}
    exit 1
fi

################################################################################
# Step 6: Verify Operator Pod
################################################################################
print_step "Step 6: Verify Operator Pod"

print_info "Checking operator pod status..."
sleep 5

OPERATOR_POD=$(oc get pods -n ${NAMESPACE} -l name=bamoe-business-automation-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$OPERATOR_POD" ]; then
    print_error "Operator pod not found"
    oc get pods -n ${NAMESPACE}
    exit 1
fi

print_success "Operator pod: ${OPERATOR_POD}"

POD_STATUS=$(oc get pod ${OPERATOR_POD} -n ${NAMESPACE} -o jsonpath='{.status.phase}')
print_info "Pod status: ${POD_STATUS}"

if [ "$POD_STATUS" != "Running" ]; then
    print_warning "Operator pod is not in Running state"
    oc describe pod ${OPERATOR_POD} -n ${NAMESPACE}
fi

################################################################################
# Step 7: Verify KieApp API
################################################################################
print_step "Step 7: Verify KieApp API"

print_info "Checking if KieApp CRD is available..."

if oc api-resources --api-group=app.kiegroup.org | grep -q kieapps; then
    print_success "KieApp CRD is available"
    oc api-resources --api-group=app.kiegroup.org
else
    print_error "KieApp CRD not found"
    exit 1
fi

################################################################################
# Summary
################################################################################
print_step "Deployment Complete!"

echo -e "${GREEN}Summary:${NC}"
echo -e "  Namespace: ${NAMESPACE}"
echo -e "  CSV: ${CSV_NAME}"
echo -e "  Operator Pod: ${OPERATOR_POD}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo -e "  1. Create pull secret for artifactory (if needed):"
echo -e "     oc create secret docker-registry docker-artifactory \\"
echo -e "       --docker-server=na.artifactory.swg-devops.com \\"
echo -e "       --docker-username=<email> \\"
echo -e "       --docker-password=<token> \\"
echo -e "       -n ${NAMESPACE}"
echo ""
echo -e "  2. Deploy a KieApp:"
echo -e "     oc apply -f deploy/crs/v2/kieapp_rhpam_trial.yaml -n ${NAMESPACE}"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  Check operator logs:"
echo -e "    oc logs -f ${OPERATOR_POD} -n ${NAMESPACE}"
echo ""
echo -e "  Check KieApp status:"
echo -e "    oc get kieapp -n ${NAMESPACE}"
echo ""
echo -e "  Cleanup:"
echo -e "    oc delete subscription bamoe-businessautomation-operator -n ${NAMESPACE}"
echo -e "    oc delete csv ${CSV_NAME} -n ${NAMESPACE}"
echo -e "    oc delete catalogsource my-operator-manifests -n openshift-marketplace"

# Made with Bob
