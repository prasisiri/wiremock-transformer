# Direct WireMock Deployment on OpenShift (No PVC)

This guide provides steps to directly deploy WireMock to OpenShift with JAR files embedded in the deployment.

## How This Works

This approach:
1. Encodes the JAR files as base64 and stores them in a ConfigMap
2. Uses an init container to decode the JAR files and place them in a shared emptyDir volume
3. The main WireMock container then accesses these JAR files

This eliminates the need for a Persistent Volume Claim (PVC) and simplifies the deployment process.

## Prerequisites

- OpenShift CLI (`oc`)
- Access to an OpenShift cluster
- The WireMock JAR files in your local directory:
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

4. **Verify your JAR files exist and are valid**

   ```bash
   # Check the JAR files exist
   ls -lh wiremock-standalone.jar custom-wiremock-transformer.jar
   
   # Verify the WireMock JAR is valid
   jar tvf wiremock-standalone.jar | grep WireMockServerRunner
   ```

5. **Create a ConfigMap with base64-encoded JAR files**

   ```bash
   # Create a file for the ConfigMap
   cat > wiremock-jars-configmap.yaml << EOF
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: wiremock-jars
     labels:
       app: wiremock
   data:
     wiremock-standalone.jar: |
   $(base64 wiremock-standalone.jar | sed 's/^/    /')
     custom-wiremock-transformer.jar: |
   $(base64 custom-wiremock-transformer.jar | sed 's/^/    /')
   EOF
   
   # Apply the ConfigMap
   oc apply -f wiremock-jars-configmap.yaml
   ```

6. **Create a ConfigMap for stubs**

   ```bash
   # Create a file for the stubs ConfigMap
   cat > wiremock-stubs-configmap.yaml << EOF
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: wiremock-stubs
     labels:
       app: wiremock
   data:
     example.json: |
       {
         "request": {
           "method": "GET",
           "url": "/example"
         },
         "response": {
           "status": 200,
           "body": "{{request.path.[0]}}",
           "headers": {
             "Content-Type": "text/plain"
           },
           "transformers": ["response-template", "com.dfs.StringManipulationTransfromer"]
         }
       }
   EOF
   
   # Apply the stubs ConfigMap
   oc apply -f wiremock-stubs-configmap.yaml
   ```

7. **Create the WireMock Deployment**

   ```bash
   # Create the deployment file
   cat > wiremock-deployment.yaml << EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: wiremock
     labels:
       app: wiremock
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: wiremock
     template:
       metadata:
         labels:
           app: wiremock
       spec:
         volumes:
         - name: wiremock-data
           emptyDir: {}
         - name: stubs-volume
           configMap:
             name: wiremock-stubs
         - name: jar-config
           configMap:
             name: wiremock-jars
         initContainers:
         - name: copy-jars
           image: registry.redhat.io/ubi8/ubi:latest
           command: ["/bin/sh", "-c"]
           args:
           - |
             mkdir -p /wiremock
             for file in \$(ls /jar-config/); do
               if [ "\$file" != "placeholder" ]; then
                 echo "Processing \$file..."
                 base64 -d "/jar-config/\$file" > "/wiremock/\$file"
                 echo "Created /wiremock/\$file"
                 ls -la "/wiremock/\$file"
               fi
             done
           volumeMounts:
           - name: wiremock-data
             mountPath: /wiremock
           - name: jar-config
             mountPath: /jar-config
         containers:
         - name: wiremock
           image: registry.redhat.io/ubi8/openjdk-11:latest
           command: ["java"]
           args: ["-jar", "/opt/wiremock/wiremock-standalone.jar", "--extensions", "com.dfs.StringManipulationTransfromer", "--classpath", "/opt/wiremock/custom-wiremock-transformer.jar", "--global-response-templating", "--root-dir", "/opt/wiremock/mappings"]
           ports:
           - containerPort: 8080
           resources:
             requests:
               memory: "512Mi"
               cpu: "200m"
             limits:
               memory: "1Gi"
               cpu: "500m"
           readinessProbe:
             httpGet:
               path: /__admin/
               port: 8080
             initialDelaySeconds: 30
             periodSeconds: 10
             timeoutSeconds: 5
             failureThreshold: 6
           volumeMounts:
           - name: wiremock-data
             mountPath: /opt/wiremock
           - name: stubs-volume
             mountPath: /opt/wiremock/mappings
   EOF
   
   # Apply the deployment
   oc apply -f wiremock-deployment.yaml
   ```

8. **Create Service and Route**

   ```bash
   # Create the service and route file
   cat > wiremock-service-route.yaml << EOF
   apiVersion: v1
   kind: Service
   metadata:
     name: wiremock
     labels:
       app: wiremock
   spec:
     selector:
       app: wiremock
     ports:
     - port: 8080
       targetPort: 8080
       name: http
     type: ClusterIP
   ---
   apiVersion: route.openshift.io/v1
   kind: Route
   metadata:
     name: wiremock
     labels:
       app: wiremock
   spec:
     to:
       kind: Service
       name: wiremock
     port:
       targetPort: http
   EOF
   
   # Apply the service and route
   oc apply -f wiremock-service-route.yaml
   ```

9. **Wait for the deployment to be ready**

   ```bash
   # Wait for the pod to be ready
   oc rollout status deployment/wiremock
   ```

10. **Verify the deployment**

    ```bash
    # Get the route URL
    ROUTE_HOST=$(oc get route wiremock -o jsonpath='{.spec.host}')
    echo "Access WireMock at: http://$ROUTE_HOST"
    
    # Test the example endpoint
    curl http://$ROUTE_HOST/example
    ```

## All-in-One Deployment

If you prefer to keep everything in a single YAML file, you can combine all the above resources:

```bash
# Create a complete deployment file
cat > wiremock-complete.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: wiremock-stubs
  labels:
    app: wiremock
data:
  example.json: |
    {
      "request": {
        "method": "GET",
        "url": "/example"
      },
      "response": {
        "status": 200,
        "body": "{{request.path.[0]}}",
        "headers": {
          "Content-Type": "text/plain"
        },
        "transformers": ["response-template", "com.dfs.StringManipulationTransfromer"]
      }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: wiremock-jars
  labels:
    app: wiremock
data:
  wiremock-standalone.jar: |
$(base64 wiremock-standalone.jar | sed 's/^/    /')
  custom-wiremock-transformer.jar: |
$(base64 custom-wiremock-transformer.jar | sed 's/^/    /')
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wiremock
  labels:
    app: wiremock
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wiremock
  template:
    metadata:
      labels:
        app: wiremock
    spec:
      volumes:
      - name: wiremock-data
        emptyDir: {}
      - name: stubs-volume
        configMap:
          name: wiremock-stubs
      - name: jar-config
        configMap:
          name: wiremock-jars
      initContainers:
      - name: copy-jars
        image: registry.redhat.io/ubi8/ubi:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          mkdir -p /wiremock
          for file in \$(ls /jar-config/); do
            echo "Processing \$file..."
            base64 -d "/jar-config/\$file" > "/wiremock/\$file"
            echo "Created /wiremock/\$file"
            ls -la "/wiremock/\$file"
          done
        volumeMounts:
        - name: wiremock-data
          mountPath: /wiremock
        - name: jar-config
          mountPath: /jar-config
      containers:
      - name: wiremock
        image: registry.redhat.io/ubi8/openjdk-11:latest
        command: ["java"]
        args: ["-jar", "/opt/wiremock/wiremock-standalone.jar", "--extensions", "com.dfs.StringManipulationTransfromer", "--classpath", "/opt/wiremock/custom-wiremock-transformer.jar", "--global-response-templating", "--root-dir", "/opt/wiremock/mappings"]
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /__admin/
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
        volumeMounts:
        - name: wiremock-data
          mountPath: /opt/wiremock
        - name: stubs-volume
          mountPath: /opt/wiremock/mappings
---
apiVersion: v1
kind: Service
metadata:
  name: wiremock
  labels:
    app: wiremock
spec:
  selector:
    app: wiremock
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  type: ClusterIP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: wiremock
  labels:
    app: wiremock
spec:
  to:
    kind: Service
    name: wiremock
  port:
    targetPort: http
EOF

# Apply all resources at once
oc apply -f wiremock-complete.yaml
```

## Troubleshooting

If the deployment is not working as expected:

1. **Check pod status**

   ```bash
   oc get pods -l app=wiremock
   ```

2. **Check init container logs**

   ```bash
   # Check logs from the init container that processes the JAR files
   oc logs $(oc get pods -l app=wiremock -o name) -c copy-jars
   ```

3. **Check logs of the WireMock container**

   ```bash
   # Check logs from the main WireMock container
   oc logs $(oc get pods -l app=wiremock -o name) -c wiremock
   ```

4. **Check if JAR files were created correctly**

   ```bash
   # Check the files in the running pod
   oc exec $(oc get pods -l app=wiremock -o name) -c wiremock -- ls -lh /opt/wiremock/
   ```

## Limitations

- ConfigMaps have a size limit (typically around 1MB). If your JAR files exceed this limit, you may need to use the PVC approach instead.
- Base64 encoding increases the size of the JAR files by approximately 33%.
- The ConfigMap approach is generally suitable for smaller JAR files. 