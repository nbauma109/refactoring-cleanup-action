FROM eclipse-temurin:25

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

RUN curl --fail --location --silent --show-error --retry 3 \
      https://github.com/nbauma109/refactoring-cli/releases/download/2.0.0/io.github.nbauma109.refactoring.cli-2.0.0.jar \
      --output /opt/io.github.nbauma109.refactoring.cli-2.0.0.jar && \
    echo "38bd5b5cb94d013eab5674d3c11b7f6c33f136306b2556b28c66925aece4f0dc  /opt/io.github.nbauma109.refactoring.cli-2.0.0.jar" | sha256sum --check

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
