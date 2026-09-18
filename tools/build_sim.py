#!/usr/bin/env python3
"""
Build the activity-simulation data for the neurons chosen by fetch_data.py.

  data/sim.json   regions (neuropils), per-neuron region membership, neurotransmitter sign
  data/edges.bin  uint32 n | int32 pre[n] | int32 post[n] | float32 weight[n]   (neuron indices)

Region membership is geometric: every raw SWC node is looked up in the 2 µm neuropil ROI
segmentation (brain fullbrain-roi-v4 + VNC neuropil-roi-v0). Edges come from the flat
connectome weights (synapse counts), restricted to the rendered neurons.
"""
import argparse, json, os, struct, sys
import numpy as np, pyarrow as pa, pyarrow.ipc as ipc, pyarrow.compute as pc
from cloudvolume import CloudVolume

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")
RAW = os.path.join(DATA, "raw")
BUCKET = "https://storage.googleapis.com/flyem-male-cns"
ROI_SETS = [("brain", "rois/fullbrain-roi-v4"), ("vnc", "rois/malecns-vnc-neuropil-roi-v0")]

# Sign / strength of a presynaptic neuron's effect by predicted transmitter.
# Glutamate and histamine are predominantly inhibitory in the fly CNS (GluCl / HisCl).
NT_SIGN = {"acetylcholine": 1.0, "gaba": -1.0, "glutamate": -0.7, "histamine": -1.0,
           "dopamine": 0.4, "serotonin": 0.4, "octopamine": 0.4, "unclear": 0.6}


def load_swc_nodes_nm(body):
    p = os.path.join(RAW, "swc", f"{body}.swc")
    pts = []
    for line in open(p):
        if line and line[0] != "#":
            q = line.split()
            pts.append((float(q[2]), float(q[3]), float(q[4])))
    return np.asarray(pts) * 8.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-weight", type=int, default=2, help="min synapse count for an edge")
    ap.add_argument("--min-nodes", type=int, default=8, help="min skeleton nodes inside a region to count as innervating it")
    a = ap.parse_args()

    meta = json.load(open(os.path.join(DATA, "neurons.json")))
    index = meta["index"]
    bodies = [n["bodyId"] for n in index]
    body_to_idx = {b: i for i, b in enumerate(bodies)}
    print(f"{len(bodies)} neurons", flush=True)

    # ---- regions: load 2 µm label volumes ----
    regions = []          # global region id -> {name, set}
    vols = []
    for tag, path in ROI_SETS:
        cv = CloudVolume(f"precomputed://{BUCKET}/{path}", mip=3, use_https=True, progress=False, fill_missing=True)
        arr = np.asarray(cv[:, :, :]).squeeze().astype(np.int64)
        res = np.array(cv.scale["resolution"], float)
        import requests
        sp = requests.get(f"{BUCKET}/{path}/segment_properties/info").json()["inline"]
        names = dict(zip(map(int, sp["ids"]), sp["properties"][0]["values"]))
        offset = len(regions)
        local_to_global = {}
        for lid, nm in sorted(names.items()):
            local_to_global[lid] = len(regions)
            regions.append({"id": len(regions), "name": nm, "set": tag})
        vols.append((arr, res, local_to_global))
        print(f"  {tag}: {arr.shape} voxels @ {res[0]:.0f} nm, {len(names)} regions", flush=True)

    # ---- membership ----
    membership = []       # per neuron: [[region, node_count], ...]
    for i, b in enumerate(bodies):
        pts = load_swc_nodes_nm(b)
        counts = {}
        for arr, res, l2g in vols:
            ijk = np.floor(pts / res).astype(np.int64)
            ok = np.all((ijk >= 0) & (ijk < np.array(arr.shape)), axis=1)
            lab = arr[ijk[ok, 0], ijk[ok, 1], ijk[ok, 2]]
            u, c = np.unique(lab[lab > 0], return_counts=True)
            for l, n in zip(u, c):
                if int(l) in l2g and n >= a.min_nodes:
                    counts[l2g[int(l)]] = int(n)
        membership.append(sorted(counts.items(), key=lambda kv: -kv[1]))
        if i % 1000 == 0:
            print(f"  membership {i}/{len(bodies)}", flush=True)

    # ---- neurotransmitters ----
    nt = ipc.open_file(pa.memory_map(os.path.join(RAW, "body-nt.feather"))).read_all()
    nt = nt.filter(pc.is_in(nt["body"], value_set=pa.array(bodies, pa.int64()))).to_pandas()
    nt_by_body = {}
    for r in nt.itertuples():
        lab = r.consensus_nt if isinstance(r.consensus_nt, str) and r.consensus_nt != "unclear" else r.predicted_nt
        nt_by_body[int(r.body)] = lab if isinstance(lab, str) else "unclear"
    nt_label = [nt_by_body.get(b, "unclear") for b in bodies]
    nt_sign = [NT_SIGN.get(l, 0.6) for l in nt_label]

    # ---- edges ----
    print("edges ...", flush=True)
    tab = ipc.open_file(pa.memory_map(os.path.join(RAW, "weights.feather"))).read_all()
    bset = pa.array(bodies, pa.int64())
    tab = tab.filter(pc.and_(pc.is_in(tab["body_pre"], value_set=bset), pc.is_in(tab["body_post"], value_set=bset)))
    pre = np.array([body_to_idx[b] for b in tab["body_pre"].to_pylist()], np.int32)
    post = np.array([body_to_idx[b] for b in tab["body_post"].to_pylist()], np.int32)
    w = tab["weight"].to_numpy().astype(np.float32)
    keep = (w >= a.min_weight) & (pre != post)
    pre, post, w = pre[keep], post[keep], w[keep]
    order = np.argsort(pre, kind="stable")
    pre, post, w = pre[order], post[order], w[order]
    with open(os.path.join(DATA, "edges.bin"), "wb") as fh:
        fh.write(struct.pack("<I", len(pre)))
        fh.write(pre.tobytes()); fh.write(post.tobytes()); fh.write(w.tobytes())
    out_deg = np.bincount(pre, minlength=len(bodies)); in_deg = np.bincount(post, minlength=len(bodies))
    print(f"  {len(pre)} edges (weight >= {a.min_weight}), mean out-degree {out_deg.mean():.1f}, "
          f"{(in_deg + out_deg == 0).sum()} isolated neurons")

    json.dump({"regions": regions, "membership": membership, "nt": nt_label, "nt_sign": nt_sign,
               "edges": int(len(pre))}, open(os.path.join(DATA, "sim.json"), "w"))
    rc = np.zeros(len(regions), int)
    for m in membership:
        for r, _ in m:
            rc[r] += 1
    top = sorted(zip(rc, [r["name"] for r in regions]), reverse=True)[:12]
    print("  most innervated regions:", top)


if __name__ == "__main__":
    main()
