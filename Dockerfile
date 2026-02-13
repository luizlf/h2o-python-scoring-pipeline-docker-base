ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY=""
ARG PIP_INDEX_URL=""
ARG PIP_TRUSTED_HOST=""
ARG PYTORCH_WHEEL_URL="https://download.pytorch.org/whl/torch_stable.html"
ARG EPEL_RPM_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm"
ARG INSTALL_TCP_SERVER_DEPS="0"

FROM registry.access.redhat.com/ubi8/ubi:latest AS base

ARG EPEL_RPM_URL

# --------------------------------------------------------------------------
# Optional: custom CA certificates for SSL interception
# Place .crt/.pem files in certs/ directory before building
# --------------------------------------------------------------------------
COPY certs/ /tmp/custom-certs/
RUN if find /tmp/custom-certs -name '*.crt' -o -name '*.pem' 2>/dev/null | grep -q .; then \
        find /tmp/custom-certs \( -name '*.crt' -o -name '*.pem' \) \
            -exec cp {} /etc/pki/ca-trust/source/anchors/ \; ; \
        update-ca-trust extract; \
        echo "Custom CA certificates installed"; \
    fi \
    && rm -rf /tmp/custom-certs

FROM base AS builder

ARG EPEL_RPM_URL
ARG PYTORCH_WHEEL_URL
ARG INSTALL_TCP_SERVER_DEPS

# --------------------------------------------------------------------------
# Build dependencies (includes compilers/dev headers)
# --------------------------------------------------------------------------
RUN dnf install -y \
        "${EPEL_RPM_URL}" \
    && dnf install -y --enablerepo=epel \
        python38 \
        python38-devel \
        python38-pip \
        openblas \
        unzip \
        gcc \
        gcc-c++ \
    && python3.8 -m pip install --no-cache-dir virtualenv \
    && dnf clean all \
    && rm -rf /var/cache/dnf

WORKDIR /scoring

# --------------------------------------------------------------------------
# Pre-install all shared DAI scoring pipeline dependencies
# --------------------------------------------------------------------------
# Use bind mounts so the reference pipeline is never written to a layer.
RUN --mount=type=bind,source=scoring-pipeline,target=/scoring/reference-pipeline \
    --mount=type=bind,source=install_dependencies.sh,target=/scoring/install_dependencies.sh \
    INSTALL_TCP_SERVER_DEPS="${INSTALL_TCP_SERVER_DEPS}" \
    PYTORCH_WHEEL_URL="${PYTORCH_WHEEL_URL}" \
    bash /scoring/install_dependencies.sh \
    && rm -rf /scoring/env_app_data_dir /tmp/* /root/.cache/pip

FROM base AS runtime

ARG EPEL_RPM_URL

# --------------------------------------------------------------------------
# Runtime-only system dependencies (no compiler toolchain)
# --------------------------------------------------------------------------
RUN dnf install -y \
        "${EPEL_RPM_URL}" \
    && dnf install -y --enablerepo=epel \
        python38 \
        openblas \
        libgomp \
        unzip \
    && dnf clean all \
    && rm -rf /var/cache/dnf

WORKDIR /scoring

COPY --from=builder /scoring/env /scoring/env

# --------------------------------------------------------------------------
# Runtime scripts
# --------------------------------------------------------------------------
COPY load_pipeline.sh /scoring/load_pipeline.sh
COPY entrypoint.sh /scoring/entrypoint.sh
RUN chmod +x /scoring/load_pipeline.sh /scoring/entrypoint.sh

EXPOSE 9090

ENTRYPOINT ["/scoring/entrypoint.sh"]
