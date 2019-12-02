# k8s-thingsboard

Fork of the k8s directory of thingsboard to plugin the platform to Elassandra managed by the Elassandra operator

## install

Deploy the Elassandra Operator first.
Change the variables in the _strapdata-install-td.sh_ script.
* NAMESPACE
* DATACENTER_NAME
* CLUSTER_NAME
* TRAEFIK : deploy the Traefik ingress (false by default, nginx is use instead in this case)
* USE_COAP : deploy the CoAP gateway (false by default)

Run _strapdata-install-td.sh_

