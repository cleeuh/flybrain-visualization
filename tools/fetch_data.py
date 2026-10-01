#!/usr/bin/env python3
"""
Fetch Male CNS (FlyEM, Janelia) data and convert it into compact binaries for the Godot viewer.

Sources (CC-BY 4.0, https://male-cns.janelia.org/download/):
  - brain / VNC shell meshes            (neuroglancer legacy mesh, nm)
  - neuropil ROI meshes (fullbrain-roi-v4)
  - neuron skeletons                    (SWC, 8 nm units)
  - body annotations                    (feather)

Outputs (in data/ == res://data):
  meshes/<name>.bmesh  uint32 nv | float32 xyz*nv | float32 normal*nv | uint32 nt | uint32 idx*3*nt
  neurons.mm           Godot MultiMesh buffer, 16 float32 per segment:
                         [dx,0,0,ax, dy,1,0,ay, dz,0,1,az, group, side, neuron_idx, jitter]
                       i.e. transform origin = segment start A, basis column 0 = B-A.
  neurons.json         group table, bounds, neuron index (bodyId, type, group, side)

All coordinates are converted to micrometers, Y flipped (EM image space is Y-down),
and centered on the brain-shell centroid so Godot units == microns.
"""
import argparse, io, json, os, struct, sys, concurrent.futures as cf
import numpy as np, pandas as pd, requests, trimesh, fast_simplification

BUCKET = "https://storage.googleapis.com/flyem-male-cns"
ROI = f"{BUCKET}/rois"
SWC = f"{BUCKET}/v1.0/segmentation/skeletons-malecns/skeletons-swc"
ANNOT = f"{BUCKET}/v1.0/connectome-data/flat-connectome/body-annotations-male-cns-v1.0-minconf-0.5.feather"

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "data", "raw")
OUT = os.path.join(HERE, "..", "data")   # == res://data in the Godot project

# Per-superclass sample caps: chosen for a balanced, readable picture of the whole CNS.
SAMPLE = {
    "descending_neuron": 400, "ascending_neuron": 400, "sensory_ascending": 150,
    "cb_intrinsic": 900, "visual_projection": 500, "visual_centrifugal": 250,
    "ol_intrinsic": 700, "ol_sensory": 150, "cb_sensory": 200,
    "vnc_intrinsic": 700, "vnc_sensory": 250, "vnc_motor": 300,
    "cb_motor": 107, "vnc_efferent": 94,
}


def get(url, cache=None, binary=True):
    if cache:
        p = os.path.join(RAW, cache)
        if os.path.exists(p):
            return open(p, "rb").read()
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    if cache:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(r.content)
    return r.content


def parse_ngmesh(b):
    n = struct.unpack_from("<I", b, 0)[0]
    v = np.frombuffer(b, np.float32, n * 3, 4).reshape(-1, 3)
    f = np.frombuffer(b, np.uint32, -1, 4 + n * 12).reshape(-1, 3)
    return v.astype(np.float64), f.astype(np.int64)


class Space:
    """nm -> centered microns, Y flipped."""
    def __init__(self, center_nm):
        self.c = np.asarray(center_nm, np.float64)

    def __call__(self, xyz_nm):
        p = (np.asarray(xyz_nm, np.float64) - self.c) / 1000.0
        p[..., 1] *= -1
        return p.astype(np.float32)


def write_mesh(path, v, f):
    m = trimesh.Trimesh(v, f, process=False)
    n = np.ascontiguousarray(m.vertex_normals, np.float32)
    v = np.ascontiguousarray(v, np.float32); f = np.ascontiguousarray(f, np.uint32)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<I", len(v))); fh.write(v.tobytes()); fh.write(n.tobytes())
        fh.write(struct.pack("<I", len(f))); fh.write(f.tobytes())


def decimate(v, f, target_tris):
    if len(f) <= target_tris:
        return v, f
    m0 = trimesh.Trimesh(v, f, process=True)   # merge duplicate verts / drop degenerate faces first
    v, f = np.asarray(m0.vertices), np.asarray(m0.faces)
    for agg in (9, 7, 5):
        v2, f2 = v.astype(np.float32), f.astype(np.int32)
        for _ in range(6):  # the simplifier stops early on big meshes; iterate until we hit the target
            v2, f2 = fast_simplification.simplify(v2, f2, target_count=target_tris, agg=agg)
            if len(f2) <= target_tris * 1.05:
                break
        if len(f2) > 0:
            break
    else:
        v2, f2 = v, f
    m = trimesh.Trimesh(v2, f2, process=True)
    m.fix_normals()
    return np.asarray(m.vertices), np.asarray(m.faces)


def fetch_roi_mesh(dataset, seg_id):
    man = json.loads(get(f"{ROI}/{dataset}/mesh/{seg_id}:0"))
    parts = [parse_ngmesh(get(f"{ROI}/{dataset}/mesh/{frag}", cache=f"{dataset}/{frag}")) for frag in man["fragments"]]
    if len(parts) == 1:
        return parts[0]
    vs, fs, off = [], [], 0
    for v, f in parts:
        vs.append(v); fs.append(f + off); off += len(v)
    return np.vstack(vs), np.vstack(fs)


def roi_names(dataset):
    d = json.loads(get(f"{ROI}/{dataset}/segment_properties/info"))["inline"]
    return dict(zip(map(int, d["ids"]), d["properties"][0]["values"]))


def rdp_keep(pts, eps):
    """Ramer-Douglas-Peucker: boolean mask of points to keep on a polyline."""
    n = len(pts)
    keep = np.zeros(n, bool); keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        d = b - a; L2 = d @ d
        seg = pts[i + 1:j]
        if L2 == 0:
            dist = np.linalg.norm(seg - a, axis=1)
        else:
            t = np.clip(((seg - a) @ d) / L2, 0, 1)
            dist = np.linalg.norm(seg - (a + t[:, None] * d), axis=1)
        k = int(np.argmax(dist))
        if dist[k] > eps:
            k += i + 1; keep[k] = True
            stack.append((i, k)); stack.append((k, j))
    return keep


def simplify_swc(ids, xyz, par, eps_nm):
    """Split the tree into chains (root/branch/leaf delimited), RDP each, return segment endpoint pairs."""
    lut = {i: k for k, i in enumerate(ids)}
    n = len(ids)
    children = [[] for _ in range(n)]
    roots = []
    for k in range(n):
        p = lut.get(par[k], -1) if par[k] >= 0 else -1
        (children[p].append(k) if p >= 0 else roots.append(k))
    a_out, b_out = [], []
    stack = list(roots)
    while stack:
        start = stack.pop()
        for c in children[start]:
            chain = [start, c]
            while len(children[chain[-1]]) == 1:
                chain.append(children[chain[-1]][0])
            end = chain[-1]
            pts = xyz[chain]
            kept = pts[rdp_keep(pts, eps_nm)]
            a_out.append(kept[:-1]); b_out.append(kept[1:])
            if children[end]:
                stack.append(end)
    if not a_out:
        return None
    return np.vstack(a_out), np.vstack(b_out)


def parse_swc(text, eps_nm=0.0):
    ids, xyz, par = [], [], []
    for line in text.splitlines():
        if not line or line[0] == "#":
            continue
        p = line.split()
        ids.append(int(p[0])); xyz.append((float(p[2]), float(p[3]), float(p[4]))); par.append(int(p[6]))
    if not ids:
        return None
    ids = np.array(ids); xyz = np.array(xyz) * 8.0; par = np.array(par)   # 8 nm voxels -> nm
    if eps_nm > 0:
        return simplify_swc(ids, xyz, par, eps_nm)
    lut = {i: k for k, i in enumerate(ids)}
    m = par >= 0
    a = np.array([lut[i] for i in ids[m]]); b = np.array([lut.get(p, -1) for p in par[m]])
    ok = b >= 0
    return xyz[a[ok]], xyz[b[ok]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roi-tris", type=int, default=12000, help="target triangles per neuropil ROI")
    ap.add_argument("--shell-tris", type=int, default=120000)
    ap.add_argument("--neurons", type=float, default=1.0, help="scale factor on per-class sample caps")
    ap.add_argument("--workers", type=int, default=32)
    ap.add_argument("--skel-eps", type=float, default=0.5, help="skeleton simplification tolerance (microns)")
    ap.add_argument("--skip-meshes", action="store_true")
    ap.add_argument("--skip-neurons", action="store_true")
    a = ap.parse_args()
    os.makedirs(os.path.join(OUT, "meshes"), exist_ok=True)

    # ---- shells (also defines the coordinate frame) ----
    print("brain shell ...", flush=True)
    bv, bf = fetch_roi_mesh("brain-shell-v2.2", 1)
    print("vnc shell ...", flush=True)
    vv, vf = fetch_roi_mesh("vnc-shell-v2", 1)
    allv = np.vstack([bv, vv])
    center = (allv.min(0) + allv.max(0)) / 2
    space = Space(center)
    json.dump({"center_nm": center.tolist(), "extent_um": ((allv.max(0) - allv.min(0)) / 1000).tolist()},
              open(os.path.join(OUT, "space.json"), "w"), indent=1)

    if not a.skip_meshes:
        for name, (v, f) in {"brain_shell": (bv, bf), "vnc_shell": (vv, vf)}.items():
            v2, f2 = decimate(v, f, a.shell_tris)
            write_mesh(os.path.join(OUT, "meshes", f"{name}.bmesh"), space(v2), f2)
            print(f"  {name}: {len(f)} -> {len(f2)} tris")

        # ---- neuropil ROIs ----
        rois = []
        for ds in ["fullbrain-roi-v4", "malecns-vnc-neuropil-roi-v0"]:
            names = roi_names(ds)
            def one(item):
                sid, nm = item
                try:
                    v, f = fetch_roi_mesh(ds, sid)
                except Exception as e:
                    print(f"  skip {nm}: {e}"); return None
                v2, f2 = decimate(v, f, a.roi_tris)
                fn = f"roi_{ds.split('-')[0]}_{sid}.bmesh"
                write_mesh(os.path.join(OUT, "meshes", fn), space(v2), f2)
                return {"file": fn, "name": nm, "dataset": ds, "id": sid, "tris": int(len(f2))}
            with cf.ThreadPoolExecutor(8) as ex:
                for r in ex.map(one, sorted(names.items())):
                    if r: rois.append(r); print(f"  roi {r['name']}: {r['tris']} tris", flush=True)
        json.dump(rois, open(os.path.join(OUT, "rois.json"), "w"), indent=1)

    # ---- neurons ----
    if a.skip_neurons:
        return
    print("annotations ...", flush=True)
    df = pd.read_feather(io.BytesIO(get(ANNOT, cache="body-annotations.feather")))
    df = df[(df.status == "Traced") & df.superclass.notna()]
    rng = np.random.default_rng(7)
    picks = []
    for sc, cap in SAMPLE.items():
        sub = df[df.superclass == sc]
        n = min(len(sub), int(cap * a.neurons))
        # prefer typed neurons; balance L/R
        sub = sub.assign(_w=np.where(sub.type.notna(), 3.0, 1.0))
        idx = rng.choice(len(sub), n, replace=False, p=sub._w / sub._w.sum())
        picks.append(sub.iloc[idx])
    picks = pd.concat(picks)
    groups = sorted(picks.superclass.unique())
    gid = {g: i for i, g in enumerate(groups)}
    print(f"downloading {len(picks)} skeletons ...", flush=True)

    def fetch(row):
        try:
            t = get(f"{SWC}/{row.bodyId}.swc", cache=f"swc/{row.bodyId}.swc").decode()
        except Exception:
            return None
        seg = parse_swc(t, a.skel_eps * 1000.0)
        if seg is None or len(seg[0]) == 0:
            return None
        return row, space(seg[0]), space(seg[1])

    rows = list(picks.itertuples())
    out = os.path.join(OUT, "neurons.mm")
    counts = {g: 0 for g in groups}
    index = []
    n_seg = 0
    lo = np.full(3, np.inf, np.float32); hi = np.full(3, -np.inf, np.float32)
    with open(out, "wb") as fh, cf.ThreadPoolExecutor(a.workers) as ex:
        for i, res in enumerate(ex.map(fetch, rows)):
            if res is None:
                continue
            row, p0, p1 = res
            k = len(p0)
            side = {"L": 0, "R": 1, "M": 2}.get(row.somaSide, 3)
            nidx = len(index)
            buf = np.zeros((k, 16), np.float32)
            d = p1 - p0
            buf[:, 0] = d[:, 0]; buf[:, 3] = p0[:, 0]
            buf[:, 4] = d[:, 1]; buf[:, 5] = 1; buf[:, 7] = p0[:, 1]
            buf[:, 8] = d[:, 2]; buf[:, 10] = 1; buf[:, 11] = p0[:, 2]
            buf[:, 12] = gid[row.superclass]; buf[:, 13] = side; buf[:, 14] = nidx
            buf[:, 15] = rng.random()
            fh.write(buf.tobytes())
            lo = np.minimum(lo, np.minimum(p0.min(0), p1.min(0))); hi = np.maximum(hi, np.maximum(p0.max(0), p1.max(0)))
            # row.type is NaN for untyped neurons; JSON's NaN is not valid JSON and Godot
            # refuses the whole file, so write null instead.
            ntype = row.type if isinstance(row.type, str) else None
            index.append({"bodyId": int(row.bodyId), "type": ntype, "group": gid[row.superclass], "side": side, "segments": k})
            n_seg += k; counts[row.superclass] += 1
            if i % 500 == 0:
                print(f"  {i}/{len(rows)}  segments so far: {n_seg}", flush=True)
    json.dump({"groups": [{"id": gid[g], "name": g, "count": counts[g]} for g in groups],
               "neurons": len(index), "segments": n_seg,
               "aabb_min": lo.tolist(), "aabb_max": hi.tolist(),
               "index": index}, open(os.path.join(OUT, "neurons.json"), "w"), allow_nan=False)
    print(f"done: {len(index)} neurons, {n_seg} segments, {os.path.getsize(out)/1e6:.1f} MB")


if __name__ == "__main__":
    main()
