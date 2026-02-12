FROM registry.access.redhat.com/ubi8/ubi:latest

# --------------------------------------------------------------------------
# System dependencies (RHEL 8 / UBI 8)
# --------------------------------------------------------------------------
RUN dnf install -y \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm \
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
COPY scoring-pipeline/ /scoring/reference-pipeline/
COPY install_dependencies.sh /scoring/install_dependencies.sh

RUN chmod +x /scoring/install_dependencies.sh \
    && bash /scoring/install_dependencies.sh \
    && rm -rf /scoring/reference-pipeline /scoring/env_app_data_dir /tmp/* /root/.cache/pip

# --------------------------------------------------------------------------
# Runtime scripts
# --------------------------------------------------------------------------
COPY load_pipeline.sh /scoring/load_pipeline.sh
COPY entrypoint.sh /scoring/entrypoint.sh
RUN chmod +x /scoring/load_pipeline.sh /scoring/entrypoint.sh

EXPOSE 9090

ENTRYPOINT ["/scoring/entrypoint.sh"]
