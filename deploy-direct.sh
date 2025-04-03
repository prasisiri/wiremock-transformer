#!/bin/bash
set -e

# Check if JAR files exist
if [ ! -f "wiremock-standalone.jar" ] || [ ! -f "custom-wiremock-transformer.jar" ]; then
  echo "Error: JAR files not found. Please make sure wiremock-standalone.jar and custom-wiremock-transformer.jar are in the current directory."
  exit 1
fi

# Check if oc is available
if ! command -v oc &> /dev/null; then
  echo "Error: OpenShift CLI (oc) could not be found. Please install it first."
  exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
  echo "Error: You are not logged in to OpenShift. Please run 'oc login' first."
  exit 1
fi

echo "Current project: $(oc project -q)"
echo "Preparing deployment with direct JAR embedding..."

# Create a temporary file for the ConfigMap with embedded JARs
temp_configmap=$(mktemp)
cat <<EOF > $temp_configmap
apiVersion: v1
kind: ConfigMap
metadata:
  name: wiremock-jars
  labels:
    app: wiremock
data:
EOF

# Base64 encode the JAR files and add them to the ConfigMap
echo "  wiremock-standalone.jar: |" >> $temp_configmap
base64 wiremock-standalone.jar | sed 's/^/    /' >> $temp_configmap

echo "  custom-wiremock-transformer.jar: |" >> $temp_configmap
base64 custom-wiremock-transformer.jar | sed 's/^/    /' >> $temp_configmap

echo "Created ConfigMap with embedded JAR files"

# Apply the ConfigMap first
echo "Applying ConfigMap with JAR files..."
oc apply -f $temp_configmap

# Clean up temporary file
rm $temp_configmap

# Apply the main deployment
echo "Applying main WireMock deployment..."
oc apply -f direct-wiremock-novolume.yaml

# Wait for the deployment to be ready
echo "Waiting for deployment to complete..."
oc rollout status deployment/wiremock

# Get the route
ROUTE_HOST=$(oc get route wiremock -o jsonpath='{.spec.host}')
echo ""
echo "WireMock deployed successfully!"
echo "Access WireMock at: http://$ROUTE_HOST"
echo "Example endpoint: http://$ROUTE_HOST/example" 