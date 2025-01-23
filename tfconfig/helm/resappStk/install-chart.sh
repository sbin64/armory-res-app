#!/usr/bin/env bash

# Exit on any failure
set -e

HELM_CHART_DIR="."
RELEASE_NAME=${1}

if [ -z "${RELEASE_NAME}" ]; then
    echo "Usage: install-chart.sh <release-name>"
    exit 1
fi

# Add bitnami repo
helm repo add bitnami https://charts.bitnami.com/bitnami

# Build helm dependencies
helm dependency build ${HELM_CHART_DIR}

# Install chart
helm upgrade --install ${RELEASE_NAME} ${HELM_CHART_DIR} -f ${HELM_CHART_DIR}/values.yaml --render-subchart-notes
