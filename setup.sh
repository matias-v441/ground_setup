#!/usr/bin/env bash
# One-time (and idempotent) setup of the ground station: submodules, PROJ grids, the ROS workspace build
# in docker, and the holoswarm-client Python environment. Afterwards: ./compose/up.sh simulation
#
#   ./setup.sh             # everything
#   MRS_SYSTEM_IMAGE=<image> ./setup.sh   # build against another MRS system image (default ctumrs/mrs_uav_system:stable)
#
# Like `git submodule update`, it checks out the commits recorded in this repository: commit submodule work and
# its new pointer here first, or a submodule's branch is left behind (detached HEAD at the recorded commit).

set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

PROJ_GRIDS=(cz_cuzk_CR-2005.tif us_nga_egm96_15.tif)

# uv and the python it installs for holoswarm-client live in .uv/, independent of any uv or python on the host
UV_VERSION=0.13.6
UV="$PWD/.uv/bin/uv"
export UV_PYTHON_INSTALL_DIR="$PWD/.uv/python"
export UV_PYTHON_PREFERENCE=only-managed   # never a system python, whatever version the host has

step() { echo; echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }

# | ------------------------- prerequisites ------------------------- |

step "Checking prerequisites"

command -v git >/dev/null || fail "git is missing: sudo apt install git"
command -v curl >/dev/null || fail "curl is missing: sudo apt install curl"

command -v docker >/dev/null || fail "docker is missing, install it with:
  bash <(curl -fsSL https://raw.githubusercontent.com/ctu-mrs/mrs_docker/master/install/install_docker_ubuntu.sh)"
docker compose version >/dev/null 2>&1 || fail "the docker compose plugin is missing (or docker cannot be used by $USER, see 'docker info')"

command -v tmuxinator >/dev/null || warn "tmuxinator is missing; only ./tmux/start.sh needs it (sudo apt install tmuxinator)"
command -v lazydocker >/dev/null || warn "lazydocker is missing; optional, see https://github.com/jesseduffield/lazydocker"

# | -------------------------- submodules --------------------------- |

step "Checking out the submodules at their pinned commits"
git submodule sync --recursive
git submodule update --init --recursive
# An interrupted clone can leave a submodule fetched, at the right commit, but never checked out (empty index,
# no files); `submodule update` skips it as up to date. With an empty index there is nothing to lose: restore it.
git submodule foreach --recursive --quiet '
  if [ -z "$(git ls-files | head -n 1)" ] && [ -n "$(git ls-tree HEAD | head -n 1)" ]; then
    echo "restoring $displaypath: cloned, but its files were never checked out"
    git reset --quiet --hard HEAD
  fi'
git submodule update --init --recursive   # submodules of restored ones

# | --------------------- data directories -------------------------- |

step "Downloading the PROJ grids into .proj"
mkdir -p .proj .assets
for grid in "${PROJ_GRIDS[@]}"; do
  if [[ -f ".proj/$grid" ]]; then
    echo "$grid already present"
  else
    echo "downloading $grid"
    curl --fail --silent --show-error --location -o ".proj/$grid.part" "https://cdn.proj.org/$grid"
    mv ".proj/$grid.part" ".proj/$grid"
  fi
done

# | ------------------------ ROS workspace -------------------------- |

step "Building holoswarm_ros_packages in docker (pulls the MRS system image on the first run)"
./compose/build.sh

# | ------------------------ holoswarm-client ----------------------- |

step "Installing uv $UV_VERSION into .uv"
if [[ -x "$UV" && "$("$UV" --version)" == "uv $UV_VERSION "* ]]; then
  echo "uv $UV_VERSION already present"
else
  curl --fail --silent --show-error --location "https://astral.sh/uv/$UV_VERSION/install.sh" \
    | UV_INSTALL_DIR="$PWD/.uv/bin" UV_NO_MODIFY_PATH=1 sh -s -- --quiet
fi

step "Installing holoswarm-client into holoswarm-client/.venv"
unset PYTHONPATH   # a sourced ROS environment would leak its packages into the venv
(
  cd holoswarm-client
  # Keep the venv if it is built on the managed python that uv picks for requires-python in pyproject.toml.
  # Otherwise (first run, a venv from the system python, requires-python changed) recreate it: `uv venv` downloads
  # that python into .uv/python.
  python="$("$UV" python find --system 2>/dev/null || true)"
  if [[ -z "$python" || ! -x .venv/bin/python ]] \
      || [[ "$(sed -n 's/^home = //p' .venv/pyvenv.cfg 2>/dev/null)" != "$(dirname "$python")" ]]; then
    "$UV" venv --clear --quiet .venv
  fi
  "$UV" pip install --quiet --python .venv/bin/python -e .
  echo "$(.venv/bin/python --version) in holoswarm-client/.venv"
)

cat <<EOF

==> Setup done. Next:

  ./compose/up.sh simulation                                # ground stack + simulated uav14, uav16
  (cd holoswarm-client && .venv/bin/holoswarm-client)       # the GUI
  ./compose/down.sh                                         # stop everything

See README.md for running an experiment with real UAVs.
EOF
