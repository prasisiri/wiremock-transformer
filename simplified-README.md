# Direct WireMock Deployment on OpenShift

This guide provides steps to directly deploy WireMock to OpenShift without building a custom image.

## Prerequisites

- OpenShift CLI (`oc`)
- Access to an OpenShift cluster
- The WireMock JAR files:
  - wiremock-standalone.jar
  - custom-wiremock-transformer.jar

## Simplified Deployment Steps

1. **Login to OpenShift**

   ```bash
   oc login
   ```

2. **Create a new project or use an existing one**

   ```bash
   oc new-project wiremock-project   # Optional - create a new project
   # OR
   oc project your-existing-project  # Use existing project
   ```

3. **Copy your JAR files to OpenShift**

   ```bash
   # Create a temporary pod to upload JAR files
   oc run jar-uploader --image=busybox -- sleep 3600
   
   # Wait for the pod to be ready
   oc wait --for=condition=Ready pod/jar-uploader
   
   # Copy JAR files to the pod
   oc cp wiremock-standalone.jar jar-uploader:/tmp/
   oc cp custom-wiremock-transformer.jar jar-uploader:/tmp/
   ```

4. **Apply the deployment**

   ```bash
   # Apply the deployment manifest
   oc apply -f direct-wiremock-deployment.yaml
   
   # Wait for the pod to be ready
   oc wait --for=condition=Ready pod -l app=wiremock
   ```

5. **Check the deployment**

   ```bash
   # Get the route URL
   oc get route wiremock -o jsonpath='{.spec.host}'
   
   # Test the example endpoint
   curl http://$(oc get route wiremock -o jsonpath='{.spec.host}')/example
   ```

## How It Works

This deployment uses:
1. A standard Java container (eclipse-temurin:11-jre)
2. An init container to copy the JAR files from a shared volume 
3. ConfigMaps for stub mappings and initialization scripts
4. A direct Java command to run WireMock with your custom transformer

## Troubleshooting

Check the logs of the WireMock pod:

```bash
oc logs $(oc get pods -l app=wiremock -o name)
```

If the init container fails, check its logs:

```bash
oc logs $(oc get pods -l app=wiremock -o name) -c jar-loader
``` 