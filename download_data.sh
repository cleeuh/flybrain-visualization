#!/usr/bin/env bash
# Download the Male CNS connectome data and convert it for the viewer.
# Result: data/ (meshes, neurons, synaptic graph). Raw downloads are cached in data/raw/.
#
#   ./download_data.sh                # defaults (~5k neurons)
#   ./download_data.sh --neurons 2    # extra args go to fetch_data.py (denser sample)
set -euo pipefail
cd "$(dirname "$0")"

PY=${PYTHON:-python3}
if ! "$PY" -c "import numpy, pandas, pyarrow, trimesh, fast_simplification, cloudvolume" 2>/dev/null; then
    echo ">> installing python dependencies"
    "$PY" -m pip install -q -r tools/requirements.txt \
        || "$PY" -m pip install -q --break-system-packages -r tools/requirements.txt
fi

echo ">> 1/2 meshes + neuron skeletons"
"$PY" tools/fetch_data.py "$@"

echo ">> 2/2 synaptic graph + neuropil membership (downloads ~1.2 GB of tables)"
"$PY" tools/build_sim.py

echo ">> done:"
du -sh data/meshes data/neurons.mm data/edges.bin
