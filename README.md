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

## Guided tour (`V`, or `--story`)

**The app starts in the tour** (`--no-story` to boot straight into free flight, `V` to leave
or re-enter it). It is a narrated slide sequence stepped with the **← / →** arrow keys,
which navigate slides instead of orbiting while it is up. It opens on the
fly itself — a stylised whole animal hovering with its wings flapping — then dissolves the
body to reveal the nervous system inside it, flies into the head while the outer shell fades
to fully transparent, and visits
one region per slide — optic lobes, antennal lobe, mushroom body, lateral horn, central
complex, AMMC/wedge, gnathal ganglia, the neck connective and the ventral nerve cord —
lighting that region's neuropil meshes, framing them, and showing only the relevant neuron
superclasses. The narration (title, formal name, abbreviations, description) sits in a panel
down the right-hand edge, drawn in both eyes at zero parallax — nothing else is drawn over
the scene while the tour runs. The closing slide carries the credits (dataset, licence,
rendering and stereo attributions) and offers **R** to start over or **→ / V** to go into
explore mode. `R` restarts the tour from any slide.

The opening fly is [`scripts/fly.gd`](scripts/fly.gd): the connectome data is nervous system
only, so the body is built procedurally from scaled spheres and cylinders in the same shell
shader, laid out in the data's own coordinates so the brain sits inside the head and the
nerve cord inside the thorax — which is what makes the dissolve line up.

Slides are plain data at the top of [`scripts/story.gd`](scripts/story.gd) — edit `SLIDES`
to re-order, re-word or add regions (`rois` takes neuropil names as in `data/rois.json`,
without the `(L)` / `(R)` suffix). `--story` starts in the tour, `--story=5` at slide 5.
`godot --headless --path . -s tools/story_test.gd` walks every slide and checks each one
still resolves its neuropils; `tools/story_shots.gd` (needs a display, e.g.
`xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tools/story_shots.gd ++ --3d=mono`)
renders one PNG per slide to `user://` so the framing can be eyeballed.

While the tour is up the rendered image is lens-shifted left by 16 % of the frame
(`Story.VIEW_SHIFT`, a frustum offset, not a camera move) so the panel never sits on the
subject, and each slide's framing distance is computed from the region's bounding box and
the eye's own field of view. Powerwall mode keeps its physical off-axis frustums, so there
the panel simply overlays the right of the wall.

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
   godot --path . ++ --3d=half                        # squeezed side-by-side (single-input 3D TV / wall)
   godot --path . ++ --3d=full                        # window two frames wide, full-res per eye
   godot --path . ++ --3d=mono                        # plain 3D
   godot --path . ++ --3d=half --windowed             # don't start fullscreen
   godot --path . ++ --3d=wall                        # powerwall, geometry from the config

   All formats: `half` `full` `wall` `mono`; the wall's physical geometry comes from the
   config file (see below), not from flags. The window starts fullscreen (`--windowed` to
   opt out; `--fullscreen` is still accepted).
   If a wall's menu says "single 3D" it takes one input carrying both eyes — pick the packing
   named in that menu. `X` swaps eyes if the depth looks inside-out.
   ```

   Other flags: `--swap` `--ipd=0.033` `--conv=1.0` `--fov=70` `--width=1.2`
   `--brightness=0.02` `--rois` `--no-shells` `--no-rotate` `--help=0`
   `--demo` (auto-stimulate random regions) `--stim="AL(R)"` (pulse a region at start)
   `--no-story` (skip the guided tour at startup) / `--story=5` (start it at slide 5).
   Press `C` to save the current settings to `user://flyviz.cfg` (loaded on start).

## Controls

| key | action |
|---|---|
| V | guided tour of the brain (on by default) — leave / re-enter |
| ← → | previous / next slide (during the tour) |
| R | restart the tour (neuropil ROIs outside it) |
| Tab / ⇧Tab | choose stimulation target (neuropil or class) |
| Enter | pulse the target |
| L / G / P / K | tonic drive / auto demo / pause / stop simulation |
| drag / arrows / WASD | orbit (arrows step slides during the tour) |
| wheel / Q E | zoom |
| space | auto-rotate |
| 1-9 0, ⇧1-4 | toggle neuron class; `` ` `` all |
| B | brain + VNC shells |
| T | cycle 3D format (SBS half → SBS full → wall → mono) |
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

## Powerwall mode

For walls driven as two full-resolution eye images side by side — the setup of
[`addons/stereo_wall_display`](addons/stereo_wall_display) (UH LAVA lab, MIT), whose
off-axis projection and wall geometry this mode reuses. It opens a borderless window at
(0,0) of `2 × eye width` by `eye height` and derives each eye's frustum from the physical
wall size, viewer distance and eye separation, so depth is geometrically correct for a
viewer standing at the design position.

**Setting it up is configuration, not launch flags:** press `T` until the format reads
`wall`, press `C` to write `user://flyviz.cfg`, then edit the `[wall]` section and restart —
the wall window and frustums are applied on start. Defaults are the LAVA wall:

```ini
[wall]
width_m=6.047          ; wall size in metres
height_m=2.042
distance_m=2.282       ; viewer to wall
eye_separation_m=0.063
eye_width_px=4800      ; pixels per eye (the window is 9600x1620)
eye_height_px=1620
```

On Windows the config lives in `%APPDATA%\Godot\app_userdata\godot-fly\flyviz.cfg`, on
Linux in `~/.local/share/godot/app_userdata/godot-fly/`. Project settings follow satwatch2's
wall deployment (`rendering_device/driver.windows="d3d12"`), and the Windows export preset
uses BPTC textures.

The orbit target (the CNS centre) always sits on the wall plane, so zooming (`Q`/`E`,
wheel) rescales the fly rather than moving through it; the legend shows the current scale
(`1 mm on the wall = … µm`). Press `C` again to save any changes back to the config file.
`F12` saves a screenshot of the full output frame; `--screenshot=path` does so after 2 s and quits.

`display/window/stretch/mode` must stay `disabled` (it is) — any stretch mode rescales the
eye compositing against the base resolution.

## Building a standalone executable

```sh
./export.sh            # build/godot-fly.exe + build/godot-fly.x86_64, both self-contained
./export.sh windows    # one platform
```

Installs the matching export templates on first run. Both binaries embed the resource pack
(scenes, shaders, data), so each is a single file to copy — there is no `.pck` to ship
alongside, and nothing to keep named in sync. No Godot or Python needed on the target
machine.

If you add an export preset of your own, keep **Embed Pck** on and keep the
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
tools/build_sim.py     neuropil membership (2 µm ROI volume), NT signs, synaptic edges
scripts/sim.gd         leaky integrate-and-fire spreading activation, activity texture
scripts/neurons.gd     MultiMesh loader (one instance per segment)
shaders/neuron_ribbon.gdshader   screen-space ribbon expansion, per-class colour/visibility
scripts/stereo_rig.gd  stereo cameras + output packing (SBS half / full / wall)
shaders/stereo_composite.gdshader   packs the two eye renders into the display's format
addons/stereo_wall_display/         vendored UH LAVA powerwall addon (MIT); wall mode uses its projection
scripts/story.gd       guided slide tour: slide data, region framing, shell / neuropil fades
scripts/fly.gd         procedural stylised fly for the opening slide (hover + wing flap)
scripts/orbit.gd       orbit camera (animated pivot, so the tour can fly into a region)
scripts/main.gd        glue, input, legend, config
```
