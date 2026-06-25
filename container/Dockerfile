FROM mambaorg/micromamba:2.5.0

USER root

RUN apt-get update && apt-get install -y procps && rm -rf /var/lib/apt/lists/*

USER $MAMBA_USER

COPY --chown=$MAMBA_USER:$MAMBA_USER ./container/environment.yml /tmp/

RUN micromamba install -y -n base -f /tmp/environment.yml && \
    micromamba clean --all --yes

ARG MAMBA_DOCKERFILE_ACTIVATE=1

# adding the path to the tools managed by mamba
ENV PATH="/opt/conda/bin:$PATH"