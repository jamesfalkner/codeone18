# Code One 2018: <br/>Getting Started with Cloud-Native Applications Lab Guide

Lab guides for the Cloud-Native Lab at Code One 2018

## Deploy this lab on your own OpenShift cluster

This lab uses an Ansible playbook to deploy itself to a running OpenShift cluster with Istio Tech Preview installed. To deploy this lab yourself, see the [README in the ansible directory](ansible/README.md)

## Deploy Lab Guides On OpenShift

You can deploy Workshopper as a container image anywhere but most conveniently, you can deploy it on OpenShift Online or other OpenShift flavours:

```
$ oc new-app quay.io/osevg/workshopper --name=guides \
      -e WORKSHOPS_URLS="https://raw.githubusercontent.com/jamesfalkner/codeone18/master/_codeone18.yml" \
      -e JAVA_APP=false 
$ oc expose svc/guides
```

The lab content (`.md` and `.adoc` files) will be pulled from the GitHub when users access the workshopper in 
their browser.

Note that the workshop variables can be overriden via specifying environment variables on the container itself e.g. the `JAVA_APP` env var in the above command

## Test Guides Locally with Docker

You can directly run Workshopper as a docker container which is especially helpful when writing the content.
```
$ docker run -it -p 8080:8080 -v $(pwd):/app-data \
              -e CONTENT_URL_PREFIX="file:///app-data" \
              -e WORKSHOPS_URLS="file:///app-data/_codeone18.yml" \
              quay.io/osevg/workshopper:latest 
```

Go to http://localhost:8080 on your browser to see the rendered workshop content. You can modify the lab instructions 
and refresh the page to see the latest changes.

