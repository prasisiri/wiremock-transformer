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

# Check if the user is logged in
if ! oc whoami &> /dev/null; then
  echo "Error: You are not logged in to OpenShift. Please run 'oc login' first."
  exit 1
fi

echo "Current project: $(oc project -q)"
echo ""

# Delete any existing jar-uploader pod
if oc get pod jar-uploader &> /dev/null; then
  echo "Removing existing jar-uploader pod..."
  oc delete pod jar-uploader
  sleep 5
fi

# Create a temporary pod to upload JAR files
echo "Creating temporary pod for JAR file upload..."
oc run jar-uploader --image=registry.access.redhat.com/ubi8/ubi-minimal:latest -- sleep 3600

echo "Waiting for pod to be ready..."
oc wait --for=condition=Ready pod/jar-uploader --timeout=60s

# Copy JAR files to the pod
echo "Copying wiremock-standalone.jar to the pod..."
oc cp wiremock-standalone.jar jar-uploader:/tmp/

echo "Copying custom-wiremock-transformer.jar to the pod..."
oc cp custom-wiremock-transformer.jar jar-uploader:/tmp/

echo "Verifying files were uploaded..."
oc exec jar-uploader -- ls -lh /tmp/wiremock-standalone.jar /tmp/custom-wiremock-transformer.jar

echo ""
echo "JAR files have been uploaded successfully."
echo "Now you can apply the deployment:"
echo "$ oc apply -f direct-wiremock-deployment.yaml"
echo ""
echo "After deployment completes, you can delete the temporary pod with:"
echo "$ oc delete pod jar-uploader" 