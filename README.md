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

1. Fetch and convert the data (~600 MB download, cached in `data/raw/`; produces ~230 MB in `data/`):

   ```sh
   pip install -r tools/requirements.txt
   python3 tools/fetch_data.py                 # defaults: 5.1k neurons, 0.8 µm skeleton tolerance
   python3 tools/fetch_data.py --neurons 2 --skel-eps 0.5    # denser (more GPU memory)
   python3 tools/build_sim.py                  # synaptic graph + neuropil membership for the simulation
   ```

   `build_sim.py` additionally downloads the 1.1 GB connectome-weights table and the
   neurotransmitter table (cached in `data/raw/`).

2. Run:

   ```sh
   godot --path . ++ --sbs=half --fullscreen          # squeezed half-SBS (3D TV / most walls)
   godot --path . ++ --sbs=full                        # window two frames wide, full-res per eye
   godot --path . ++ --sbs=mono                        # plain 3D
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
| T | stereo mode (half SBS → full SBS → mono) |
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

## How the stereo works

`scripts/stereo_rig.gd` renders the shared `World3D` into two `SubViewport`s with
off-axis (asymmetric-frustum) cameras (`Camera3D.PROJECTION_FRUSTUM` + `frustum_offset`),
converged on the orbit target, and composites them side by side. In *half* mode each eye
is rendered at full window resolution and squeezed into its half, so the wall's SBS
un-squeeze restores the correct aspect. UI is drawn into each eye at zero parallax.

Scene units are micrometres; the EM Y axis is flipped and the CNS is centred at the origin.

## Layout

```
tools/fetch_data.py    download + decimate meshes, RDP-simplify skeletons, write binaries
data/                  generated (git-ignored): meshes/*.bmesh, neurons.mm, *.json
tools/build_sim.py     neuropil membership (2 µm ROI volume), NT signs, synaptic edges
scripts/sim.gd         leaky integrate-and-fire spreading activation, activity texture
scripts/neurons.gd     MultiMesh loader (one instance per segment)
shaders/neuron_ribbon.gdshader   screen-space ribbon expansion, per-class colour/visibility
scripts/stereo_rig.gd  SBS stereo compositor
scripts/orbit.gd       orbit camera
scripts/main.gd        glue, input, legend, config
```
