#!/bin/bash
# fix-coredns-local.sh
# Run this after every minikube restart to fix stale CoreDNS IPs.
# Usage: ./scripts/fix-coredns-local.sh

set -e

echo "→ Getting current nginx ingress ClusterIP..."
NGINX_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

if [ -z "$NGINX_IP" ]; then
  echo "✗ Could not get nginx ClusterIP. Is minikube running and ingress addon enabled?"
  echo "  Run: minikube addons enable ingress"
  exit 1
fi
echo "  nginx ClusterIP: $NGINX_IP"

echo "→ Getting host.minikube.internal IP..."
MINIKUBE_IP=$(minikube ssh "cat /etc/hosts" 2>/dev/null | \
  grep host.minikube.internal | awk '{print $1}')

if [ -z "$MINIKUBE_IP" ]; then
  echo "✗ Could not get host.minikube.internal IP."
  exit 1
fi
echo "  host.minikube.internal: $MINIKUBE_IP"

COREDNS_FILE="$(dirname "$0")/../k8s/coredns-patch.yaml"

echo "→ Updating $COREDNS_FILE..."

# Update nginx IP lines (both dev.atoloan.api.com and dev.atoloan.com)
sed -i '' "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\} dev\.atoloan\.api\.com/$NGINX_IP dev.atoloan.api.com/" "$COREDNS_FILE"
sed -i '' "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\} dev\.atoloan\.com/$NGINX_IP dev.atoloan.com/" "$COREDNS_FILE"

# Update host.minikube.internal IP
sed -i '' "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\} host\.minikube\.internal/$MINIKUBE_IP host.minikube.internal/" "$COREDNS_FILE"

echo "→ Applying updated CoreDNS config..."
kubectl apply -f "$COREDNS_FILE"

echo "→ Restarting CoreDNS..."
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system

echo ""
echo "✓ Done. CoreDNS updated with:"
echo "  nginx:   $NGINX_IP"
echo "  minikube: $MINIKUBE_IP"
