#!/bin/bash

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

# wait for master and nodes to be available
wait_for_host master.example.com
wait_for_host infranode.example.com
wait_for_host node01.example.com
wait_for_host node02.example.com
wait_for_host node03.example.com

# first install istio
/usr/local/bin/install_istio.sh 

# now make some cheap PVs

echo "Waiting for PV support"
for i in {1..200}; do ssh master.example.com oc get pv && break || sleep 2; done

echo "Creating PVs"
for i in pv01 pv02 pv03 pv04 pv05 pv06 pv07 pv08 pv09 pv10 ; do

	if ! ssh master.example.com oc get persistentvolume ${i} --as=system:admin ; then

		for j in master node01 node02 node03 ; do
			ssh $j.example.com mkdir -p /root/${i}
			ssh $j.example.com chcon -R -t svirt_sandbox_file_t /root/${i}
			ssh $j.example.com restorecon -R /root/${i}
			ssh $j.example.com chmod 777 /root/${i}
		done

		cat <<-EOF | ssh master.example.com oc create --as=system:admin -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${i}
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
    - ReadOnlyMany
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Recycle
  hostPath:
    path: /root/${i}
EOF

	fi
done

# Pre-pull images on all nodes
for i in infranode.example.com node01.example.com node02.example.com node03.example.com ; do
	echo "prepulling images on $i"

      ssh $i docker pull  eclipse/che-server:6.9.0
      ssh $i docker pull  openshiftdemos/gogs:0.11.34
	  ssh $i docker pull  sonatype/nexus3:3.10.0
      ssh $i docker pull  siamaksade/che-centos-jdk8:rhsummit18-cloudnative
      ssh $i docker pull  siamaksade/rhsummit18-cloudnative-inventory:prod
      ssh $i docker pull  siamaksade/rhsummit18-cloudnative-web:prod
	  ssh $i docker pull  quay.io/osevg/workshopper:latest

      ssh $i docker pull registry.access.redhat.com/distributed-tracing-tech-preview/jaeger-agent:1.6.0
      ssh $i docker pull registry.access.redhat.com/distributed-tracing-tech-preview/jaeger-collector:1.6.0
      ssh $i docker pull registry.access.redhat.com/distributed-tracing-tech-preview/jaeger-elasticsearch:5.6.10
      ssh $i docker pull registry.access.redhat.com/distributed-tracing-tech-preview/jaeger-query:1.6.0

      ssh $i docker pull  istio/grafana:1.0.2
      ssh $i docker pull  prom/statsd-exporter:v0.6.0
      ssh $i docker pull  prom/prometheus:v2.3.1
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/citadel:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/galley:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/istio-operator:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/mixer:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/openshift-ansible:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/pilot:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/proxy-init:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/proxyv2:0.2.0
      ssh $i docker pull registry.access.redhat.com/openshift-istio-tech-preview/sidecar-injector:0.2.0


	  ssh $i docker pull registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:1.2
	  ssh $i docker pull registry.access.redhat.com/rhscl/nodejs-4-rhel7:latest
	  ssh $i docker pull registry.access.redhat.com/openshift3/jenkins-2-rhel7:latest
	  ssh $i docker pull registry.access.redhat.com/openshift3/jenkins-slave-maven-rhel7:latest
	  ssh $i docker pull registry.access.redhat.com/rhscl/postgresql-95-rhel7:latest
	  ssh $i docker pull registry.access.redhat.com/rhscl/postgresql-96-rhel7:latest


done

for i in master.example.com infranode.example.com node01.example.com node02.example.com node03.example.com ; do
	ssh $i setenforce 0
done

# add developer and admin user
ssh master.example.com "htpasswd -b /etc/origin/master/htpasswd developer openshift"
ssh master.example.com "htpasswd -b /etc/origin/master/htpasswd admin openshift"

ssh master.example.com "yum install -y git"
ssh master.example.com "oc get -n openshift is/redhat-openjdk18-openshift || oc create -n openshift -f https://raw.githubusercontent.com/openshift/openshift-ansible/release-3.10/roles/openshift_examples/files/examples/v3.10/xpaas-streams/openjdk18-image-stream.json"
ssh master.example.com "oc import-image redhat-openjdk18-openshift -n openshift --all"
ssh master.example.com "rm -rf /root/codeone18\*"
ssh master.example.com "curl -sL -o /root/codeone18-lab.tar.gz https://github.com/jamesfalkner/codeone18/archive/master.tar.gz"
ssh master.example.com "cd /root; tar xvfz codeone18-lab.tar.gz"
ssh master.example.com "cd /root/codeone18-master/ansible; ansible-galaxy install -r requirements.yml -f ; ansible-playbook init.yml -e oc_kube_config=/root/.kube/config -e clean_init=true"

