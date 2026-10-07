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

command -v python3 >/dev/null || fail "python3 is missing: sudo apt install python3 python3-venv"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || fail "holoswarm-client needs python >= 3.11, found $(python3 --version)"
python3 -c 'import ensurepip, venv' 2>/dev/null || fail "python3 venv is missing: sudo apt install python3-venv"

command -v tmuxinator >/dev/null || warn "tmuxinator is missing; only ./tmux/start.sh needs it (sudo apt install tmuxinator)"
command -v lazydocker >/dev/null || warn "lazydocker is missing; optional, see https://github.com/jesseduffield/lazydocker"

# | -------------------------- submodules --------------------------- |

step "Checking out the submodules at their pinned commits"
git submodule sync --recursive
git submodule update --init --recursive

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

step "Installing holoswarm-client into holoswarm-client/.venv"
unset PYTHONPATH   # a sourced ROS environment would leak its packages into pip's view of the venv
if [[ ! -x holoswarm-client/.venv/bin/python ]]; then
  python3 -m venv holoswarm-client/.venv
fi
holoswarm-client/.venv/bin/pip install --quiet --upgrade pip
holoswarm-client/.venv/bin/pip install --quiet -e holoswarm-client

cat <<EOF

==> Setup done. Next:

  ./compose/up.sh simulation                                # ground stack + simulated uav14, uav16
  (cd holoswarm-client && .venv/bin/holoswarm-client)       # the GUI
  ./compose/down.sh                                         # stop everything

See README.md for running an experiment with real UAVs.
EOF
