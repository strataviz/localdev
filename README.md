# Local Development Environment

Localdev provides an workstation/laptop based development environment for StrataViz projects.  The environment includes:

* Minio to mimic S3 compatible object storage.
* Spark Operator for managing spark and beam jobs. 
* RedPanda to provide a streaming data platform.
* Genie for custom event generation.
* Tailscale operator for exposing ingresses and services inside a tailnet mesh

The tailscale operator is not installed by default since there are external dependencies in setting up, but can be installed after the base system.

The local kind cluster mounts up the global source directory to allow users to access and mount their project directories inside of the cluster to facilitate incremental development and testing against resources that are present in the cluster - something that usually isn't possible without packaging and loading the image with takes time. 

## Starting the localdev environment

By default the cluster name is `localdev` and the source directory is `$HOME/src` is mounted in each kind node to `/mnt`.  To spin up the cluster and it's base resources, run the following:

```
make
```

To change the name and extra mounts:

```
CLUSTER_NAME=strataviz SRCDIR=$PWD make
```

To install the tailscale operator follow the directions below and then run:

```
make install-tailscale
```

## Stop

To remove all of the localdev environment, run:

```
make clean
```

## Using localdev

Since the localdev environment (by default) mounts your the root of your source directory, you can access multiple projects in it.  The following is an example on how to create a development pod that you can use to run your golang projects inside of the cluster without packaging the image.

Assuming that you are working on a project found in `$HOME/src/myproject`, create a deployment manifest:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev
  labels:
    app: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dev
  template:
    metadata:
      labels:
        app: dev
    spec:
      containers:
      - name: dev
        securityContext:
          runAsUser: 0
          runAsGroup: 0
          runAsNonRoot: false
        image: docker.io/golang:1.21.2
        imagePullPolicy: IfNotPresent
        workingDir: /usr/src/app
        command:
          - sleep
          - infinity
        volumeMounts:
          - name: app
            mountPath: /usr/src/app
      volumes:
        - name: app
          hostPath:
            path: /mnt/src/myproject
```

Deploy the manifest and add the following to your Makefile (or alias as a standalone command):

```
.PHONY: run
run:
  $(eval POD := $(shell kubectl get pods -l app=dev -o=custom-columns=:metadata.name --no-headers))
  kubectl exec -it pod/$(POD) -- bash -c "go run main.go"
```

When you run `make run` the kubectl will find and exec into the pod created by the deployment and run everything inside your cluster.  I often use this pattern when working on k8s operators and will modify the deployment giving it access to a service account that has access to specific resources.

## Tailscale

The tailscale operator is available to set up access to ingresses and services inside the kind cluster.  Additional documentation will follow.  In short, if you have a tailscale network that you would like to integrate into your local development cluster, you will need to create an oauth client in your tailscale dashboard and export the following environment variables:

* `TAILSCALE_OAUTH_CLIENT_ID`: set this to your client ID
* `TAILSCALE_OAUTH_CLIENT_SECRET`: set this to your client secret

The deployment will create a secret that will be mounted into the operator and connect the operator into your tailnet.  Annotated services and ingresses of class `tailscale` will automatically create machines in your network.  There is a new funnel service (in beta) which allows you to expose your internal nodes to the public internet to test external webhooks.  Home networks may require modifications to allow port forwarding to your workstation.

As an example:

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
spec:
  defaultBackend:
    service:
      name: nginx
      port:
        number: 80
  ingressClassName: tailscale
  tls:
  - hosts:
    - nginx
```

```
apiVersion: v1
kind: Service
metadata:
  name: nginx
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "nginx"
spec:
  ports:
  - name: http
    port: 80
    targetPort: 80
  type: ClusterIP
  selector:
    app: nginx
```