#!/bin/bash

set -xe


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

source $(dirname $0)/k8s-lib.sh

setup_elassandra_user_config
deploy_elassandra_operator
deploy_elassandra_datacenter
create_keyspace
init_db
setup_thingsboard
