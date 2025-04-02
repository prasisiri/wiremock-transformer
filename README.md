# WireMock OCP Deployment

This guide provides steps to deploy WireMock with a custom transformer to OpenShift.

## Prerequisites

- OpenShift CLI (`oc`)
- Access to an OpenShift cluster
- The WireMock JAR files:
  - wiremock-standalone.jar
  - custom-wiremock-transformer.jar

## Deployment Steps

1. **Prepare your directory**

   Place these files in your working directory:
   - wiremock-standalone.jar
   - custom-wiremock-transformer.jar
   - Dockerfile
   - wiremock-deployment.yaml
   - wiremock-configmap.yaml

2. **Login to OpenShift**

   ```bash
   oc login
   # Note your current project
   oc project
   ```

3. **Create an OpenShift build**

   ```bash
   # Create a new build configuration
   oc new-build --binary --name=wiremock-custom -l app=wiremock
   
   # Start the build using the local directory
   oc start-build wiremock-custom --from-dir=. --follow
   ```

4. **Deploy WireMock**

   ```bash
   # Apply the ConfigMap with stub mappings
   oc apply -f wiremock-configmap.yaml
   
   # Update the deployment file with the correct image reference
   PROJECT=$(oc project -q)
   sed -i "s|image: wiremock-custom:latest|image: image-registry.openshift-image-registry.svc:5000/$PROJECT/wiremock-custom:latest|g" wiremock-deployment.yaml
   
   # Apply the deployment
   oc apply -f wiremock-deployment.yaml
   ```

5. **Verify deployment**

   ```bash
   # Wait for deployment
   oc rollout status deployment/wiremock
   
   # Check pods, services, and routes
   oc get pods
   oc get svc
   oc get routes
   
   # Get the route URL
   ROUTE_HOST=$(oc get route wiremock -o jsonpath='{.spec.host}')
   echo "Access WireMock at: http://$ROUTE_HOST"
   echo "Example endpoint: http://$ROUTE_HOST/example"
   ```

## Configuration

The WireMock instance is configured with:
- Custom transformer: `com.dfs.StringManipulationTransfromer`
- Global response templating enabled

## Troubleshooting

Check the logs of the WireMock pod:

```bash
oc logs $(oc get pods -l app=wiremock -o name)
``` 