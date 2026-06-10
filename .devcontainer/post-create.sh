#!/bin/bash
set -euo pipefail

workspace_root="/workspaces/openEMS"
src_dir="${workspace_root}/openEMS-Project"
install_prefix="${workspace_root}/.openems-local"
install_marker="${install_prefix}/.openems_installed"
python_marker="${install_prefix}/.python_bindings_installed"
venv_dir="/opt/venv"
build_gui="${OPENEMS_BUILD_GUI:-YES}"
build_jobs="${OPENEMS_BUILD_JOBS:-$(nproc)}"

export PATH="${venv_dir}/bin:${install_prefix}/bin:${PATH}"
export LD_LIBRARY_PATH="${install_prefix}/lib:${LD_LIBRARY_PATH:-}"
export OPENEMS_HOME="${install_prefix}"
export VIRTUAL_ENV="${venv_dir}"

cpp_install_available() {
  [[ -x "${install_prefix}/bin/openEMS" ]] \
    && [[ -x "${install_prefix}/bin/nf2ff" ]] \
    && [[ -f "${install_prefix}/lib/libopenEMS.so" ]] \
    && [[ -f "${install_prefix}/lib/libCSXCAD.so" ]]
}

build_if_needed() {
  if [[ "${OPENEMS_REBUILD:-0}" == "1" ]]; then
    echo "OPENEMS_REBUILD=1 is set; rebuilding openEMS."
  elif [[ -f "${install_marker}" ]] && cpp_install_available; then
    echo "openEMS already installed at ${install_prefix}; skipping build/install."
    return
  fi

  mkdir -p "${install_prefix}"
  local build_args=(
    "--njobs=${build_jobs}"
    --python
    --python-venv-mode=disable
    --python-use-network=disable
  )
  if [[ "${build_gui}" == "NO" || "${build_gui}" == "OFF" || "${build_gui}" == "0" ]]; then
    build_args+=(--disable-GUI)
  fi

  ./update_openEMS.sh "${install_prefix}" \
    "${build_args[@]}"
  touch "${install_marker}"
}

python_bindings_available() {
  "${venv_dir}/bin/python" - <<'PY'
import CSXCAD
import openEMS

print("CSXCAD:", CSXCAD.__file__)
print("openEMS:", openEMS.__file__)
PY
}

install_python_bindings_if_needed() {
  if [[ -f "${python_marker}" ]] && python_bindings_available; then
    echo "openEMS Python bindings already installed in ${venv_dir}; skipping."
    return
  fi

  echo "Installing CSXCAD/openEMS Python bindings into ${venv_dir}..."
  ./scripts/build_python.sh \
    --cpp-install-dir "${install_prefix}" \
    --python-venv-mode=disable \
    --python-use-network=disable
  python_bindings_available
  touch "${python_marker}"
}

if [[ -d "${src_dir}" ]]; then
  cd "${src_dir}"
  if [[ -d .git ]]; then
    git submodule update --init --recursive
  fi
  build_if_needed
  install_python_bindings_if_needed
else
  echo "openEMS-Project not found at ${src_dir}."
  git clone --recursive https://github.com/thliebig/openEMS-Project.git "${src_dir}"
  cd "${src_dir}"
  build_if_needed
  install_python_bindings_if_needed
fi
