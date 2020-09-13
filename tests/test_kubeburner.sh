#!/usr/bin/env bash
set -xeEo pipefail

source tests/common.sh

function finish {
  if [ $? -eq 1 ] && [ $ERRORED != "true" ]
  then
    error
  fi

  [[ $check_logs == 1 ]] && kubectl logs -l app=kube-burner-benchmark-$uuid -n my-ripsaw
  echo "Cleaning up kube-burner"
  kubectl delete ns -l kube-burner-uuid=${long_uuid}
  wait_clean
}


trap error ERR
trap finish EXIT

function functional_test_kubeburner {
  workload_name=$1
  token=$(oc -n openshift-monitoring sa get-token prometheus-k8s)
  cr=tests/test_crs/valid_kube-burner.yaml
  check_logs=0
  wait_clean
  apply_operator
  echo "Performing kube-burner: ${workload_name}"
  sed -e "s/WORKLOAD/${workload_name}/g" -e "s/PROMETHEUS_TOKEN/${token}/g" ${cr} | kubectl apply -f -
  long_uuid=$(get_uuid 20)
  uuid=${long_uuid:0:8}

  pod_count "app=kube-burner-benchmark-$uuid" 1 900
  wait_for "kubectl wait -n my-ripsaw --for=condition=complete -l app=kube-burner-benchmark-$uuid jobs --timeout=500s" "500s"
  check_logs=1

  index="ripsaw-kube-burner"
  if check_es "${long_uuid}" "${index}"
  then
    echo "kube-burner ${workload_name}: Success"
  else
    echo "Failed to find data for kube-burner ${workload_name} in ES"
    exit 1
  fi
  kubectl delete ns -l kube-burner-uuid=${long_uuid}
}

figlet $(basename $0)
functional_test_kubeburner cluster-density
functional_test_kubeburner kubelet-density
functional_test_kubeburner kubelet-density-heavy