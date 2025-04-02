#!/bin/bash
set -e

# Check if the JAR files exist
if [ ! -f "wiremock-standalone.jar" ] || [ ! -f "custom-wiremock-transformer.jar" ]; then
  echo "Error: JAR files not found. Please make sure wiremock-standalone.jar and custom-wiremock-transformer.jar are in the current directory."
  exit 1
fi

# Login to OpenShift
echo "Logging in to OpenShift..."
if ! oc whoami &>/dev/null; then
  echo "Please login to OpenShift using 'oc login'"
  exit 1
fi

# Get current project
PROJECT=$(oc project -q)
echo "Using project: $PROJECT"

# Create OpenShift build configuration
echo "Creating OpenShift BuildConfig..."
oc new-build --binary --name=wiremock-custom -l app=wiremock

# Start the build using the local directory
echo "Starting build from local directory..."
oc start-build wiremock-custom --from-dir=. --follow

# Apply ConfigMap and Deployment
echo "Deploying to OpenShift..."
oc apply -f wiremock-configmap.yaml

# Update the image reference in the deployment file
echo "Updating deployment file with local image..."
sed -i "s|image: wiremock-custom:latest|image: image-registry.openshift-image-registry.svc:5000/$PROJECT/wiremock-custom:latest|g" wiremock-deployment.yaml

# Apply the deployment
oc apply -f wiremock-deployment.yaml

# Wait for deployment
echo "Waiting for deployment to be ready..."
oc rollout status deployment/wiremock

# Get route
ROUTE_HOST=$(oc get route wiremock -o jsonpath='{.spec.host}')
echo ""
echo "WireMock deployed successfully!"
echo "Access WireMock at: http://$ROUTE_HOST"
echo "Example endpoint: http://$ROUTE_HOST/example"
echo ""
echo "To check logs: oc logs $(oc get pods -l app=wiremock -o name)" 