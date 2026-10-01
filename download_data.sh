#!/usr/bin/env bash
# Download the Male CNS connectome data and convert it for the viewer.
# Result: data/ (meshes, neurons, synaptic graph, fly body). Raw downloads are cached
# in data/raw/, so re-runs are fast and resumable.
#
#   ./download_data.sh                     # in Docker (default; needs only Docker)
#   ./download_data.sh --neurons 2         # extra args go to fetch_data.py (denser sample)
#   ./download_data.sh --local             # use the host's python instead of Docker
#
# Docker is the default because the pipeline's dependencies (fast-simplification,
# cloud-volume, pyarrow) need an interpreter they publish wheels for; a host python that
# is too new, or externally managed without venv support, cannot install them.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE=${IMAGE:-godot-fly-data}
mkdir -p data

if [ "${1:-}" = "--local" ]; then
    shift
    PY=${PYTHON:-python3}
    if ! "$PY" -c "import numpy, pandas, pyarrow, trimesh, fast_simplification, cloudvolume" 2>/dev/null; then
        echo ">> installing python dependencies"
        "$PY" -m pip install -q -r tools/requirements.txt \
            || "$PY" -m pip install -q --break-system-packages -r tools/requirements.txt
    fi
    exec env PYTHON="$PY" bash tools/pipeline.sh "$@"
fi

if ! command -v docker >/dev/null; then
    echo "docker not found — install Docker, or run ./download_data.sh --local" >&2
    exit 1
fi

echo ">> building $IMAGE"
docker build -q -t "$IMAGE" . >/dev/null

echo ">> running the pipeline in $IMAGE"
docker run --rm \
    -v "$PWD/data:/app/data" \
    --user "$(id -u):$(id -g)" \
    "$IMAGE" "$@"
