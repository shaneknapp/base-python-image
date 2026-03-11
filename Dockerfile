# ===================================================================
# Base image
# ===================================================================
FROM buildpack-deps:noble-scm AS base

# -------------------------------------------------------------------
# Environment
# -------------------------------------------------------------------
ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

ENV NB_USER=jovyan
ENV NB_UID=1000

ENV CONDA_DIR=/srv/conda
ENV DEFAULT_PATH=${PATH}

# -------------------------------------------------------------------
# Locale + user
# -------------------------------------------------------------------
RUN apt-get -qq update --yes && \
    apt-get -qq install --yes locales && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

RUN echo "Deleting user/group ubuntu (UID/GID 1000)..." && \
    (userdel -f ubuntu || true) && \
    (groupdel ubuntu || true)  && \
    echo "Creating ${NB_USER} user with UID/GID 1000..." && \
    adduser --disabled-password --gecos "Default Jupyter user" --uid ${NB_UID} ${NB_USER} && \
    # Set home directory of jovyan user
    usermod --home /home/${NB_USER} --move-home ${NB_USER} && \
    # Make sure that /srv is owned by non-root user, so we can install things there    
    install -d -o ${NB_USER} -g ${NB_USER} /srv

# -------------------------------------------------------------------
# Man pages
# -------------------------------------------------------------------
RUN sed -i '/usr.share.man/s/^/#/' /etc/dpkg/dpkg.cfg.d/excludes
RUN apt --reinstall install coreutils

# -------------------------------------------------------------------
# System packages
# -------------------------------------------------------------------
COPY apt.txt /tmp/apt.txt
RUN apt-get -qq update --yes && \
    apt-get -qq install --yes --no-install-recommends \
        $(grep -v ^# /tmp/apt.txt) && \
    apt-get -qq purge && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/*

# Remove diverted man binary
RUN if [ "$(dpkg-divert --truename /usr/bin/man)" = "/usr/bin/man.REAL" ]; then \
        rm -f /usr/bin/man; \
        dpkg-divert --quiet --remove --rename /usr/bin/man; \
    fi

RUN mandb -c

# ===================================================================
# Build /srv/conda and notebook environment
# ===================================================================
FROM base AS srv-conda

USER root
RUN install -d -o ${NB_USER} -g ${NB_USER} ${CONDA_DIR}

USER ${NB_USER}

# Install Miniforge
COPY --chown=${NB_USER}:${NB_USER} install-miniforge.bash /tmp/install-miniforge.bash
RUN bash /tmp/install-miniforge.bash && \
    rm /tmp/install-miniforge.bash

ENV PATH=${CONDA_DIR}/bin:$PATH

# Copy environment.yml as NB_USER so we can remove it later
COPY --chown=${NB_USER}:${NB_USER} environment.yml /tmp/environment.yml

# -------------------------------------------------------------------
# Create a new environment called 'notebook'
# -------------------------------------------------------------------
RUN mamba env create -n notebook -f /tmp/environment.yml && \
    mamba clean -afy && \
    rm /tmp/environment.yml

# Use notebook env by default
ENV PATH=${CONDA_DIR}/envs/notebook/bin:$PATH

# Verify installation
RUN mamba list -n notebook

# ===================================================================
# Final image
# ===================================================================
FROM base AS final

USER root
COPY --chown=${NB_USER}:${NB_USER} --from=srv-conda /srv/conda /srv/conda

USER ${NB_USER}
ENV PATH=${CONDA_DIR}/envs/notebook/bin:${CONDA_DIR}/bin:${DEFAULT_PATH}

# Cleanup temp files
USER root
RUN rm -rf /tmp/*
RUN rm -rf /root/.cache

USER ${NB_USER}
WORKDIR /home/${NB_USER}

EXPOSE 8888

ENTRYPOINT ["tini", "--"]
