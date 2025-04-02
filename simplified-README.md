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

4. **Apply the deployment to create the PVC**

   ```bash
   # Apply the deployment to create the PVC first
   oc apply -f direct-wiremock-deployment.yaml
   
   # Wait for the PVC to be bound
   oc get pvc wiremock-jars
   ```

5. **Create a pod to copy JAR files**

   ```bash
   # Create a helper pod that mounts the same PVC
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

6. **Copy JAR files to the PVC**

   ```bash
   # Copy JAR files directly to the mounted PVC
   oc cp wiremock-standalone.jar jar-uploader:/opt/wiremock/
   oc cp custom-wiremock-transformer.jar jar-uploader:/opt/wiremock/
   
   # Verify the files were uploaded correctly
   oc exec jar-uploader -- ls -lh /opt/wiremock/
   ```

7. **Delete the helper pod and restart WireMock**

   ```bash
   # Delete the helper pod
   oc delete pod jar-uploader
   
   # Restart the WireMock pod to make sure it sees the JAR files
   oc rollout restart deployment/wiremock
   
   # Wait for the deployment to be ready
   oc rollout status deployment/wiremock
   ```

8. **Test the deployment**

   ```bash
   # Get the route URL
   oc get route wiremock -o jsonpath='{.spec.host}'
   
   # Test the example endpoint
   curl http://$(oc get route wiremock -o jsonpath='{.spec.host}')/example
   ```

## How It Works

The deployment configuration (`direct-wiremock-deployment.yaml`) includes:

1. **ConfigMap**
   - `wiremock-stubs`: Contains example stub mappings

2. **PersistentVolumeClaim**
   - `wiremock-jars`: Provides persistent storage for the JAR files

3. **Deployment**
   - Uses Red Hat UBI 8 OpenJDK 11 container (registry.redhat.io/ubi8/openjdk-11)
   - Mounts the PVC to access the JAR files
   - Mounts the ConfigMap as a volume for stub mappings
   - Runs WireMock with your custom transformer

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

4. **Verify JAR files exist on the PVC**

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
             "command": ["ls", "-lh", "/opt/wiremock"],
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