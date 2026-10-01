#!/usr/bin/env bash
# The data pipeline, in order. Run by download_data.sh (inside Docker or, with --local,
# directly). Extra arguments are passed to fetch_data.py (e.g. --neurons 2 --skel-eps 0.5).
set -euo pipefail
cd "$(dirname "$0")/.."

PY=${PYTHON:-python3}

echo ">> 1/3 neuropil meshes + neuron skeletons"
"$PY" tools/fetch_data.py "$@"

echo ">> 2/3 synaptic graph + neuropil membership (downloads ~1.2 GB of tables)"
"$PY" tools/build_sim.py

echo ">> 3/3 fly body model (flybody, Apache-2.0; ~36 MB)"
"$PY" tools/fetch_fly_body.py

echo ">> checking the files the viewer loads"
missing=0
for f in neurons.mm neurons.json rois.json sim.json edges.bin fly.json \
         meshes/brain_shell.bmesh meshes/vnc_shell.bmesh meshes/fly_body.bmesh; do
    [ -s "data/$f" ] || { echo "   MISSING data/$f"; missing=1; }
done
[ "$missing" = 0 ] || { echo ">> pipeline incomplete"; exit 1; }

# Godot's JSON parser rejects NaN and Infinity, and refuses the whole file when it sees one,
# which shows up as an empty scene rather than an error anyone would connect to the data.
"$PY" - <<'PY' || { echo ">> pipeline produced JSON the viewer cannot parse"; exit 1; }
import json, sys
def reject(c):
    raise ValueError(f"{c} is not valid JSON")
bad = 0
for name in ["neurons.json", "rois.json", "sim.json", "fly.json", "space.json"]:
    try:
        json.load(open("data/" + name), parse_constant=reject)
    except Exception as e:
        print(f"   INVALID data/{name}: {e}")
        bad = 1
sys.exit(bad)
PY

echo ">> done:"
du -sh data/meshes data/neurons.mm data/edges.bin data/sim.json
