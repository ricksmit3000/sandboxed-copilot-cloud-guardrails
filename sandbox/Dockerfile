FROM docker/sandbox-templates:copilot

USER root

RUN apt-get update && \
        apt-get install -y --no-install-recommends curl jq unzip && \
        arch="$(dpkg --print-architecture)" && \
        case "${arch}" in \
            amd64) aws_arch="x86_64" ;; \
            arm64) aws_arch="aarch64" ;; \
            *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
        esac && \
        curl "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "/tmp/awscliv2.zip" && \
    unzip /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

USER agent
