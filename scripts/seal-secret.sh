#!/bin/bash
# Helper script to create a SealedSecret from a literal value
# Usage: ./seal-secret.sh <secret-name> <namespace> <literal-key=value>
# Example: ./seal-secret.sh my-api-key game api-key=abc123

SECRET_NAME=$1
NAMESPACE=$2
LITERAL=$3

if [ -z "$SECRET_NAME" ] || [ -z "$NAMESPACE" ] || [ -z "$LITERAL" ]; then
  echo "Usage: $0 <secret-name> <namespace> <literal-key=value>"
  echo "Example: $0 my-api-key game api-key=abc123"
  exit 1
fi

# Ensure kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
  echo "❌ kubeseal not found. Install it from https://github.com/bitnami-labs/sealed-secrets"
  exit 1
fi

# Create sealed secret and save to file
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --dry-run=client \
  --from-literal="$LITERAL" \
  -o yaml | kubeseal --format yaml > "secrets/sealed-secrets/${SECRET_NAME}.yaml"

echo "✅ Sealed secret saved to secrets/sealed-secrets/${SECRET_NAME}.yaml"