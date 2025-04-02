# Direct WireMock Deployment on OpenShift

This guide provides steps to directly deploy WireMock to OpenShift without building a custom image.

## Prerequisites

- OpenShift CLI (`oc`)
- Access to an OpenShift cluster
- The WireMock JAR files:
  - wiremock-standalone.jar
  - custom-wiremock-transformer.jar

## Deployment Steps

1. **Login to OpenShift**

   ```bash
   oc login
   ```

2. **Create a new project or select an existing one**

   ```bash
   oc new-project wiremock-project   # Create a new project
   # OR
   oc project your-existing-project  # Use existing project
   ```

3. **Upload JAR files to OpenShift**

   Create a temporary pod and upload your JAR files:

   ```bash
   # Create a temporary pod
   oc run jar-uploader --image=registry.access.redhat.com/ubi8/ubi-minimal:latest -- sleep 3600
   
   # Wait for the pod to be ready
   oc wait --for=condition=Ready pod/jar-uploader
   
   # Copy JAR files to the pod
   oc cp wiremock-standalone.jar jar-uploader:/tmp/
   oc cp custom-wiremock-transformer.jar jar-uploader:/tmp/
   
   # Verify the files were uploaded correctly
   oc exec jar-uploader -- ls -lh /tmp/wiremock-standalone.jar /tmp/custom-wiremock-transformer.jar
   ```

4. **Deploy WireMock to OpenShift**

   ```bash
   # Apply the deployment configuration
   oc apply -f direct-wiremock-deployment.yaml
   
   # Wait for the deployment to be ready
   oc wait --for=condition=Ready pod -l app=wiremock
   ```

5. **Test the deployment**

   ```bash
   # Get the route URL
   oc get route wiremock -o jsonpath='{.spec.host}'
   
   # Test the example endpoint
   curl http://$(oc get route wiremock -o jsonpath='{.spec.host}')/example
   ```

6. **Clean up (optional)**

   Once the WireMock deployment is running, you can remove the temporary pod:

   ```bash
   oc delete pod jar-uploader
   ```

## How It Works

The deployment configuration (`direct-wiremock-deployment.yaml`) includes:

1. **ConfigMaps**
   - `wiremock-stubs`: Contains example stub mappings
   - `wiremock-init-script`: Contains the script for copying JAR files

2. **Deployment**
   - Uses Red Hat UBI 8 OpenJDK 11 container (registry.access.redhat.com/ubi8/openjdk-11)
   - Uses a Red Hat UBI 8 Minimal init container to copy JAR files
   - Mounts the ConfigMap as a volume for stub mappings
   - Runs WireMock with your custom transformer

3. **Service and Route**
   - Creates a Service to expose WireMock within the cluster
   - Creates a Route for external access

## Troubleshooting

If the deployment is not working as expected:

1. **Check pod status**

   ```bash
   oc get pods -l app=wiremock
   ```

2. **Check logs of the WireMock container**

   ```bash
   oc logs $(oc get pods -l app=wiremock -o name) -c wiremock
   ```

3. **Check logs of the init container**

   ```bash
   oc logs $(oc get pods -l app=wiremock -o name) -c jar-loader
   ```

4. **Verify JAR files were copied correctly**

   ```bash
   oc exec $(oc get pods -l app=wiremock -o name) -- ls -lh /opt/wiremock/
   ``` 