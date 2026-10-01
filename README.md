# godot-fly — Male CNS connectome viewer for SBS 3D display walls

Renders the FlyEM / Janelia **male adult *Drosophila* CNS connectome** (male-cns v1.0,
brain + ventral nerve cord) in Godot 4.7 as an interactive, auto-rotating, side-by-side
stereo visualization.

Data: https://male-cns.janelia.org/download/ (CC-BY 4.0). Fly body: [flybody](https://github.com/TuragaLab/flybody)
(Apache-2.0) — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## What it shows

- ~5 100 proofread neuron skeletons, stratified across all 14 superclasses
  (descending/ascending, central-brain, optic-lobe, VNC intrinsic/sensory/motor …),
  ~2.9 M skeleton segments rendered as additive screen-space ribbons via one MultiMesh.
- Brain and VNC outline shells.
- 114 neuropil compartment meshes (toggle with `R`).

## Guided tour

**The app is the tour** — there is no free-flight mode. It is a narrated slide sequence
stepped with the **← / →** arrow keys. Each slide flies the camera to its framing; you can
rotate (drag, WASD) and zoom (wheel, Q/E) around it until the next slide takes over. It opens on the
fly itself — the whole animal hovering with its wings flapping — then dissolves the
body to reveal the nervous system inside it, flies into the head while the outer shell fades
to fully transparent, and visits
one region per slide — optic lobes, antennal lobe, mushroom body, lateral horn, central
complex, AMMC/wedge, gnathal ganglia, the neck connective and the ventral nerve cord —
lighting that region's neuropil meshes, framing them, and showing only the relevant neuron
superclasses. The narration (title, formal name, abbreviations, description) sits in a panel
down the right-hand edge, drawn in both eyes at zero parallax; the only other overlay is a
small key hint in the bottom-left corner (rotate, zoom, `T` 3D format, `F` fullscreen). The closing slide
carries the credits (dataset, licence, rendering and stereo attributions), and **→** from it
starts the tour over.

The opening fly is the **flybody** model (Vaxenburg et al. 2024, TuragaLab / Janelia,
Apache-2.0 — see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)): the connectome data is
nervous system only, so `tools/fetch_fly_body.py` (step 3 of `download_data.sh`) poses the
model's meshes, converts them to micrometres and places the head around the connectome's brain.
It is exported as flybody's own body tree (67 jointed segments, `data/fly.json`), so
[`scripts/fly.gd`](scripts/fly.gd) can animate it while it hovers: wings flap on their hinges,
legs tuck into the flight posture from FlyGym and drift slowly around it, antennae twitch, the abdomen pumps and the halteres beat. The body
is drawn solid (`shaders/fly.gdshader`) and dissolves on slide 2 to leave the nervous system.

Slides are plain data at the top of [`scripts/story.gd`](scripts/story.gd) — edit `SLIDES`
to re-order, re-word or add regions (`rois` takes neuropil names as in `data/rois.json`,
without the `(L)` / `(R)` suffix). `--story=5` starts at slide 5.
`godot --headless --path . -s tools/story_test.gd` walks every slide and checks each one
still resolves its neuropils; `tools/story_shots.gd` (needs a display, e.g.
`xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tools/story_shots.gd ++ --3d=mono`)
renders one PNG per slide to `user://` so the framing can be eyeballed.

While the tour is up the rendered image is lens-shifted left by 16 % of the frame
(`Story.VIEW_SHIFT`, a frustum offset, not a camera move) so the panel never sits on the
subject, and each slide's framing distance is computed from the region's bounding box and
the eye's own field of view.

## Ambient animation

Small, slow motion keeps the picture alive without competing with it — everything additive,
faint and off the subject's silhouette:

- **a slow wave** rolling from the brain down the nerve cord every 16 s;
- **grow-in** — the connectome grows out from the centre as the fly's body dissolves;
- **lit neuropils** on the tour breathe and carry faint contour lines creeping up their surface;
- **class cross-fades** when a slide shows or hides a superclass;
- **motes** — a sparse field of pixel-sized drifting points around the CNS, which give the
  stereo image depth cues in the empty space without ever growing into blobs up close;
- the tour's narration eases in per slide.

The wave is only shown while the simulation is off, so it never reads as activity. All of
it scales with one shader global, `anim_level`; `--no-anim` turns it off.

## Simulated activity

Throughout the tour, random targets — any neuropil (antennal lobe, mushroom body calyx,
fan-shaped body, medulla, leg neuropils, …) or a whole neuron class — receive a pulse every
8–12 s, once the previous wave has died down. Activity propagates over the real synaptic
graph: each rendered neuron's downstream partners (connectome weights ≥ 2 synapses) receive
input scaled by synapse count and signed by the presynaptic neuron's predicted transmitter
(ACh excitatory; GABA, glutamate, histamine inhibitory; monoamines weakly modulatory).
Neurons are leaky integrate-and-fire with refractoriness and spike-frequency adaptation, so
a pulse produces a wave that spreads through the brain, down the neck connective and into the
VNC, then dies out. At most 1.2 % of neurons fire per step (`Sim.MAX_FIRE_FRAC`), so a
burst never washes out the anatomy the slide is about.

The model runs on the *rendered* subgraph (~5k neurons, ~51k edges), so it's a qualitative
picture of "what talks to what", not a biophysical simulation. Sampling more neurons
(`fetch_data.py --neurons 2`) gives a denser graph. Tunables live at the top of `scripts/sim.gd`;
`godot --headless --path . -s tools/sim_test.gd` prints spike counts per tick for tuning.

## Setup

1. Fetch and convert the data (~1.9 GB download, cached in `data/raw/`; produces ~230 MB in `data/`):

   ```sh
   ./download_data.sh                               # runs the pipeline in Docker
   ./download_data.sh --neurons 2 --skel-eps 0.5    # denser sample (more GPU memory)
   ./download_data.sh --local                       # use the host's python instead
   ```

   This builds the image from the [`Dockerfile`](Dockerfile) and runs
   `tools/pipeline.sh` inside it with `data/` bind-mounted, so the only requirement on
   the host is Docker. The three steps are `tools/fetch_data.py` (neuropil meshes +
   neuron skeletons), `tools/build_sim.py` (synaptic graph + neuropil membership for
   the simulation) and `tools/fetch_fly_body.py` (the flybody model). At the end it
   verifies every file the viewer loads, so a partial download fails loudly instead of
   producing a build with an empty scene.

   **Why Docker:** the pipeline needs `fast-simplification`, `cloud-volume`, `pyarrow`
   and `scipy`, which only publish wheels for released Python versions. On a host whose
   interpreter is newer than those wheels — or externally managed (PEP 668) without
   `venv`/`ensurepip` — the dependency install cannot succeed and the pipeline silently
   produces nothing. Pinning the interpreter in the image makes it reproducible. Use
   `--local` if you already have a working environment.

   Raw downloads are cached in `data/raw/`, so interrupting and re-running is cheap and
   only the missing pieces are fetched.

2. Run:

   ```sh
   godot --path . ++ --3d=half                        # squeezed side-by-side (single-input 3D TV / wall)
   godot --path . ++ --3d=full                        # window two frames wide, full-res per eye
   godot --path . ++ --3d=mono                        # plain 3D
   godot --path . ++ --3d=half --windowed             # don't start fullscreen

   All formats: `half` `full` `mono`. The window starts fullscreen (`--windowed` to
   opt out; `--fullscreen` is still accepted).
   If a wall's menu says "single 3D" it takes one input carrying both eyes — pick the packing
   named in that menu. `--swap` swaps eyes if the depth looks inside-out.
   ```

   Other flags: `--swap` `--ipd=0.033` `--conv=1.0` `--fov=70` `--width=1.2`
   `--brightness=0.02` `--story=5` (start at slide 5) `--no-anim` (ambient animation off)
   `--screenshot=path` (save a frame after 2 s and quit).

## Controls

| key | action |
|---|---|
| ← → | previous / next slide (→ on the last slide starts over) |
| drag / WASD | rotate (stops the slide's auto-rotation until the next slide) |
| wheel / Q E | zoom |
| T | cycle 3D format (SBS half → SBS full → mono); remembered for the next start |
| F / F11 | fullscreen |
| Esc | quit |

## Configuration

`T` saves the chosen 3D format to `user://flyviz.cfg`, and it is applied on the next start;
nothing else is stored. On Windows the config lives in `%APPDATA%\Godot\app_userdata\godot-fly\flyviz.cfg`, on
Linux in `~/.local/share/godot/app_userdata/godot-fly/`. Project settings follow satwatch2's
deployment (`rendering_device/driver.windows="d3d12"`), and the Windows export preset
uses BPTC textures.

`--screenshot=path` saves the full output frame after 2 s and quits.

`display/window/stretch/mode` must stay `disabled` (it is) — any stretch mode rescales the
eye compositing against the base resolution.

## Building a standalone executable

```sh
./export.sh            # build/godot-fly.exe + godot-fly.pck, build/godot-fly.x86_64 (self-contained)
./export.sh windows    # one platform
```

Installs the matching export templates on first run. The Linux binary embeds the resource
pack (scenes, shaders, data). The Windows build does **not** — an exe with the pack appended
doesn't start — so copy `godot-fly.exe` and `godot-fly.pck` together, from the same export,
into the same folder (a missing or mismatched `.pck` is the "Couldn't load project data"
error at startup). No Godot or Python needed on the target machine.

If you add an export preset of your own, keep the
`include_filter` for `data/*.bmesh, data/*.mm, data/*.bin, data/*.json`: those are plain
files rather than Godot resources, so without the filter the build runs on the dev machine
and shows an empty scene everywhere else.

## How the stereo works

`scripts/stereo_rig.gd` renders the shared `World3D` into two `SubViewport`s with
off-axis (asymmetric-frustum) cameras (`Camera3D.PROJECTION_FRUSTUM` + `frustum_offset`),
converged on the orbit target, and packs them with `shaders/stereo_composite.gdshader`
into the display's format. In the squeezed formats each eye is rendered at full window
resolution, so the wall's un-squeeze restores the correct aspect. UI is drawn into each
eye at zero parallax.

Scene units are micrometres; the EM Y axis is flipped and the CNS is centred at the origin.

## Layout

```
tools/fetch_data.py    download + decimate meshes, RDP-simplify skeletons, write binaries
data/                  generated (git-ignored): meshes/*.bmesh, neurons.mm, *.json
Dockerfile             pinned python environment for the data pipeline
tools/pipeline.sh      the three pipeline steps, plus a completeness check
tools/build_sim.py     neuropil membership (2 µm ROI volume), NT signs, synaptic edges
scripts/sim.gd         leaky integrate-and-fire spreading activation, activity texture
scripts/neurons.gd     MultiMesh loader (one instance per segment)
shaders/neuron_ribbon.gdshader   screen-space ribbon expansion, per-class colour/visibility
scripts/stereo_rig.gd  stereo cameras + output packing (SBS half / full / mono)
shaders/stereo_composite.gdshader   packs the two eye renders into the display's format
scripts/story.gd       guided slide tour: slide data, region framing, shell / neuropil fades
tools/fetch_fly_body.py  flybody body model -> data/meshes/fly/*.bmesh + data/fly.json (rig)
scripts/fly.gd         rigged whole fly for the opening slide (hover, wings, legs, antennae)
scripts/orbit.gd       orbit camera (animated pivot, so the tour can fly into a region; drag / wheel)
scripts/main.gd        glue, keys, narration panel and key hint, 3D-format config
```
