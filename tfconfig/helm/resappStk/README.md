# [StackGen](stackgen.com) generated IaC

Below are the instructions to get started with the generated IaC

## Install Helm Chart

1. Before installing the included helm chart, please make sure the ~/.kube/config points to the cluster you want to use.
2. Update the helm-chart/values.yaml as required.
3. Generated charts and dependent sub-charts for the AppStack can be installed to your cluster by running -

```
sh install-chart.sh
```
