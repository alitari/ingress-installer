#!/usr/bin/bash
helm repo add jetstack "https://charts.jetstack.io"
helm repo add stable "https://kubernetes-charts.storage.googleapis.com"
helm repo add elastic "https://helm.elastic.co"
helm repo update