FROM adoptopenjdk/openjdk11 as builder

ARG DEBIAN_FRONTEND=noninteractive CLOJVER=1.10.3.1087 MB_EDITION=oss
#ARG CLOJVER=1.10.3.814

# coreutils:    needed for the basic tools
# ttf-dejavu:   needed for POI
# fontconfig:   needed for POI
# bash:         various shell scripts
# yarn:         frontend building
# nodejs:       frontend building
# git:          ./bin/version
# curl:         needed by script that installs Clojure CLI & Lein

RUN apt update && apt -y install build-essential git bash rlwrap curl fontconfig openssl awscli ttf-dejavu && \
    curl -fsSL https://deb.nodesource.com/setup_14.x | bash -s && apt install nodejs && \
#    curl -o- -L https://yarnpkg.com/install.sh | bash -s &&
    npm install --global yarn && \
    apt-get clean && \
    curl https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein -o /usr/local/bin/lein && \
    chmod +x /usr/local/bin/lein && \
    /usr/local/bin/lein upgrade && \
    curl https://download.clojure.org/install/linux-install-${CLOJVER}.sh -o /tmp/linux-install-${CLOJVER}.sh && \
    chmod +x /tmp/linux-install-${CLOJVER}.sh && \
    /tmp/linux-install-${CLOJVER}.sh


COPY --chown=circleci metabase /home/circleci
WORKDIR /home/circleci
RUN INTERACTIVE=false CI=true MB_EDITION=$MB_EDITION bin/build

###########
# STAGE 2 #
###########

FROM eclipse-temurin:11-jre as runner

ENV FC_LANG en-US LC_CTYPE en_US.UTF-8 DEBIAN_FRONTEND=noninteractive

# dependencies
RUN apt update && apt install -y --no-install-recommends bash fonts-dejavu-core fontconfig curl ca-certificates-java unzip && \
    apt-get clean && \
    mkdir -p /app/certs && \
    curl https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -o /app/certs/rds-combined-ca-bundle.pem  && \
    /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias aws-rds -file /app/certs/rds-combined-ca-bundle.pem -keystore /etc/ssl/certs/java/cacerts -keypass changeit -storepass changeit && \
    curl https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem -o /app/certs/DigiCertGlobalRootG2.crt.pem  && \
    /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias azure-cert -file /app/certs/DigiCertGlobalRootG2.crt.pem -keystore /etc/ssl/certs/java/cacerts -keypass changeit -storepass changeit && \
    mkdir -p /plugins /data/ && chmod a+rwx /plugins /data

# add Metabase script and uberjar
COPY --from=builder /home/circleci/target/uberjar/metabase.jar /app/
COPY metabase/bin/docker/run_metabase.sh /app/

# add Crowdsec support
RUN curl https://crowdsec-statics-assets.s3-eu-west-1.amazonaws.com/metabase_sqlite.zip -o /tmp/metabase_sqlite.zip && \
    unzip /tmp/metabase_sqlite.zip -d /data/

# expose our default runtime port
EXPOSE 3000

# run it
ENTRYPOINT ["/app/run_metabase.sh"]
