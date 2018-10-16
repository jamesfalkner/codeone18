#!/bin/bash
# This script should be placed under /usr/local/bin made executable
# and ran via systemd service fixpublicurl

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

sleep 60

bastion="bastion.example.com"
ocpver="3.10"

cfg_dir="/etc/origin/master"
master_cfg="$cfg_dir/master-config.yaml"
console_cfg="$cfg_dir/webconsole-config.yaml"

myGUID=`hostname|cut -f2 -d-|cut -f1 -d.`

echo "My GUID: $myGUID"

wait_for_host master.example.com
wait_for_host infranode.example.com
masterExtIP=`ssh -oStrictHostKeyChecking=no master.example.com curl -s http://www.opentlc.com/getip`
infraExtIP=`ssh -oStrictHostKeyChecking=no infranode.example.com curl -s http://www.opentlc.com/getip`

echo "master external IP: $masterExtIP"
echo "infra external IP: $infraExtIP"


echo "Updating public URLs"

# Just a couple of functions for motd change
# could be written with 'case' or 'if's but this is easier to read and change

function dev_motd {

cp /etc/motd /etc/motd.orig
cat << EOF >/etc/motd
#####################################################################################
      Welcome to Red Hat Openshift Container Platform $ocpver Workshop On RHPDS
                              *** DEVELOPMENT MODE ***
#####################################################################################
Information about Your current environment:

OCP WEB UI access via IP: https://$masterExtIP
Wildcard FQDN for apps: *.$infraExtIP.nip.io


EOF
}

function prod_motd {

cp /etc/motd /etc/motd.orig
cat << EOF >/etc/motd
#####################################################################################
      Welcome to Red Hat Openshift Container Platform $ocpver Workshop On RHPDS
#####################################################################################
Information about Your current environment:

Your GUID: $myGUID
OCP WEB UI access via IP: https://master-$myGUID.generic.opentlc.com
Wildcard FQDN for apps: *.apps-$myGUID.generic.opentlc.com


EOF
}


shopt -s nocasematch
if [ $? -ne 0 ]
then
        echo "Failed to get external IP"
        exit 1
fi

ocp_config="/root/.kube/config"
datest=`date +%Y%m%d%H%M`

rm -rf /root/.kube
scp -pr master.example.com:.kube /root/

# Setting a router subdomain based on deployment (DEV vs. RHPDS)
echo "Master Ext IP: $masterExtIP"
echo "GUID: $myGUID"

TMP=/tmp/.cfg.$$

if [[ $myGUID == 'repl' ]]
then
  mpu="https:\/\/$masterExtIP"
  apu="https:\/\/$masterExtIP\/console\/"
  cpu=$apu
  pu=$apu
  sd="$infraExtIP.nip.io"
  dev_motd
else
  mpu="https:\/\/master-$myGUID.generic.opentlc.com"
  apu="https:\/\/master-$myGUID.generic.opentlc.com\/console\/"
  cpu=$apu
  pu=$apu
  sd="apps-$myGUID.generic.opentlc.com"
  prod_motd
fi

ssh master.example.com "oc -n openshift-web-console get configmap/webconsole-config -o yaml > $console_cfg"

for CFG in $master_cfg $console_cfg;do
  scp master.example.com:$CFG $TMP
  ssh master.example.com cp "$CFG $CFG.$datest"
  sed -i "s/masterPublicURL: .*$/masterPublicURL: $mpu/" $TMP
  sed -i "s/assetPublicURL: .*$/assetPublicURL: $apu/" $TMP
  sed -i "s/consolePublicURL: .*$/consolePublicURL: $cpu/" $TMP
  sed -i "s/publicURL: .*$/publicURL: $pu/" $TMP
  sed -i "s/subdomain: .*$/subdomain: $sd/" $TMP
  echo "new config file on master" + $CFG
  cat $TMP
  echo
  scp $TMP master.example.com:$CFG
  rm -f $TMP
done

echo "Recreating pod"
ssh master.example.com "oc -n openshift-web-console replace -f $console_cfg"
echo "new console config:"
ssh master.example.com cat $console_cfg
echo

echo "killing old pods"
ssh master.example.com "oc -n openshift-web-console delete pods --all"

sleep 15
echo "Restarting master..."
ssh master.example.com "reboot"

## start lab prep
/usr/local/bin/prepare_lab.sh

