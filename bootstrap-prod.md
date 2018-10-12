## Automate PROD Release

In previous labs you created the Catalog service and now it's time to release it 
to the production environment. Releasing software to production is always associated with midnight
caffeine-intensive processes with traumatizing effects when it does not go well!

As you have noticed, automation is a key principle when building cloud native applications,
and that does not exclude the release process. Although many teams might not want to automatically 
release their software into production, the process still has to be automated and be able to 
go forward with push of a button.

In this lab, you will create a release pipeline that creates a release for the Catalog service by 

* Tagging the source code in Git repository
* Publishing the release artifacts to the Maven repository 
* Building and tagging the release container image for Catalog 
* Deploy the release container image into production

The production environment is already set up on your OpenShift cluster with the project 
name **CoolStore PROD**. Browse the production project in the OpenShift Web Console.

#### Define Release Pipeline

In Eclipse Che, right-click in the in the root of catalog directory and then click on 
**New** > **File** and name it `Jenkinsfile.release`. Paste the following pipeline definition 
into `Jenkinsfile.release`:

~~~shell
def releaseTag

pipeline {
  agent {
      label 'maven'
  }
  stages {
    stage('Release Code') {
      environment {
        SCM_GIT_URL = sh(returnStdout: true, script: 'git config remote.origin.url').trim()
      }
      steps {
        sh "git config --local user.email 'jenkins@cicd.com'"
        sh "git config --local user.name 'jenkins'"
        sh "git checkout master"

        script {
          releaseTag = readMavenPom().getVersion().replace("-SNAPSHOT", "")
          openshift.withCluster() {
            withCredentials([usernamePassword(credentialsId: "${openshift.project()}-git-credentials", usernameVariable: "GIT_USERNAME", passwordVariable: "GIT_PASSWORD")]) {
              sh "mvn --batch-mode release:clean release:prepare release:perform -s .settings.xml"
            }
          }
        }
      }
    }
  }
}
~~~

The above stage uses the [Maven Release Plugin](http://maven.apache.org/maven-release/maven-release-plugin/){:target="_blank"} to release
the Catalog code and JAR archives in the Git repository and Maven repository respectively. In addition, this stage 
performs the following steps as the part of the release process:

* Checks that there are no SNAPSHOT dependencies in `pom.xml`
* Changes the version in the POMs from `x-SNAPSHOT` to a new version
* Transforms the Git information in the POM to include the final destination of the tag
* Runs the project tests against the modified POMs to confirm everything is in working order
* Commits the modified POMs to the Catalog Git repository
* Tags the code in the Git repository with a version name
* Bumps the version in the POMs to a new value `y-SNAPSHOT`
* Commits the modified POMs

Since the release process involves committing code to the Catalog Git repository, we would expect the build pipeline 
also get triggered during the release in order to build and test the new `y-SNAPSHOT` version fo the Catalog service.

The next stage in the release pipeline is to create the release container image based on the released Catalog
artifacts. The release container image is what will be used across all environments and will be verified through 
various tests to make sure it can to into production. It's critical to build the container image once and only once and
perform all tests on the exact same release image to ensure the integrity of the release as it is promoted across different
environments (in this case, _dev > prod_).

Add the `Release Image` stage right after `Release Code` in the `Jenkinsfile.release`

|**CAUTION:** Be sure to place the below code at the correct indentation level, so that the individual `stage{...}` elements are at the same curly-brace level! In particular, be aware of the presence of `stages{...}` as the containing element for all of the `stage{...}` elements.

~~~shell
    stage('Release Image') {
      steps {
        script {
          openshift.withCluster() {
            echo "Releasing catalog image version ${releaseTag}"
            openshift.tag("${openshift.project()}/catalog:latest", "${openshift.project()}/catalog:${releaseTag}")
          }
        }
      }
    }    
~~~

Notice that the Catalog release image is tagged with the release version, similar to the JAR files in the Maven 
repository.

The next stage is to promote the Catalog release image to production and deploy it. You can take advantage of
[OpenShift deployment triggers]({{OPENSHIFT_DOCS_BASE}}/dev_guide/deployments/basic_deployment_operations.html#triggers){:target="_blank"} 
to automate deployment of the new release. Deployment triggers can drive the creation of new deployments
in response to events (new images built, configuration changes) inside the OpenShift cluster.

Add the `Promote to PROD` stage right after `Release Image` in the `Jenkinsfile.release`

~~~shell
    stage('Promote to PROD') {
      steps {
        script {
          openshift.withCluster() {
            def devNamespace = openshift.project()
            openshift.withProject(env.PROD_PROJECT) {
              openshift.tag("${devNamespace}/catalog:${releaseTag}", "${openshift.project()}/catalog:prod")
            }
          }
        }
      }
    }    
~~~

Since the Catalog deployment in production tracks the `catalog:prod` image, tagging the new Catalog release 
image with `prod` in production will trigger an automatic deployment of the new image.

Commit the `Jenkinsfile.release` into the Git repository by right-clicking on the catalog in the project 
explorer and then on **Git** > **Commit**.

Make sure `Jenkinsfile.release` is checked. Enter a commit message to describe your change. Check the 
**Push commit changes to...** to push the commit directly to the git server and then click on **Commit***

![Eclipse Che - Jenkinsfile Commit]({% image_path prod-pipeline-commit.png %}){:width="600px"}

#### Credentials in the Pipeline

As discussed, the release pipeline interacts with the Catalog Git repository and creates a release tag 
in the repository. For doing so, the pipeline needs to authenticate itself to the Git repository.

Jenkins provides a central way to define and consume credentials (e.g. Git repository username and password) 
in the pipeline and in fact anywhere else applicable throughout Jenkins. When a credential is defined in 
Jenkins, it can be used inside the pipelines using the `withCredentials() {...}` expression. It will essentially 
retrieve the credentials from the Jenkins credentials store and inject them into the pipeline as environment variables.

Jenkins credentials are very useful, but following immutable infrastructure principles, you shouldn't store sensitive
information or any configuration for that matter inside Jenkins.

Fortunately, OpenShift has an elegant way to integrate 
[the built-in secret management]({{OPENSHIFT_DOCS_BASE}}/dev_guide/secrets.html){:target="_blank"} 
that exists in Kubernetes with Jenkins credentials. The Jenkins container image on OpenShift has
[a number of plugins pre-installed]({{OPENSHIFT_DOCS_BASE}}/using_images/other_images/jenkins.html#sync-plug-in){:target="_blank"} 
that automatically import certain secrets into Jenkins credentials which can then be used in the pipeline. Note 
that the [sync plugin](https://github.com/openshift/jenkins-sync-plugin){:target="_blank"} 
can also be installed on any Jenkins running elsewhere to provide the secret-credentials sync capability.

Create a secret in the **Catalog DEV** project to secure store the Catalog Git repository credentials:

~~~shell
oc create secret generic git-credentials --from-literal=username={{ GIT_USERNAME }} --from-literal=password={{ GIT_PASSWORD }}
~~~

In order to instruct OpenShift to inject this secret as a Jenkins credential into Jenkins, you should label 
the secret:

~~~shell
oc label secret git-credentials credential.sync.jenkins.openshift.io=true
~~~

That's it! Now this secret will be automatically available in Jenkins as a credential. If you look closely in 
the `Jenkinsfile.release` pipeline, you will notice that you have already included the `withCredentials(){}` expression 
to use the Jenkins credentials for authentication against the Catalog git repository.

~~~shell
  ...

  withCredentials([usernamePassword(credentialsId: "${openshift.project()}-git-credentials", usernameVariable: "GIT_USERNAME", passwordVariable: "GIT_PASSWORD")]) {
    sh "mvn --batch-mode release:clean release:prepare release:perform -s .settings.xml"
  }

  ...
~~~

The `withCredentials` expression sets the `GIT_USERNAME` and `GIT_PASSWORD` environment variables which are then used by 
the `.settings.xml` maven settings to configure the Maven Release Plugin.


#### Pipeline Access to Production

OpenShift by default maintains a tight access control regime and does not allow services from one project to 
modify other projects. In this lab, you want Jenkins to be able to tag
images in the production environment and deploy containers while executing the release pipeline. For that, you have to explicitly give access to the
Jenkins pod, or to say more accurately to the [service account]({{OPENSHIFT_DOCS_BASE}}/dev_guide/service_accounts.html){:target="_blank"} 
that the Jenkins pod uses for authentication and making API calls to OpenShift.

Service accounts in OpenShift are in form of `system:serviceaccount:<project>:<name>` and Jenkins specifically 
uses the `system:serviceaccount:<project>:jenkins`. The _\<project\>_ expression is the name of the namespace where Jenkins 
is deployed.

Grant the service account which is used by Jenkins access to tag images and deploy pods in the production environment:

~~~shell
oc policy add-role-to-user admin system:serviceaccount:dev:jenkins -n prod{{ PROJECT_SUFFIX }}
~~~

#### Create OpenShift Pipeline

You can now create an OpenShift Pipeline that uses the `Jenkinsfile.release` definition from the Catalog Git 
repository to create a pipeline. 

In the [Catalog DEV Project Console]({{ OPENSHIFT_MASTER_URL }}/console/project/dev{{PROJECT_SUFFIX}}){:target="_blank"}, click on **Add to Project** > **Import YAML/JSON**.

![Import YAML/JSON]({% image_path bootstrap-prod-import-yaml.png %}){:width="700px"}

Then copy the following and paste in the field and then click on **Create**.

~~~yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: catalog-release
spec:
  runPolicy: Serial
  source:
    git:
      ref: master
      uri: "http://{{ GIT_HOSTNAME }}/{{ GIT_USERNAME }}/catalog.git"
    type: Git
  strategy:
    jenkinsPipelineStrategy:
      env:
        - name: PROD_PROJECT
          value: "prod{{ PROJECT_SUFFIX }}"
      jenkinsfilePath: Jenkinsfile.release
    type: JenkinsPipeline
~~~

Click on **Create**. 

In the **Catalog DEV** project go to **Builds** > **Pipelines** and click on **Start Pipeline** near 
the **catalog-release** pipeline.

![Catalog Release Pipeline]({% image_path boostrap-prod-release-pipeline.png %}){:width="900px"}

Did you notice that while the **catalog-release** pipeline is running, the **catalog-build** pipeline also 
started running? The reason for that is that during the release process, `pom.xml` is modified to increase the version 
number and is pushed back to the catalog git repository. You wanted **catalog-build** pipeline 
to run on every change that takes place in the git repository, right?

After the release pipeline completes successfully (all green, yaay!),
[go the git repository in your browser](http://{{GIT_HOSTNAME}}/{{GIT_USERNAME}}/catalog/releases){:target="_blank"} to
review the Catalog release that is created in the Git repository.

![Catalog Git Releases]({% image_path boostrap-prod-git-releases.png %}){:width="900px"}

Navigate to the [Nexus Maven Repository]({{NEXUS_EXTERNAL_URL}}/#browse/browse:maven-releases:com%2Fredhat%2Fcoolstore%2Fcatalog){:target="_blank"} to review the binary release of
the Catalog service in form of a JAR file:

![Catalog Released Artifacts in Nexus]({% image_path boostrap-prod-nexus-releases.png %}){:width="800px"}

Go to the [CoolStore Production Project Console]({{ OPENSHIFT_MASTER_URL }}/console/project/prod{{PROJECT_SUFFIX}}){:target="_blank"} and click on the **web-ui** route url to verify
CoolStore application is working ([or click here to access it directly](http://web-ui-prod{{PROJECT_SUFFIX}}.{{APPS_HOSTNAME_SUFFIX}}){:target="_blank"}).
