#!/usr/bin/env python3
"""
Fetch the flybody Drosophila body model and convert it into meshes for the tour's opening fly.

Source: flybody (Vaxenburg et al. 2024, "Whole-body physical simulation of fruit fly locomotion"),
https://github.com/TuragaLab/flybody — Apache License 2.0. The model's meshes were built from
imaging of a real female Drosophila melanogaster. See THIRD_PARTY_NOTICES.md.

The MJCF body tree (fruitfly.xml) is walked in its default pose, every visual geom's mesh is
placed in world space, and the result is fitted to the connectome: flybody is in centimetres,
x anterior / y left / z up; the viewer is in micrometres, -Z anterior / +Y dorsal. The body is
scaled so the brain fills most of the head and moved so the head capsule is centred on it.

Outputs (data/ == res://data):
  meshes/fly/<body>_<kind>.bmesh  one mesh per MJCF body (head, femur_T1_left, wing_left, …) and
                                  look (body / eyes / membrane / veins), in that body's own frame
  fly.json                        body tree: parent, rest transform in viewer space, meshes —
                                  every joint axis that bends a segment is its local X
"""
import json, os, struct, sys, urllib.request
import xml.etree.ElementTree as ET
import numpy as np



def write_mesh(path, v, f):
    """Same .bmesh layout as fetch_data.py (kept separate so this needs only numpy)."""
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])     # area-weighted
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    n = np.ascontiguousarray(n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12), np.float32)
    v = np.ascontiguousarray(v, np.float32); f = np.ascontiguousarray(f, np.uint32)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<I", len(v))); fh.write(v.tobytes()); fh.write(n.tobytes())
        fh.write(struct.pack("<I", len(f))); fh.write(f.tobytes())

BRAIN_IN_HEAD = 0.8     ## brain width / head width
COMMIT = "d015e9bfe441bd90ae431bac24c55cb74bdbce26"   # pinned: the fit below is tuned to it
BASE = f"https://raw.githubusercontent.com/TuragaLab/flybody/{COMMIT}"
ASSETS = f"{BASE}/flybody/fruitfly/assets"

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "data", "raw", "flybody")
OUT = os.path.join(HERE, "..", "data")

def fetch(url, path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with urllib.request.urlopen(url) as r, open(path + ".part", "wb") as fh:
            fh.write(r.read())
        os.replace(path + ".part", path)
    return path


def quat_mat(q):
    """MJCF quaternion (w x y z) -> 3x3 rotation."""
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def xform(el):
    m = np.eye(4)
    if el.get("quat"):
        m[:3, :3] = quat_mat(np.array(el.get("quat").split(), float))
    if el.get("pos"):
        m[:3, 3] = np.array(el.get("pos").split(), float)
    return m


def load_obj(path):
    """Vertices and (fan-triangulated) faces of a Wavefront OBJ."""
    vs, fs = [], []
    with open(path) as fh:
        for line in fh:
            if line.startswith("v "):
                vs.append(line.split()[1:4])
            elif line.startswith("f "):
                idx = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
                fs.extend([idx[0], idx[i], idx[i + 1]] for i in range(1, len(idx) - 1))
    return np.array(vs, float), np.array(fs, np.int64)


def main():
    xml_path = fetch(f"{ASSETS}/fruitfly.xml", os.path.join(RAW, "fruitfly.xml"))
    fetch(f"{BASE}/LICENSE", os.path.join(RAW, "LICENSE"))
    root = ET.parse(xml_path).getroot()
    mesh_scale = np.array(root.find("default/mesh").get("scale").split(), float)
    files = {m.get("name"): m.get("file") for m in root.iter("mesh") if m.get("file")}

    # walk the body tree: every body's world transform (cm) and its visual meshes in its own
    # frame, split by look (cuticle / eyes / wing membrane / wing veins)
    bodies = []          # [{name, parent, world 4x4, parts: {kind: [(v_local_cm, f)]}}]

    def walk(body, parent_name, parent_w):
        for b in body.findall("body"):
            w = parent_w @ xform(b)
            name = b.get("name")
            parts = {}
            for g in b.findall("geom"):
                mesh = g.get("mesh")
                if not mesh:
                    continue                    # physics-only capsules / ellipsoids
                path = fetch(f"{ASSETS}/{files[mesh]}", os.path.join(RAW, "meshes", files[mesh]))
                v, f = load_obj(path)
                gl = xform(g)
                v = (v * mesh_scale) @ gl[:3, :3].T + gl[:3, 3]
                mat = g.get("material", "body")
                if name.startswith("wing_"):
                    kind = "membrane" if mat == "membrane" else "veins"
                else:
                    kind = "eyes" if mat == "red" else "body"
                parts.setdefault(kind, []).append((v, f))
            bodies.append({"name": name, "parent": parent_name, "world": w, "parts": parts})
            walk(b, name, w)

    walk(root.find("worldbody"), "", np.eye(4))

    # flybody (cm; x anterior, y left, z up) -> viewer axes (x_o = -y, y_o = z, z_o = -x), µm
    R = np.array([[0, -1, 0], [0, 0, 1], [-1, 0, 0]], float)

    # anchor: the head capsule's centre
    head = next(b for b in bodies if b["name"] == "head")
    hv = np.concatenate([v for v, _ in head["parts"]["body"]])
    hv = (hv @ head["world"][:3, :3].T + head["world"][:3, 3]) @ R.T * 1e4
    a_head = (hv.min(0) + hv.max(0)) / 2

    with open(os.path.join(OUT, "meshes", "brain_shell.bmesh"), "rb") as fh:
        nv = struct.unpack("<I", fh.read(4))[0]
        sv = np.frombuffer(fh.read(nv * 12), np.float32).reshape(-1, 3)
    c_brain, s_brain = (sv.min(0) + sv.max(0)) / 2, sv.max(0) - sv.min(0)

    # uniform scale so the brain (optic lobes included) spans ~80 % of the head's width, head
    # capsule centred on the brain; the body's own posture is kept as modelled
    head_w0 = (hv.max(0) - hv.min(0))[0]
    scale = s_brain[0] / (head_w0 * BRAIN_IN_HEAD)
    print(f"fit: scale {scale:.3f} (1 = true size), "
          f"brain width {s_brain[0]:.0f} µm vs head width {head_w0 * scale:.0f} µm")

    def fit(p):
        return (np.asarray(p) @ R.T * 1e4 - a_head) * scale + c_brain

    # Each body becomes a node: rotation R·W, origin fit(W·0); its meshes are in its own frame,
    # scaled to µm. Animating a node about its local X turns it about its MJCF joint axis.
    out_dir = os.path.join(OUT, "meshes", "fly")
    os.makedirs(out_dir, exist_ok=True)
    meta = {"source": "flybody (TuragaLab/flybody, Apache-2.0)", "commit": COMMIT,
            "scale": float(scale), "bodies": []}
    total = 0
    for b in bodies:
        rot = R @ b["world"][:3, :3]
        node = {"name": b["name"], "parent": b["parent"],
                "basis": rot.T.tolist(),        # rows = Godot Basis columns x, y, z
                "origin": fit(b["world"][:3, 3]).tolist(), "meshes": []}
        for kind, items in sorted(b["parts"].items()):
            vs, fs, off = [], [], 0
            for v, f in items:
                vs.append(v); fs.append(f + off); off += len(v)
            v, f = np.concatenate(vs) * 1e4 * scale, np.concatenate(fs)
            fn = f"{b['name']}_{kind}.bmesh"
            write_mesh(os.path.join(out_dir, fn), v, f)
            node["meshes"].append({"file": f"fly/{fn}", "kind": kind})
            total += len(f)
        meta["bodies"].append(node)
    with open(os.path.join(OUT, "fly.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    print(f"  {len(bodies)} bodies, {total} triangles -> data/meshes/fly/, data/fly.json")


if __name__ == "__main__":
    main()
