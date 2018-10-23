Ansible Playbook For Workshop Setup
=========

The provided playbook automates preparing an OpenShift cluster for the Getting Started 
with Cloud-Native Labs by deploying required services (Gogs, Nexus, Eclipse Che, etc) which 
are used during the labs.

Playbook Variables
------------

| Variable              | Default Value | Description   |
|-----------------------|---------------|---------------|
|`lab_infra_project`    | `lab-infra`   | Project name to deploy Git server and lab guides  |
|`user_gogs_admin`      | `gogs`        | Admin username to create in Gogs |
|`user_gogs_test`       | `test`        | Test username to create in Gogs |
|`user_gogs_password`   | `openshift`   | Gogs password to configure for admin and test users |
|`project_suffix`       | NONE          | Project suffix for project names to be created e.g. `prod{PROJECT_SUFFIX}` |
|`user_openshift`       | `developer`   | User to set as the admin of dev and prod projects |
|`clean_init`           | `false`       | Clean the environment and remove projects before init |


How To Run
------------
You'll need an OpenShift 3.10 or later cluster already installed (you can use [Minishift](https://github.com/MiniShift/minishift) and give it at least 8gb memory).

You'll also need to [install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html). 

Next, you'll need to log in to OpenShift with a user that has admin privileges and [install istio using the OpenShift operator for Istio](https://access.redhat.com/documentation/en-us/openshift_container_platform/3.10/html/service_mesh_install/)

Once that's confirmed to be installed and running, you can install the lab:

```
ansible-galaxy install -r requirements.yml
ansible-playbook init.yml 
```
Once it's done installing, browse to the installed guides using the URL from this command

~~~sh
echo http://$(oc get route guides -o jsonpath='{.spec.host}{"\n"}' -n lab-infra)
~~~

Troubleshooting 
---------------
* Mac OS X users need to upgrade the default Python installed to avoid certificate issues with GitHub. See https://blog.bearandgiraffe.com/ansible-github-and-a-failed-to-validate-the-ssl-certificate-story-a8a10ea17512 for more details on how to upgrade the ansible to use a later version of python.
* The Ansible Galaxy roles requires `jmespath` python package on Mac OS X. To install it run: `sudo pip3 install jmespath`
* Ansible on Mac OS X needs the GNU tar instead of BSD tar. Install it via `brew install gnu-tar`
* If you get `Init Crash Loop Back-off` in prod project, it's due to an [issue with Istio 0.6.0](https://github.com/istio/issues/issues/34). Disable SELinux on all your OpenShift nodes:

  ```
  setenforce 0 
  ```


Tips
----------------
* Pre-pull images on all nodes

  ```
  docker pull registry.access.redhat.com/redhat-openjdk-18/openjdk18-openshift:1.2
  docker pull registry.access.redhat.com/rhscl/nodejs-4-rhel7:latest
  docker pull registry.access.redhat.com/openshift3/jenkins-2-rhel7:latest
  docker pull registry.access.redhat.com/openshift3/jenkins-slave-maven-rhel7:latest
  docker pull registry.access.redhat.com/rhscl/postgresql-95-rhel7:latest
  docker pull registry.access.redhat.com/rhscl/postgresql-96-rhel7:latest
  docker pull sonatype/nexus3:3.7.1
  docker pull openshiftdemos/gogs:0.11.34
  docker pull eclipse/che:6.3.0
  docker pull osevg/workshopper:latest
  docker pull siamaksade/che-centos-jdk8:rhsummit18-cloudnative
  docker pull siamaksade/rhsummit18-cloudnative-inventory:prod
  docker pull siamaksade/rhsummit18-cloudnative-web:prod
  docker pull siamaksade/rhsummit18-cloudnative-inventory:prod
  docker pull siamaksade/rhsummit18-cloudnative-web:prod
  docker pull openshiftistio/origin-ansible:0.7.1
  docker pull openshiftistio/mixer-centos7:0.7.1
  docker pull openshiftistio/istio-ca-centos7:0.7.1
  docker pull openshiftistio/proxy-centos7:0.7.1
  docker pull openshiftistio/proxy-init-centos7:0.7.1
  docker pull openshiftistio/pilot-centos7:0.7.1
  docker pull prom/statsd-exporter:v0.5.0
  docker pull openshiftistio/sidecar-injector-centos7:0.7.1
  docker pull registry.centos.org/rhsyseng/elasticsearch:6.2.2
  ```

* Add an admin user to the cluster. Run the following as `system:admin`:

  ```
  oc adm policy add-cluster-role-to-user cluster-admin admin
  ```
