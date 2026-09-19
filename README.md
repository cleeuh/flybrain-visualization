# godot-fly — Male CNS connectome viewer for SBS 3D display walls

Renders the FlyEM / Janelia **male adult *Drosophila* CNS connectome** (male-cns v1.0,
brain + ventral nerve cord) in Godot 4.7 as an interactive, auto-rotating, side-by-side
stereo visualization.

Data: https://male-cns.janelia.org/download/ (CC-BY 4.0).

## What it shows

- ~5 100 proofread neuron skeletons, stratified across all 14 superclasses
  (descending/ascending, central-brain, optic-lobe, VNC intrinsic/sensory/motor …),
  ~2.9 M skeleton segments rendered as additive screen-space ribbons via one MultiMesh.
- Brain and VNC outline shells.
- 114 neuropil compartment meshes (toggle with `R`).

## Stimulating the brain

Press **Tab / ⇧Tab** to pick a target — any neuropil (antennal lobe, mushroom body calyx,
fan-shaped body, medulla, leg neuropils, …) or a whole neuron class — then **Enter** to
inject a pulse. Activity propagates over the real synaptic graph: each rendered neuron's
downstream partners (connectome weights ≥ 2 synapses) receive input scaled by synapse count
and signed by the presynaptic neuron's predicted transmitter (ACh excitatory; GABA,
glutamate, histamine inhibitory; monoamines weakly modulatory). Neurons are leaky
integrate-and-fire with refractoriness and spike-frequency adaptation, so a pulse produces a
wave that spreads through the brain, down the neck connective and into the VNC, then dies
out over a second or two. **L** applies tonic drive instead of a pulse, **G** runs an
unattended demo that stimulates random regions, **K** stops the simulation.

The model runs on the *rendered* subgraph (~5k neurons, ~51k edges), so it's a qualitative
picture of "what talks to what", not a biophysical simulation. Sampling more neurons
(`fetch_data.py --neurons 2`) gives a denser graph. Tunables live at the top of `scripts/sim.gd`;
`godot --headless --path . -s tools/sim_test.gd` prints spike counts per tick for tuning.

## Setup

1. Fetch and convert the data (~1.8 GB download, cached in `data/raw/`; produces ~230 MB in `data/`):

   ```sh
   ./download_data.sh                          # installs python deps, runs both steps below
   ./download_data.sh --neurons 2 --skel-eps 0.5    # denser sample (more GPU memory)
   ```

   This runs `tools/fetch_data.py` (meshes + skeletons) and `tools/build_sim.py`
   (synaptic graph + neuropil membership for the simulation).

2. Run:

   ```sh
   godot --path . ++ --3d=half --fullscreen           # squeezed side-by-side (single-input 3D TV / wall)
   godot --path . ++ --3d=tb --fullscreen             # squeezed top-and-bottom
   godot --path . ++ --3d=rows --fullscreen           # line-interleaved (passive / polarised walls)
   godot --path . ++ --3d=full                        # window two frames wide, full-res per eye
   godot --path . ++ --3d=mono                        # plain 3D

   godot --path . ++ --wall --demo                    # UH LAVA powerwall (see below)
   godot --path . -- --stereo 4800 1620 --demo        # same, satwatch2-style flags

   All formats: `half` `full` `tb` `rows` `columns` `checkerboard` `sequential` `wall` `mono`.
   Interleaved / checkerboard need the window pixel-exact at the wall's native resolution
   (`--fullscreen`); `sequential` needs vsync at twice the eye rate (active shutter).
   If a wall's menu says "single 3D" it takes one input carrying both eyes — pick the packing
   named in that menu. `X` swaps eyes if the depth looks inside-out.
   ```

   Other flags: `--swap` `--ipd=0.033` `--conv=1.0` `--fov=70` `--width=1.2`
   `--brightness=0.02` `--rois` `--no-shells` `--no-rotate` `--help=0`
   `--demo` (auto-stimulate random regions) `--stim="AL(R)"` (pulse a region at start).
   Press `C` to save the current settings to `user://flyviz.cfg` (loaded on start).

## Controls

| key | action |
|---|---|
| Tab / ⇧Tab | choose stimulation target (neuropil or class) |
| Enter | pulse the target |
| L / G / P / K | tonic drive / auto demo / pause / stop simulation |
| drag / arrows / WASD | orbit |
| wheel / Q E | zoom |
| space | auto-rotate |
| 1-9 0, ⇧1-4 | toggle neuron class; `` ` `` all |
| B / R | brain+VNC shells / neuropil ROIs |
| T | cycle 3D format (SBS half → SBS full → top-bottom → rows → columns → checkerboard → sequential → wall → mono) |
| F12 | screenshot to `user://` |
| X | swap eyes |
| [ ] | eye separation |
| - = | convergence (zero-parallax) plane |
| , . | ribbon width |
| ; ' | brightness |
| N / ⇧N, M | step through / clear single-neuron highlight |
| F / F11 | fullscreen |
| H | hide help |
| C | save config |
| Esc | quit |

## Powerwall mode (`--wall`)

For walls driven as two full-resolution eye images side by side — the setup of
[`addons/stereo_wall_display`](addons/stereo_wall_display) (UH LAVA lab, MIT), whose
off-axis projection and wall geometry this mode reuses. It opens a borderless window at
(0,0) of `2 × eye width` by `eye height` and derives each eye's frustum from the physical
wall size, viewer distance and eye separation, so depth is geometrically correct for a
viewer standing at the design position. Defaults are the LAVA wall:

| flag | default | meaning |
|---|---|---|
| `--wall-size=WxH` | `6.047x2.042` | wall size in metres |
| `--wall-distance=D` | `2.282` | viewer to wall, metres |
| `--wall-eye=E` | `0.063` | eye separation, metres |
| `--wall-res=WxH` | `4800x1620` | pixels per eye (window is 9600×1620) |

Project settings follow satwatch2's wall deployment: `rendering_device/driver.windows="d3d12"`,
and the **Wall (Windows)** export preset embeds the PCK into a single `.exe` with BPTC textures.
`-- --stereo [W H]` and `--swap-eyes` are accepted for parity with that project.

The orbit target (the CNS centre) always sits on the wall plane, so zooming (`Q`/`E`,
wheel) rescales the fly rather than moving through it; the legend shows the current scale
(`1 mm on the wall = … µm`). Press `C` to save the wall settings to the config file.
`F12` saves a screenshot of the full output frame; `--screenshot=path` does so after 2 s and quits.

`display/window/stretch/mode` must stay `disabled` (it is) — any stretch mode rescales the
eye compositing against the base resolution.

## Building a standalone executable

```sh
./export.sh            # build/godot-fly.exe (self-contained) + build/godot-fly.x86_64 + godot-fly.pck
./export.sh windows    # one platform
```

Installs the matching export templates on first run. The Windows exe has the resource
pack (scenes, shaders, data) embedded; the Linux binary needs `godot-fly.pck` next to it.
No Godot or Python needed on the target machine.

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
tools/build_sim.py     neuropil membership (2 µm ROI volume), NT signs, synaptic edges
scripts/sim.gd         leaky integrate-and-fire spreading activation, activity texture
scripts/neurons.gd     MultiMesh loader (one instance per segment)
shaders/neuron_ribbon.gdshader   screen-space ribbon expansion, per-class colour/visibility
scripts/stereo_rig.gd  stereo cameras + output packing (SBS/TB/interleaved/wall)
shaders/stereo_composite.gdshader   packs the two eye renders into the display's format
addons/stereo_wall_display/         vendored UH LAVA powerwall addon (MIT); wall mode uses its projection
scripts/orbit.gd       orbit camera
scripts/main.gd        glue, input, legend, config
```
