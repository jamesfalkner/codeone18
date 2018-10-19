#!/bin/bash
#
# check cloud native lab health
#
# usage checkhealth.sh [FILE]
#
# where [FILE] is a text file, with one GUID per line
#
for i in $(grep '^[0-9a-f]' ${1}) ; do

echo "--- Checking $i health..."
function warn() {
	echo "!!!!!!!!!! WARNING: $1 unhealhy: $2"
	echo
}

function info() {
	echo "---> $1"
}

info "Checking OpenShift..."
OCP_HEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  https://master-${i}.generic.opentlc.com/)

if [ "$OCP_HEALTH" != 200 ] ; then
	warn $i "OCP_HEALTH: ${OCP_HEALTH}"
	continue
fi

info "Logging in..."
if ! oc login --insecure-skip-tls-verify=true https://master-${i}.generic.opentlc.com -u admin -p openshift >& /dev/null; then
	warn "$i" "cannot oc login"
	continue
fi

info "Switching to istio-system project..."
if ! oc project istio-system >& /dev/null ; then
	warn "$i" "istio-system does not exist"
	continue
fi

info "Checking pod count..."
COUNT=$(oc get pods --no-headers --show-all=false | wc -l | awk '{print $1}')
if [ "$COUNT" != 17 ] ; then
	warn "$i" "less than 17 pods in istio-system"
	continue
fi

info "Switching to prod..."
if ! oc project prod >& /dev/null ; then
	warn "$i" "prod does not exist"
	continue
fi

info "Checking prod health..."
PROD_HEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  http://inventory-prod.apps-${i}.generic.opentlc.com/services/inventory/all)
if [ "$PROD_HEALTH" != 200 ] ; then
	warn $i "PROD_HEALTH: ${PROD_HEALTH}"
	continue
fi

info "Switching to lab-infra..."
if ! oc project lab-infra >& /dev/null ; then
	warn "$i" "lab-infra does not exist"
	continue
fi

info "Checking lab-infra pod count..."
COUNT=$(oc get pods --no-headers --show-all=false | wc -l | awk '{print $1}')

if [ "$COUNT" != 5 ] ; then
	warn "$i" "less than 5 pods in lab-infra"
	continue
fi

info "Checking guides..."
INFRA_HEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  http://guides-lab-infra.apps-${i}.generic.opentlc.com/workshop/cloudnative/lab/bootstrap-dev)
if [ "$INFRA_HEALTH" != 200 ] ; then
	warn $i "INFRA_HEALTH: guides: ${PROD_HEALTH}"
	continue
fi

info "Checking nexus..."
INFRA_HEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  http://nexus-lab-infra.apps-${i}.generic.opentlc.com/)
if [ "$INFRA_HEALTH" != 200 ] ; then
	warn $i "INFRA_HEALTH: nexus: ${PROD_HEALTH}"
	continue
fi

info "Checking gogs..."
INFRA_HEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  http://gogs-lab-infra.apps-${i}.generic.opentlc.com/)
if [ "$INFRA_HEALTH" != 200 ] ; then
	warn $i "INFRA_HEALTH: gogs: ${PROD_HEALTH}"
	continue
fi

info "Checking che..."
INFRA_HEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  http://che-lab-infra.apps-${i}.generic.opentlc.com/dashboard/)
if [ "$INFRA_HEALTH" != 200 ] ; then
	warn $i "INFRA_HEALTH: gogs: ${PROD_HEALTH}"
	continue
fi

info "Checking initial build..."
BUILDVAL=$(oc get build/catalog-1 -o jsonpath='{.status.phase}')
if [ "$BUILDVAL" != 'Complete' ] ; then
	warn $i "BUILDVAL: build didnt complete: ${BUILDVAL}"
	continue
fi

info "Checking code..."
PUSHHEALTH=$(curl -sk -w "%{http_code}" -o /dev/null  http://gogs-lab-infra.apps-${i}.generic.opentlc.com/developer/catalog/raw/master/pom.xml)
if [ "$PUSHHEALTH" != 200 ] ; then
	warn $i "PUSHHEALTH: cant get pom.xml: ${PUSHHEALTH}"
	continue
fi

echo "--- $i healthy"
echo
done

oc logout