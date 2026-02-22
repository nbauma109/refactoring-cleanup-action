FROM eclipse-temurin:21

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
      curl \
      unzip \
      xvfb \
      libgtk-3-0 \
      libasound2t64 \
      libcairo2 \
      libgtk-3-bin \
      libxtst6 \
      libxi6 \
      libxrender1 \
      libxcomposite1 \
      libxdamage1 \
      libxrandr2 \
      libatk1.0-0 \
      libgdk-pixbuf-2.0-0 \
      libpangocairo-1.0-0 \
      libpango-1.0-0 \
      libxfixes3 \
      libxcb1 \
    && rm -rf /var/lib/apt/lists/*

COPY eclipse-download.sh /usr/local/bin/eclipse-download
RUN chmod +x /usr/local/bin/eclipse-download

COPY plugin/io.github.nbauma109.refactoring.cli-1.0.1.jar /opt/io.github.nbauma109.refactoring.cli-1.0.1.jar

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
