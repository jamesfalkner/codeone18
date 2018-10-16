#!/bin/bash
operator_template=https://raw.githubusercontent.com/Maistra/openshift-ansible/maistra-0.2.0-ocp-3.1.0-istio-1.0.2/istio/istio_product_operator_template.yaml

oc delete project prod lab-infra
oc delete -n istio-operator installation istio-installation
oc process -n default -f ${operator_template} | oc delete -f -

