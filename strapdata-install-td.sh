#!/bin/bash

set -xe

# export useful env variables
export NAMESPACE="default"
export DATACENTER_NAME="dc1"
export CLUSTER_NAME="cl1"

#######################################


cat << EOF | kubectl apply -n $NAMESPACE -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: elassandra-${CLUSTER_NAME}-${DATACENTER_NAME}-user-config
  labels:
    app: elassandra
    cluster: ${CLUSTER_NAME}
    datacenter: ${DATACENTER_NAME}
    parent: elassandra-${CLUSTER_NAME}-${DATACENTER_NAME}
data:
  cassandra_yaml_d_user_config_overrides_yaml: |
    enable_materialized_views: true
EOF


helm install --name ${CLUSTER_NAME}-${DATACENTER_NAME} --namespace $NAMESPACE -f /home/eric/strapdata/dev/customer/orchid/values-datacenter-thingsboard.yml /home/eric/strapdata/dev/strapkop/helm/src/main/helm/elassandra-datacenter/

sleep 20

echo "check elassandra deployment..."
ELASSANDRA_NODE=$(kubectl get pod -n $NAMESPACE -l app=elassandra,app.kubernetes.io/managed-by=elassandra-operator -o name | head -1)
if [[ -z "$ELASSANDRA_NODE" ]]
then 
 echo "ERROR : Deploy Elassandra node first"
fi

echo "OK: Elassandra node(s) found"
echo "    $ELASSANDRA_NODE"

kubectl -n $NAMESPACE wait $ELASSANDRA_NODE --for=condition=Ready --timeout=300s
echo "    $ELASSANDRA_NODE ready!"


#######################################


while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --loadDemo)
    LOAD_DEMO=true
    shift # past argument
    ;;
    *)
    shift # past argument or value
    ;;
esac
done

if [ "$LOAD_DEMO" == "true" ]; then
    loadDemo=true
else
    loadDemo=false
fi

#######################################

echo "Create TB-NODE config map to cassandra"

sed 's/__CASSANDRA_SERVICE__/"elassandra-'${CLUSTER_NAME}'-'${DATACENTER_NAME}':39042"/g' tb-node-cassandra-configmap.yml > /tmp/configmap-cassandra.yml
kubectl apply -n $NAMESPACE -f /tmp/configmap-cassandra.yml

echo "Create Thingsboard keyspace using $ELASANDRA_NODE"
kubectl exec -n $NAMESPACE -it $ELASSANDRA_NODE -- bash -c "cqlsh -e \
                \"CREATE KEYSPACE IF NOT EXISTS thingsboard \
                WITH replication = { \
                    'class' : 'NetworkTopologyStrategy', \
                    '$DATACENTER_NAME' : 1 \
                };\""


#######################################

echo "Initialize DB"

kubectl apply -n $NAMESPACE -f tb-node-configmap.yml
kubectl apply -n $NAMESPACE -f database-setup.yml &&
kubectl wait --for=condition=Ready -n $NAMESPACE pod/tb-db-setup --timeout=120s && \
   kubectl exec -n $NAMESPACE tb-db-setup -- sh -c 'export INSTALL_TB=true; export LOAD_DEMO='"$loadDemo"'; start-tb-node.sh; touch /install-finished;'

kubectl delete pod -n $NAMESPACE  tb-db-setup

#######################################

kubectl apply -n $NAMESPACE -f tb-mqtt-transport-configmap.yml
kubectl apply -n $NAMESPACE -f tb-http-transport-configmap.yml
kubectl apply -n $NAMESPACE -f thingsboard.yml
if [[ "$TRAEFIK" == "true" ]]
then 
kubectl apply -n $NAMESPACE -f thingsboard-ingress-traefik.yml
else 
kubectl apply -n $NAMESPACE -f thingsboard-ingress-nginx.yml
fi

if [[ "$USE_COAP" == "true" ]]
then 

  echo "Enable CoAP services"
  kubectl apply -n $NAMESPACE -f tb-coap-transport-configmap.yml
  kubectl apply -n $NAMESPACE -f thingsboard-coap.yml

fi
