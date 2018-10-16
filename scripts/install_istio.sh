#!/bin/bash
# installs istio on master

shopt -s nocasematch

cfg_dir="/etc/origin/master"
master_cfg="$cfg_dir/master-config.yaml"
console_cfg="$cfg_dir/webconsole-config.yaml"
istio_cfg="$cfg_dir/istio-installation.yaml"
datest=`date +%Y%m%d%H%M`

masterExtIP=`ssh -oStrictHostKeyChecking=no master.example.com curl -s http://www.opentlc.com/getip`

myGUID=`hostname|cut -f2 -d-|cut -f1 -d.`

if [[ $myGUID == 'repl' ]]
then
  mpu="https://$masterExtIP"
else
  mpu="https://master-$myGUID.generic.opentlc.com"
fi

function wait_for_host()
{
    count=0
    while test $count -lt 100; do
        nc -w 3 $1 22 </dev/null >/dev/null 2>&1 && break
        count=$((count+1))
        sleep 60
    done
    echo "Host $1 is up after $count attempts"
}

wait_for_host master.example.com
wait_for_host infranode.example.com
wait_for_host node01.example.com
wait_for_host node02.example.com
wait_for_host node03.example.com


if ssh master.example.com oc get project istio-operator ; then
  echo "istio-operator already installed, skipping istio install"
  exit 0
fi

CFGPATCHTEMP=$(mktemp)
CFGTEMP=$(mktemp)
CFGFINAL=$(mktemp)

cat << EOF > ${CFGPATCHTEMP}
admissionConfig:
  pluginConfig:
    MutatingAdmissionWebhook:
      configuration:
        apiVersion: v1
        disable: false
        kind: DefaultAdmissionConfig
    ValidatingAdmissionWebhook:
      configuration:
        apiVersion: v1
        disable: false
        kind: DefaultAdmissionConfig
EOF

scp master.example.com:$master_cfg ${CFGTEMP}
oc ex config patch ${CFGTEMP} -p "$(cat ${CFGPATCHTEMP})" > ${CFGFINAL}
ssh master.example.com cp "$master_cfg $master_cfg.istio.$datest"
scp ${CFGFINAL} master.example.com:$master_cfg
rm -f $CFGTEMP $CFGPATCHTEMP $CFGFINAL
ssh master.example.com master-restart api
ssh master.example.com master-restart controllers

for node in master.example.com infranode.example.com node01.example.com node02.example.com node03.example.com ; do
  ssh $node "echo 'vm.max_map_count = 262144' > /etc/sysctl.d/99-elasticsearch.conf"
  ssh $node sysctl vm.max_map_count=262144
done

TMPCRD=$(mktemp)

cat << EOF > ${TMPCRD}
apiVersion: "istio.openshift.com/v1alpha1"
kind: "Installation"
metadata:
  name: "istio-installation"
spec:
  deployment_type: openshift
  istio:
    authentication: false
    community: false
    prefix: openshift-istio-tech-preview/
    version: 0.2.0
  jaeger:
    prefix: distributed-tracing-tech-preview/
    version: 1.6.0
    elasticsearch_memory: 1Gi
EOF

# Install the istio operator
operator_template=https://raw.githubusercontent.com/Maistra/openshift-ansible/maistra-0.2.0-ocp-3.1.0-istio-1.0.2/istio/istio_product_operator_template.yaml

for i in {1..200}; do ssh master.example.com oc new-project istio-operator && break || sleep 2; done

ssh master.example.com oc new-app -f $operator_template --param=OPENSHIFT_ISTIO_MASTER_PUBLIC_URL=${mpu}

# Install istio
scp ${TMPCRD} master.example.com:$istio_cfg
ssh master.example.com oc -n istio-operator create -f ${istio_cfg}




