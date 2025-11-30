FROM eclipse-temurin:21

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

COPY eclipse-download.sh /usr/local/bin/eclipse-download
RUN chmod +x /usr/local/bin/eclipse-download

COPY plugin/io.github.nbauma109.refactoring.cli-1.0.0.jar /opt/io.github.nbauma109.refactoring.cli-1.0.0.jar

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
