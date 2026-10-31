# Jenkins with the plugins the platform pipelines need, installed at image
# build time instead of clicked through the setup wizard.
#
# Built on the CI box by `make deploy` (docker compose up --build). The
# jenkins_home volume keeps jobs, builds and credentials across rebuilds;
# plugins listed here are copied into it on start when missing.

FROM jenkins/jenkins:lts-jdk21

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt

# Resolves each plugin and its dependencies to the newest version compatible
# with this Jenkins core. Pin `name:version` in plugins.txt to hold one back.
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
