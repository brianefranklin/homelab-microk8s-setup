./setup_arc.sh --cleanup
echo "Restart microk8s"
sudo microk8s stop 
sudo microk8s start
sleep 120
./setup_arc.sh --debug
sleep 30
echo "Get pod"
microk8s.kubectl get pods -A
microk8s.kubectl get pods -n actions-runner-system
ACTION_RUNNER_POD=$(kubectl get pods -n actions-runner-system -o json | jq -r '.items[].metadata.name')
echo "Get logs for pod $ACTION_RUNNER_POD"
microk8s.kubectl logs $ACTION_RUNNER_POD -n actions-runner-system
echo "Describe pod $ACTION_RUNNER_POD"
microk8s.kubectl describe pod $ACTION_RUNNER_POD -n actions-runner-system
