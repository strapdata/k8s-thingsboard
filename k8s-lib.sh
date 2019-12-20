#!/bin/bash

set -x

# export useful env variables
export NAMESPACE=${TB_NAMESPACE:-"default"}
export DATACENTER_NAME=${TB_DATACENTER_NAME:-"dc1"}
export CLUSTER_NAME=${TB_CLUSTER_NAME:-"testthingsboard"}
export TRAEFIK=${TB_TRAEFIK:-"true"}
export USE_COAP=${TB_COAP:-"false"}

#######################################

function setup_elassandra_user_config() {
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
}


# helm install --name ${CLUSTER_NAME}-${DATACENTER_NAME} --namespace $NAMESPACE -f /home/eric/strapdata/dev/customer/orchid/values-datacenter-thingsboard.yml /home/eric/strapdata/dev/strapkop/helm/src/main/helm/elassandra-datacenter/

function deploy_elassandra_operator() {
  helm install --name strapkop --namespace $NAMESPACE \
    --set image.pullSecrets[0]="$REGISTRY_SECRET_NAME" \
    --set image.tag="$OPERATOR_TAG" \
    https://strapdata.blob.core.windows.net/charts/elassandra-operator-0.2.0.tgz

}

function deploy_elassandra_datacenter() {
  helm install --name ${CLUSTER_NAME}-${DATACENTER_NAME} --namespace $NAMESPACE -f values-datacenter-thingsboard.yml https://strapdata.blob.core.windows.net/charts/elassandra-datacenter-0.2.0.tgz

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
}

#######################################



#######################################

function create_keyspace() {
  echo "Create TB-NODE config map to cassandra"
  sed 's/__CASSANDRA_SERVICE__/"elassandra-'${CLUSTER_NAME}'-'${DATACENTER_NAME}':39042"/g' tb-node-cassandra-configmap.yml > /tmp/configmap-cassandra.yml
  kubectl apply -n $NAMESPACE -f /tmp/configmap-cassandra.yml

  ELASSANDRA_NODE=$(kubectl get pod -n $NAMESPACE -l app=elassandra,app.kubernetes.io/managed-by=elassandra-operator -o name | head -1)

  echo "Create Thingsboard keyspace using $ELASANDRA_NODE"
  kubectl exec -n $NAMESPACE -it ${ELASSANDRA_NODE:4} -- cqlsh -e "CREATE KEYSPACE IF NOT EXISTS thingsboard WITH replication = { 'class' : 'NetworkTopologyStrategy', '$DATACENTER_NAME' : '1' };"
}

#######################################

function init_db() {
  echo "Initialize DB"
  kubectl apply -n $NAMESPACE -f tb-node-configmap.yml
  kubectl apply -n $NAMESPACE -f database-setup.yml &&
  kubectl wait --for=condition=Ready -n $NAMESPACE pod/tb-db-setup --timeout=120s && \
     kubectl exec -n $NAMESPACE tb-db-setup -- sh -c 'export INSTALL_TB=true; export LOAD_DEMO='"$loadDemo"'; start-tb-node.sh; touch /install-finished;'

  #kubectl delete pod -n $NAMESPACE  tb-db-setup
}

#######################################

function setup_thingsboard() {
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
}
