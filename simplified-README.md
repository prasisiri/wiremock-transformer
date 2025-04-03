# Direct WireMock Deployment on OpenShift

This guide provides steps to directly deploy WireMock to OpenShift without building a custom image.

## Prerequisites

- OpenShift CLI (`oc`)
- Access to an OpenShift cluster
- The WireMock JAR files:
  - wiremock-standalone.jar
  - custom-wiremock-transformer.jar
- Red Hat account (for registry.redhat.io access)

## Deployment Steps

### STEP 1: Initial Setup

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

3. **Create an image pull secret for registry.redhat.io**

   The registry.redhat.io requires authentication to pull images.

   ```bash
   # Create a secret with your Red Hat credentials
   oc create secret docker-registry redhat-pull-secret \
     --docker-server=registry.redhat.io \
     --docker-username=YOUR_RED_HAT_USERNAME \
     --docker-password=YOUR_RED_HAT_PASSWORD \
     --docker-email=YOUR_EMAIL
   
   # Link the secret to your service account
   oc secrets link default redhat-pull-secret --for=pull
   ```

4. **Verify your JAR files**

   Before proceeding, verify your JAR files:

   ```bash
   # Check that wiremock-standalone.jar contains the WireMockServerRunner class
   jar tvf wiremock-standalone.jar | grep WireMockServerRunner
   
   # Make sure your custom transformer JAR also exists
   ls -lh custom-wiremock-transformer.jar
   ```

### STEP 2: Create the PVC and Upload JAR Files

5. **Create only the PVC first**

   Extract just the PVC from the deployment YAML and apply it:

   ```bash
   # Create a file for the PVC only
   cat > wiremock-pvc.yaml << EOF
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: wiremock-jars
     labels:
       app: wiremock
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 100Mi
   EOF
   
   # Apply just the PVC
   oc apply -f wiremock-pvc.yaml
   
   # Wait for the PVC to be bound
   oc get pvc wiremock-jars -w
   ```

6. **Create a pod to copy JAR files to the PVC**

   ```bash
   # Create a helper pod that mounts the PVC
   oc run jar-uploader --image=registry.redhat.io/ubi8/ubi:latest \
     --overrides='
     {
       "spec": {
         "volumes": [
           {
             "name": "wiremock-jars",
             "persistentVolumeClaim": {
               "claimName": "wiremock-jars"
             }
           }
         ],
         "containers": [
           {
             "name": "jar-uploader",
             "image": "registry.redhat.io/ubi8/ubi:latest",
             "command": ["sleep", "3600"],
             "volumeMounts": [
               {
                 "name": "wiremock-jars",
                 "mountPath": "/opt/wiremock"
               }
             ]
           }
         ]
       }
     }'
   
   # Wait for the pod to be ready
   oc wait --for=condition=Ready pod/jar-uploader
   ```

7. **Copy JAR files to the PVC**

   ```bash
   # Copy JAR files directly to the mounted PVC
   oc cp wiremock-standalone.jar jar-uploader:/opt/wiremock/
   oc cp custom-wiremock-transformer.jar jar-uploader:/opt/wiremock/
   
   # Verify the files were uploaded correctly and check their sizes
   oc exec jar-uploader -- ls -lh /opt/wiremock/
   
   # Verify the JAR contents within the pod
   oc exec jar-uploader -- sh -c "jar tvf /opt/wiremock/wiremock-standalone.jar | grep WireMockServerRunner"
   ```

8. **Cleanup the jar-uploader pod**

   ```bash
   # Delete the helper pod when file upload is confirmed
   oc delete pod jar-uploader
   ```

### STEP 3: Deploy WireMock

9. **Deploy WireMock only after JAR files are in place**

   ```bash
   # Apply the full deployment (excluding the PVC which is already created)
   oc apply -f direct-wiremock-deployment.yaml
   
   # Wait for the deployment to be ready
   oc rollout status deployment/wiremock
   ```

10. **Test the deployment**

    ```bash
    # Get the route URL
    oc get route wiremock -o jsonpath='{.spec.host}'
    
    # Test the example endpoint
    curl http://$(oc get route wiremock -o jsonpath='{.spec.host}')/example
    ```

## How It Works

The deployment process works in three distinct phases:

1. **Setup Phase**
   - Create the PVC for persistent storage of JAR files
   - Create a temporary pod to access this PVC

2. **JAR Upload Phase**
   - Upload JAR files to the PVC using the temporary pod
   - Verify the files are correctly uploaded
   - Clean up the temporary pod

3. **Deployment Phase**
   - Deploy WireMock which mounts the same PVC
   - WireMock pod can now access the previously uploaded JAR files
   - WireMock starts using these JAR files

This ensures that the JAR files are available on the persistent volume **before** the WireMock container tries to access them.

## Deployment Components

The deployment configuration (`direct-wiremock-deployment.yaml`) includes:

1. **ConfigMap**
   - `wiremock-stubs`: Contains example stub mappings

2. **PersistentVolumeClaim**
   - `wiremock-jars`: Provides persistent storage for the JAR files

3. **Deployment**
   - Uses Red Hat UBI 8 OpenJDK 11 container (registry.redhat.io/ubi8/openjdk-11)
   - Uses `-jar` option to run the WireMock standalone JAR 
   - Uses `--classpath` option to add custom transformer JAR
   - Mounts the PVC to access the JAR files
   - Mounts the ConfigMap as a volume for stub mappings

4. **Service and Route**
   - Creates a Service to expose WireMock within the cluster
   - Creates a Route for external access

## Troubleshooting

If the deployment is not working as expected:

1. **Check pod status**

   ```bash
   oc get pods -l app=wiremock
   ```

2. **Check if image pull errors are occurring**

   If you see `ImagePullBackOff` errors, check your image pull secret:
   
   ```bash
   # Verify the pull secret is linked to your service account
   oc get serviceaccount default -o yaml
   
   # Check events for image pull issues
   oc get events
   ```

3. **Check logs of the WireMock container**

   ```bash
   oc logs $(oc get pods -l app=wiremock -o name)
   ```

4. **Verify JAR files exist on the PVC and are not corrupted**

   ```bash
   # Create a temporary pod to check the PVC contents
   oc run pvc-checker --image=registry.redhat.io/ubi8/ubi:latest --rm -it \
     --overrides='
     {
       "spec": {
         "volumes": [
           {
             "name": "wiremock-jars",
             "persistentVolumeClaim": {
               "claimName": "wiremock-jars"
             }
           }
         ],
         "containers": [
           {
             "name": "pvc-checker",
             "image": "registry.redhat.io/ubi8/ubi:latest",
             "command": ["sh", "-c", "ls -lh /opt/wiremock/ && jar tvf /opt/wiremock/wiremock-standalone.jar | grep -i wiremock"],
             "volumeMounts": [
               {
                 "name": "wiremock-jars",
                 "mountPath": "/opt/wiremock"
               }
             ]
           }
         ]
       }
     }'
   ```

5. **If the error persists, try running directly with Java**

   ```bash
   # Create a pod that mounts the PVC to test the Java command directly
   oc run wiremock-test --image=registry.redhat.io/ubi8/openjdk-11:latest --rm -it \
     --overrides='
     {
       "spec": {
         "volumes": [
           {
             "name": "wiremock-jars",
             "persistentVolumeClaim": {
               "claimName": "wiremock-jars"
             }
           }
         ],
         "containers": [
           {
             "name": "wiremock-test",
             "image": "registry.redhat.io/ubi8/openjdk-11:latest",
             "command": ["sh", "-c", "cd /opt/wiremock && java -jar wiremock-standalone.jar --help"],
             "volumeMounts": [
               {
                 "name": "wiremock-jars",
                 "mountPath": "/opt/wiremock"
               }
             ]
           }
         ]
       }
     }'
   ``` 