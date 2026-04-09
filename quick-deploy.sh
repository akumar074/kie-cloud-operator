#!/bin/bash
set -e

echo "=========================================="
echo "Quick Deploy - Updated Operator"
echo "=========================================="
echo ""

NAMESPACE="bamoe-v8-sanity-test"
OPERATOR_IMAGE="quay.io/abkuma/kie-cloud-operator:8.0.9"

echo "Step 1: Build and push operator image"
echo "--------------------------------------"
docker build -t $OPERATOR_IMAGE -f build/Dockerfile .
docker push $OPERATOR_IMAGE
echo "✓ Image pushed"
echo ""

echo "Step 2: Restart operator pod"
echo "-----------------------------"
OPERATOR_POD=$(oc get pods -n $NAMESPACE -l name=bamoe-business-automation-operator -o jsonpath='{.items[0].metadata.name}')
echo "Current operator pod: $OPERATOR_POD"
oc delete pod $OPERATOR_POD -n $NAMESPACE
echo "✓ Operator pod deleted, waiting for new pod..."
sleep 10

NEW_POD=$(oc get pods -n $NAMESPACE -l name=bamoe-business-automation-operator -o jsonpath='{.items[0].metadata.name}')
echo "New operator pod: $NEW_POD"
oc wait --for=condition=ready pod/$NEW_POD -n $NAMESPACE --timeout=120s
echo "✓ New operator pod ready"
echo ""

echo "Step 3: Delete and recreate KieApp"
echo "-----------------------------------"
oc delete kieapp rhpam-trial -n $NAMESPACE
echo "Waiting for cleanup..."
sleep 15

cat <<EOF | oc apply -f -
apiVersion: app.kiegroup.org/v2
kind: KieApp
metadata:
  name: rhpam-trial
  namespace: $NAMESPACE
spec:
  environment: rhpam-trial
EOF
echo "✓ KieApp recreated"
echo ""

echo "Step 4: Wait for deployments"
echo "----------------------------"
echo "Waiting for Business Central..."
oc wait --for=condition=available --timeout=300s deployment/rhpam-trial-rhpamcentr -n $NAMESPACE || true
echo "Waiting for KIE Server..."
oc wait --for=condition=available --timeout=300s deployment/rhpam-trial-kieserver -n $NAMESPACE || true
echo ""

echo "Step 5: Verify the fix"
echo "----------------------"
echo "Startup strategy:"
oc get kieapp rhpam-trial -n $NAMESPACE -o jsonpath='{.status.applied.commonConfig.startupStrategy.strategyName}'
echo ""
echo ""
echo "KIE Server env:"
oc get deployment rhpam-trial-kieserver -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="KIE_SERVER_STARTUP_STRATEGY")].value}'
echo ""
echo ""

echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Check KIE Server logs:"
echo "  oc logs -l app=rhpam-trial-kieserver -n $NAMESPACE | grep -i controller"

# Made with Bob
