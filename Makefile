.DEFAULT_GOAL := localdev

CLUSTER_NAME ?= localdev
SRCDIR ?= $(HOME)/src

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

MINIODIR ?= $(shell pwd)/.minio
$(MINIODIR):
	mkdir -p $(MINIODIR)

KUBECTL ?= kubectl
KUSTOMIZE ?= $(LOCALBIN)/kustomize

ISTIO_VERSION ?= 1.20.0

.PHONY: deps
deps: kustomize

.PHONY: kustomize istioctl
kustomize: $(KUSTOMIZE)
$(KUSTOMIZE): $(LOCALBIN)
	@curl -sSLo ./scripts/install_kustomize.sh "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
	@chmod +x ./scripts/install_kustomize.sh
	@./scripts/install_kustomize.sh $(KUSTOMIZE_VERSION) $(LOCALBIN)

.PHONY: istioctl
istioctl: $(LOCALBIN)
	@curl -sSLo ./scripts/install_istioctl.sh "https://istio.io/downloadIstioctl"
	@chmod +x ./scripts/install_istioctl.sh
	@./scripts/install_istioctl.sh -b $(LOCALBIN) $(ISTIO_VERSION)

## Install the local development environment.  I'd like to come
## back around and do this outside of the Makefile, but for now
## I'm ok with it.  In general, I'd like to have a tool that can
## interact with both the clusters and applications to set up
## the environment in a customized way.
.PHONY: localdev
localdev: kind install

.PHONY: kind
kind:
	@./scripts/kind-start.sh $(CLUSTER_NAME) $(SRCDIR)

## Installs everything except for the tailscale operator.  I'll add
## this in as optional based on an environment variable plus I actually
## need to get it working properly and document it.
.PHONY: install
install: $(KUSTOMIZE) $(MINIODIR) install-cert-manager install-spark-system install-redpanda install-genie install-minio install-otel-system

.PHONY: uninstall
uninstall: uninstall-otel-system uninstall-minio uninstall-genie uninstall-redpanda uninstall-spark-system uninstall-cert-manager

.PHONY: install-cert-manager
install-cert-manager:
	@$(KUSTOMIZE) build k8s/cert-manager | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=cert-manager -n cert-manager

.PHONY: uninstall-cert-manager
uninstall-cert-manager:
	-@kubectl delete -k k8s/cert-manager

.PHONY: install-tailscale
install-tailscale:
	@$(KUSTOMIZE) build k8s/tailscale | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=tailscale -n tailscale

.PHONY: uninstall-tailscale
uninstall-tailscale:
	-@kubectl delete -k k8s/tailscale

.PHONY: install-spark-system
install-spark-system:
	@$(KUSTOMIZE) build k8s/spark-system | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=spark-system -n spark-system

.PHONY: uninstall-spark-system
uninstall-spark-system:
	-@kubectl delete -k k8s/spark-system

.PHONY: install-flink
install-flink: install-spark-system
	@$(KUSTOMIZE) build k8s/flink | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=flink

.PHONY: uninstall-flink
uninstall-flink:
	-@kubectl delete -k k8s/flink

.PHONY: install-redpanda-system
install-redpanda-system:
	@$(KUSTOMIZE) build k8s/redpanda-system | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=redpanda-system -n redpanda-system

.PHONY: uninstall-redpanda-system
uninstall-redpanda-system: install-cert-manager
	-@kubectl delete -k k8s/redpanda-system

.PHONY: install-redpanda
install-redpanda: install-redpanda-system
	@$(KUSTOMIZE) build k8s/redpanda | envsubst | kubectl apply -f -
## We also need to wait a few seconds for the operator to create the statefulset otherwise
## the wait will fail.  For some reason it takes a bit of time to create the statefulset.
	@sleep 10
## Because statefulsets don't set the condition we have to do some trickery and grab
## the replicas from the spec then use the availableReplicas equal to the expected
## replicas for the wait condition. It's not ideal, but it works for now.  If any other
## redpanda clusters are added to the deploy and they have upstream or downstream deps
## then each will need to be added with their own wait, unlike the other deployments that
## we can group together with labels.
	$(eval REPLICAS := $(shell kubectl get sts -l app.kubernetes.io/instance=analytics -o=custom-columns=:spec.replicas --no-headers))
	@kubectl wait --for=jsonpath='{.status.availableReplicas}'=$(REPLICAS) --timeout=120s sts -l app.kubernetes.io/instance=analytics

.PHONY: uninstall-redpanda
uninstall-redpanda:
	-@kubectl delete -k k8s/redpanda

.PHONY: install-genie
install-genie: install-redpanda
	@$(KUSTOMIZE) build k8s/genie | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=genie

.PHONY: uninstall-genie
uninstall-genie:
	-@kubectl delete -k k8s/genie

.PHONY: install-minio-system
install-minio-system:
	@$(KUSTOMIZE) build k8s/minio-system | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=minio-system -n minio-system

.PHONY: uninstall-minio-system
uninstall-minio-system:
	-@kubectl delete -k k8s/minio-system

.PHONY: install-minio
install-minio:
	@$(KUSTOMIZE) build k8s/minio | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=180s deploy -l app.kubernetes.io/group=minio

.PHONY: uninstall-minio
uninstall-minio:
	-@kubectl delete -k k8s/minio

.PHONY: install-otel-system
install-otel-system:
	@$(KUSTOMIZE) build k8s/otel-system | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=otel-system -n opentelemetry-operator-system

.PHONY: uninstall-otel-system
uninstall-otel-system:
	-@kubectl delete -k k8s/otel-system

.PHONY: install-argocd
install-argocd:
	@$(KUSTOMIZE) build k8s/argocd | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l app.kubernetes.io/group=argocd -n argocd

.PHONY: uninstall-argocd
uninstall-argocd:
	-@kubectl delete -k k8s/argocd

.PHONY: install-istio-operator
install-istio-operator:
	istioctl operator init

.PHONY: uninstall-istio-operator
uninstall-istio-operator:
	istioctl operator remove

.PHONY: install-istio
install-istio:
	@$(KUSTOMIZE) build k8s/istio | envsubst | kubectl apply -f -
	@kubectl wait --for=condition=available --timeout=120s deploy -l release=istio -n istio-system

.PHONY: uninstall-istio
uninstall-istio:
	-@kubectl delete -k k8s/istio

.PHONY: clean
clean:
	@kind delete cluster --name=localdev
