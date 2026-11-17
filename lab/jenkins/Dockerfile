FROM jenkins/jenkins:lts-jdk17

USER root

# Herramientas que el pipeline y los labs necesitan (docker CLI incluido:
# el contenedor habla con el daemon del host por /var/run/docker.sock).
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl wget git jq zip unzip netcat-openbsd iproute2 python3 ca-certificates docker-cli \
    && rm -rf /var/lib/apt/lists/*

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt

COPY casc /usr/share/jenkins/ref/casc

# Flags de los labs de Jenkins
RUN echo 'FLAG{jenkins_anon_script_console}' > /usr/share/jenkins/ref/flag.txt \
 && mkdir -p /usr/share/jenkins/ref/secrets \
 && echo 'FLAG{jenkins_update_job_rce}' > /usr/share/jenkins/ref/secrets/flag-rce.txt

USER jenkins
