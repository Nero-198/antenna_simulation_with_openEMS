FROM ubuntu:24.04

SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive

# Install openEMS build/runtime dependencies and common CLI tools.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        fontconfig \
        fonts-freefont-otf \
        git \
        hdf5-tools \
        libboost-all-dev \
        libcgal-dev \
        libfftw3-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libhdf5-dev \
        libtinyxml-dev \
        libtinyxml2-dev \
        libvtk9-dev \
        libvtk9-qt-dev \
        libx11-dev \
        libxcursor-dev \
        libxext-dev \
        libxinerama-dev \
        libxi-dev \
        libxmu-dev \
        libxrandr-dev \
        libxrender-dev \
        libxt-dev \
        nano \
        octave \
        octave-dev \
        python3-dev \
        python3-pip \
        python3-setuptools-scm \
        python3-venv \
        qtbase5-dev \
        sudo \
        vim \
    && rm -rf /var/lib/apt/lists/*

# Create a Python virtual environment used by default.
RUN python3 -m venv /opt/venv

ENV PATH="/opt/venv/bin:${PATH}"

# Upgrade pip inside the Python virtual environment and preinstall the packages
# needed to build and use the openEMS Python bindings.
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir \
        Cython \
        h5py \
        ipython \
        matplotlib \
        numpy \
        scipy \
        setuptools_scm \
        sympy \
        tqdm

# Create or reuse a non-root user for devcontainer usage.
ARG USERNAME=ubuntu
ARG USER_UID=1000
ARG USER_GID=1000

RUN if ! id -u "${USERNAME}" >/dev/null 2>&1; then \
        if getent group "${USER_GID}" >/dev/null; then \
            group_name="$(getent group "${USER_GID}" | cut -d: -f1)"; \
        else \
            groupadd --gid "${USER_GID}" "${USERNAME}"; \
            group_name="${USERNAME}"; \
        fi; \
        useradd --uid "${USER_UID}" --gid "${group_name}" -m "${USERNAME}"; \
    fi \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}" \
    && chown -R "${USERNAME}:${USERNAME}" /opt/venv

USER ${USERNAME}

WORKDIR /workspaces/openEMS
