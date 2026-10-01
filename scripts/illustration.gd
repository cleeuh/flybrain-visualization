class_name Illustration
extends Control
## Animated schematic for a tour slide, drawn under the narration in each eye's panel.
##
## These are teaching cartoons, not data, so they are kept visibly apart from the connectome:
## flat 2D line drawings in the panel's grey / yellow, inside a dashed frame labelled
## "ILLUSTRATION · SCHEMATIC, NOT DATA". Both eyes draw from the same clock, so the figure sits
## at zero parallax like the rest of the panel. `kind` picks the figure (a slide's "illus").

const W := 560.0
const H := 250.0
const LABEL_H := 22.0
const CAPTION_H := 30.0

const LINE := Color(0.82, 0.82, 0.82)
const DIM := Color(0.45, 0.45, 0.45)
const FAINT := Color(0.25, 0.25, 0.25)
const HI := Color(1.0, 0.85, 0.29)
const BAD := Color(1.0, 0.42, 0.32)

const CAPTIONS := {
	"vision": "Each facet samples one point; a moving object sweeps across the mosaic.",
	"smell": "Odour molecules reach the antenna and light a pattern of glomeruli.",
	"memory": "Each odour lights a sparse set of Kenyon cells; dopamine tags one as good.",
	"instinct": "Hard-wired valence: food odour draws the fly in, a wasp sends it away.",
	"compass": "A single bump of activity in the ring tracks the fly's heading.",
	"hearing": "Courtship song vibrates the arista; Johnston's organ turns it into spikes.",
	"taste": "Sugar under a foot triggers the proboscis to extend.",
	"descend": "Commands run down the neck; feedback from the legs runs back up.",
	"gait": "Tripod gait: three legs on the ground at a time, alternating.",
}

var kind := "":
	set(v):
		kind = v
		visible = v != ""
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if kind == "":
		return
	var font := UITheme.mono()
	var r := Rect2(Vector2.ZERO, size)
	for e in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		draw_dashed_line(e[0], e[1], DIM, 1.0, 6.0)
	draw_string(font, Vector2(10, 16), "ILLUSTRATION · SCHEMATIC, NOT DATA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	draw_string(font, Vector2(10, size.y - 10), CAPTIONS.get(kind, ""), HORIZONTAL_ALIGNMENT_LEFT,
		size.x - 20, 12, LINE)
	var area := Rect2(10, LABEL_H + 4, size.x - 20, size.y - LABEL_H - CAPTION_H - 8)
	var t := Time.get_ticks_msec() / 1000.0
	match kind:
		"vision": _vision(area, t)
		"smell": _smell(area, t)
		"memory": _memory(area, t)
		"instinct": _instinct(area, t)
		"compass": _compass(area, t)
		"hearing": _hearing(area, t)
		"taste": _taste(area, t)
		"descend": _descend(area, t)
		"gait": _gait(area, t)


# --------------------------------------------------------------------------- helpers

func _hex(c: Vector2, rad: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 7:
		var a := deg_to_rad(60.0 * i + 30.0)
		p.append(c + Vector2(cos(a), sin(a)) * rad)
	return p


## A small top-down fly glyph pointing along `dir`.
func _fly_icon(c: Vector2, dir: float, s: float, col: Color) -> void:
	var fwd := Vector2.from_angle(dir)
	var side := fwd.orthogonal()
	draw_circle(c + fwd * s * 0.9, s * 0.45, col)                       # head
	draw_circle(c, s * 0.6, col)                                        # thorax
	draw_circle(c - fwd * s * 1.1, s * 0.55, col)                       # abdomen
	for k in [-1.0, 1.0]:
		var wing := PackedVector2Array([c, c + (side * k * 1.6 - fwd * 1.4) * s, c + (side * k * 0.6 - fwd * 1.9) * s])
		draw_colored_polygon(wing, Color(col, 0.35))


func _fruit(c: Vector2, rad: float, col: Color) -> void:
	draw_circle(c, rad, Color(col, 0.25))
	draw_arc(c, rad, 0, TAU, 32, col, 1.5)
	draw_line(c + Vector2(0, -rad), c + Vector2(3, -rad - 7), col, 1.5)


# --------------------------------------------------------------------------- figures

## Compound eye: a honeycomb of facets; a dark disc drifts across and the facets it covers
## report it (light up), one point per facet.
func _vision(a: Rect2, t: float) -> void:
	var rad := 11.0
	var dx := rad * sqrt(3.0)
	var cols := int(a.size.x * 0.62 / dx)
	var rows := int(a.size.y / (rad * 1.5)) - 1
	var origin := a.position + Vector2(rad + 4, rad + 4)
	var u := fmod(t / 6.0, 1.0)
	var obj := origin + Vector2(lerpf(-40.0, cols * dx + 40.0, u), a.size.y * 0.45 + sin(t * 1.3) * 18.0)
	for row in rows:
		for col in cols:
			var c := origin + Vector2(col * dx + (dx * 0.5 if row % 2 else 0.0), row * rad * 1.5)
			var hit := c.distance_to(obj) < 30.0
			draw_colored_polygon(_hex(c, rad - 1.5), Color(HI, 0.75) if hit else Color(FAINT, 0.6))
			draw_polyline(_hex(c, rad - 1.5), DIM if not hit else HI, 1.0)
	# the object in the world, to the right, mirrored by what the mosaic sees
	var world := Vector2(a.end.x - 95, a.position.y + 8)
	var wr := Rect2(world, Vector2(85, a.size.y - 16))
	draw_rect(wr, DIM, false, 1.0)
	draw_string(UITheme.mono(), wr.position + Vector2(4, 13), "SCENE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	var op := wr.position + Vector2(wr.size.x * u, wr.size.y * 0.5 + sin(t * 1.3) * 18.0 * wr.size.y / a.size.y)
	if wr.has_point(op):
		draw_circle(op, 9.0, LINE)
	draw_line(Vector2(world.x - 10, a.get_center().y), Vector2(origin.x + cols * dx + 4, a.get_center().y), FAINT, 1.0)


## Smell: puffs drift from a fruit to an antenna; on arrival a fixed subset of glomeruli lights.
func _smell(a: Rect2, t: float) -> void:
	var src := a.position + Vector2(30, a.size.y * 0.5)
	var ant := a.position + Vector2(a.size.x * 0.48, a.size.y * 0.5)
	_fruit(src, 16.0, HI)
	draw_line(ant + Vector2(0, -30), ant + Vector2(8, 30), LINE, 3.0)           # antenna
	draw_string(UITheme.mono(), ant + Vector2(-26, 46), "ANTENNA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	var arrived := 0.0
	for i in 14:
		var u := fmod(t * 0.35 + i / 14.0, 1.0)
		var p := src.lerp(ant, u) + Vector2(0, sin(u * 9.0 + i) * 14.0 * (1.0 - u))
		draw_circle(p, 2.5, Color(HI, 1.0 - u * 0.6))
		if u > 0.85:
			arrived += 1.0
	# glomeruli: a cluster; odour pattern = a fixed subset, brightness with recent arrivals
	var gc := a.position + Vector2(a.size.x * 0.8, a.size.y * 0.5)
	var pattern := [1, 4, 5, 9, 12]
	var level := clampf(arrived / 3.0, 0.0, 1.0)
	for i in 14:
		var ang := i * 2.4
		var p := gc + Vector2(cos(ang), sin(ang)) * (12.0 + 4.6 * sqrt(i) * 5.0) * 0.55
		var on := i in pattern
		draw_circle(p, 9.0, Color(HI, 0.25 + 0.7 * level) if on else Color(FAINT, 0.8))
		draw_arc(p, 9.0, 0, TAU, 20, DIM, 1.0)
	draw_line(ant + Vector2(12, 0), gc - Vector2(48, 0), FAINT, 1.0)
	draw_string(UITheme.mono(), gc + Vector2(-38, a.size.y * 0.5 - 4), "GLOMERULI", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)


## Memory: two odours alternate; each lights its own sparse set of Kenyon cells, and odour A's
## set is tagged with a reward.
func _memory(a: Rect2, t: float) -> void:
	var phase := int(t / 3.0) % 2
	var names := ["ODOUR A", "ODOUR B"]
	var font := UITheme.mono()
	draw_string(font, a.position + Vector2(0, 16), names[phase], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HI)
	var cols := 16
	var rows := 6
	var g := Vector2(a.size.x * 0.62 / cols, (a.size.y - 30) / rows)
	var o := a.position + Vector2(g.x * 0.5, 34)
	var fade := clampf(fmod(t, 3.0) / 0.5, 0.0, 1.0)
	for k in cols * rows:
		var on := (hash(k * 7 + phase * 131) % 100) < 7         # ~7 % of cells per odour
		var p := o + Vector2(k % cols * g.x, k / cols * g.y)
		draw_circle(p, 5.0, Color(HI, fade) if on else FAINT)
	draw_string(font, o + Vector2(-4, rows * g.y + 2), "KENYON CELLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	var tag := a.position + Vector2(a.size.x * 0.82, a.size.y * 0.5)
	if phase == 0:
		draw_circle(tag, 26.0 * fade, Color(HI, 0.2))
		draw_string(font, tag + Vector2(-34, 5), "+ SUGAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HI)
		draw_string(font, tag + Vector2(-40, 44), "→ APPROACH", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LINE)
	else:
		draw_string(font, tag + Vector2(-34, 5), "no reward", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)
		draw_string(font, tag + Vector2(-34, 44), "→ IGNORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)


## Instinct: the fly heads for food, then a wasp appears and it turns away.
func _instinct(a: Rect2, t: float) -> void:
	var food := a.position + Vector2(40, a.size.y * 0.5)
	var wasp := a.position + Vector2(a.size.x - 40, a.size.y * 0.5)
	var font := UITheme.mono()
	_fruit(food, 18.0, HI)
	draw_string(font, food + Vector2(-20, 40), "FOOD", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HI)
	# wasp: striped body + warning
	draw_circle(wasp, 14.0, Color(BAD, 0.25))
	for k in 3:
		draw_line(wasp + Vector2(-10 + k * 8, -10), wasp + Vector2(-10 + k * 8, 10), BAD, 2.0)
	draw_string(font, wasp + Vector2(-20, 40), "WASP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BAD)
	# fly drifts toward whichever is "smelled"; alternate every 4 s
	var phase := fmod(t, 8.0)
	var mid := a.get_center()
	var pos: Vector2
	var dir: float
	if phase < 4.0:
		var u := smoothstep(0.0, 4.0, phase)
		pos = mid.lerp(food + Vector2(45, 0), u)
		dir = PI
		draw_dashed_line(mid, food + Vector2(30, 0), Color(HI, 0.5), 1.0, 5.0)
	else:
		var u := smoothstep(4.0, 8.0, phase)
		pos = mid.lerp(mid + Vector2(-60, -35), u)
		dir = lerpf(0.0, -2.6, u)
		draw_dashed_line(wasp - Vector2(25, 0), mid, Color(BAD, 0.5), 1.0, 5.0)
	_fly_icon(pos, dir, 9.0, LINE)


## Compass: the ellipsoid body as a ring of wedges; the bump of activity follows the heading
## of the fly in the middle as it turns.
func _compass(a: Rect2, t: float) -> void:
	var c := a.position + Vector2(a.size.x * 0.33, a.size.y * 0.5)
	var rad := minf(a.size.y * 0.46, 85.0)
	var heading := sin(t * 0.45) * 2.2 + t * 0.25
	var n := 16
	for i in n:
		var a0 := TAU * i / n
		var d := absf(wrapf(a0 - heading, -PI, PI))
		var act := exp(-d * d / 0.25)
		var pts := PackedVector2Array()
		for k in 7:
			var ang := a0 - PI / n + (TAU / n) * k / 6.0
			pts.append(c + Vector2.from_angle(ang) * rad)
		for k in range(6, -1, -1):
			var ang := a0 - PI / n + (TAU / n) * k / 6.0
			pts.append(c + Vector2.from_angle(ang) * rad * 0.68)
		draw_colored_polygon(pts, Color(HI, 0.08 + 0.85 * act))
		draw_polyline(pts, DIM, 1.0)
	_fly_icon(c, heading, 8.0, LINE)
	var font := UITheme.mono()
	draw_string(font, c + Vector2(rad + 26, -18), "ELLIPSOID BODY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	draw_string(font, c + Vector2(rad + 26, 2), "bump = heading", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HI)
	draw_string(font, c + Vector2(rad + 26, 22), "%3d°" % int(fposmod(rad_to_deg(heading), 360.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, LINE)


## Hearing: a pulse song waveform reaches the arista, which shakes; spikes follow below.
func _hearing(a: Rect2, t: float) -> void:
	var font := UITheme.mono()
	var wave := PackedVector2Array()
	var y0 := a.position.y + a.size.y * 0.3
	var x1 := a.position.x + a.size.x * 0.62
	for i in 120:
		var x := lerpf(a.position.x, x1, i / 119.0)
		var ph := (x - a.position.x) * 0.12 - t * 9.0
		var pulse := maxf(0.0, sin(ph * 0.12)) ** 6.0                    # pulse trains
		wave.append(Vector2(x, y0 + sin(ph * 2.0) * 18.0 * pulse))
	draw_polyline(wave, HI, 1.5)
	draw_string(font, Vector2(a.position.x, y0 - 26), "COURTSHIP SONG", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	# antenna with feathery arista, shaking with the current pulse amplitude
	var base := Vector2(x1 + 50, y0 + 10)
	var amp := maxf(0.0, sin((x1 - a.position.x) * 0.12 * 0.12 - t * 9.0 * 0.12)) ** 6.0
	var tip := base + Vector2(60, -40).rotated(sin(t * 40.0) * 0.25 * amp)
	draw_line(base, base + Vector2(0, 30), LINE, 4.0)
	draw_line(base, tip, LINE, 1.5)
	for k in 6:
		var p := base.lerp(tip, (k + 1) / 7.0)
		draw_line(p, p + (tip - base).orthogonal().normalized() * 7.0, DIM, 1.0)
	draw_string(font, base + Vector2(-20, 48), "ARISTA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	# spike raster of Johnston's organ
	var sy := a.position.y + a.size.y * 0.8
	draw_line(Vector2(a.position.x, sy), Vector2(x1, sy), FAINT, 1.0)
	for i in 60:
		var x := lerpf(a.position.x, x1, i / 59.0)
		var ph := (x - a.position.x) * 0.12 - t * 9.0
		if maxf(0.0, sin(ph * 0.12)) ** 6.0 > 0.5 and i % 2 == 0:
			draw_line(Vector2(x, sy - 12), Vector2(x, sy), LINE, 1.5)
	draw_string(font, Vector2(a.position.x, sy + 16), "SPIKES", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)


## Taste: a leg steps onto sugar, and the proboscis extends toward it.
func _taste(a: Rect2, t: float) -> void:
	var font := UITheme.mono()
	var phase := fmod(t, 5.0)
	var ground := a.position.y + a.size.y - 14
	draw_line(Vector2(a.position.x, ground), Vector2(a.end.x, ground), DIM, 1.0)
	var sugar := Vector2(a.position.x + a.size.x * 0.32, ground - 6)
	for k in 5:
		draw_rect(Rect2(sugar + Vector2(-14 + k * 6, -(k % 2) * 5), Vector2(6, 6)), HI)
	draw_string(font, sugar + Vector2(-20, -18), "SUGAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HI)
	# side-view head + body
	var head := Vector2(a.position.x + a.size.x * 0.48, a.position.y + a.size.y * 0.3)
	draw_circle(head, 20.0, Color(LINE, 0.15))
	draw_arc(head, 20.0, 0, TAU, 32, LINE, 1.5)
	draw_circle(head + Vector2(-6, -4), 9.0, Color(BAD, 0.6))           # eye
	draw_rect(Rect2(head + Vector2(18, -18), Vector2(110, 40)), Color(LINE, 0.15))
	draw_rect(Rect2(head + Vector2(18, -18), Vector2(110, 40)), LINE, false, 1.5)
	# front leg reaching down to the sugar
	var step := smoothstep(0.0, 1.2, phase)
	var foot := Vector2(lerpf(head.x + 30, sugar.x + 8, step), ground - 2)
	var knee := Vector2(head.x + 10, head.y + 40)
	draw_polyline(PackedVector2Array([head + Vector2(26, 18), knee, foot]), LINE, 2.0)
	# proboscis extends once the foot has tasted
	var ext := smoothstep(1.4, 2.4, phase) * (1.0 - smoothstep(4.0, 4.8, phase))
	var root := head + Vector2(-8, 18)
	var ptip := root + Vector2(-10 - 24 * ext, 14 + 40 * ext)
	draw_line(root, ptip, HI if ext > 0.1 else LINE, 3.0)
	draw_circle(ptip, 4.0, HI if ext > 0.1 else LINE)
	if step >= 1.0:
		draw_circle(foot, 6.0 + 4.0 * sin(t * 8.0), Color(HI, 0.4))
	draw_string(font, Vector2(a.end.x - 150, a.position.y + 16),
		"PROBOSCIS EXTENDS" if ext > 0.1 else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HI)


## Brain to body: pulses run down the neck connective to the legs; fainter ones return.
func _descend(a: Rect2, t: float) -> void:
	var font := UITheme.mono()
	var top := Vector2(a.get_center().x, a.position.y + 26)
	var bottom := Vector2(a.get_center().x, a.end.y - 30)
	draw_rect(Rect2(top - Vector2(90, 22), Vector2(180, 40)), LINE, false, 1.5)
	draw_string(font, top + Vector2(-26, 3), "BRAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LINE)
	draw_rect(Rect2(bottom - Vector2(40, 16), Vector2(80, 44)), LINE, false, 1.5)
	draw_string(font, bottom + Vector2(-16, 10), "VNC", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LINE)
	for k in 3:
		for s in [-1.0, 1.0]:
			var p := bottom + Vector2(40 * s, -6 + k * 14)
			draw_line(p, p + Vector2(55 * s, 10 + k * 6), DIM, 1.5)
	var neck_a := top + Vector2(0, 18)
	var neck_b := bottom - Vector2(0, 16)
	for dx in [-14.0, -5.0, 5.0, 14.0]:
		draw_line(neck_a + Vector2(dx, 0), neck_b + Vector2(dx, 0), FAINT, 1.0)
	for i in 6:
		var u := fmod(t * 0.5 + i / 6.0, 1.0)
		var dx: float = [-14.0, -5.0, 5.0][i % 3]
		draw_circle(neck_a.lerp(neck_b, u) + Vector2(dx, 0), 4.0, HI)        # descending
	for i in 3:
		var u := fmod(t * 0.35 + i / 3.0, 1.0)
		draw_circle(neck_b.lerp(neck_a, u) + Vector2(14, 0), 3.0, Color(LINE, 0.7))   # ascending
	draw_string(font, Vector2(top.x + 110, a.get_center().y - 8), "↓ commands", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HI)
	draw_string(font, Vector2(top.x + 110, a.get_center().y + 12), "↑ feedback", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LINE)


## Gait: a scrolling stance / swing chart for the six legs; the two tripods alternate.
func _gait(a: Rect2, t: float) -> void:
	var font := UITheme.mono()
	var legs := ["L1", "R2", "L3", "R1", "L2", "R3"]
	var row_h := a.size.y / 6.5
	var x0 := a.position.x + 34
	var x1 := a.end.x - 6
	var period := 1.6
	for i in 6:
		var y := a.position.y + i * row_h + (row_h * 0.5 if i >= 3 else 0.0)
		draw_string(font, Vector2(a.position.x, y + row_h * 0.65), legs[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			HI if i < 3 else LINE)
		var offset := 0.0 if i < 3 else 0.5
		# stance (on the ground) drawn as filled bars, scrolling left
		var x := x0
		while x < x1:
			var ph := fposmod((x - x0) / 110.0 + t / period + offset, 1.0)
			var seg := minf(4.0, x1 - x)
			if ph < 0.5:
				draw_rect(Rect2(x, y + 3, seg, row_h - 8), Color(HI, 0.85) if i < 3 else Color(LINE, 0.7))
			x += 4.0
	draw_line(Vector2(x0 + 2, a.position.y), Vector2(x0 + 2, a.end.y), DIM, 1.0)
	draw_string(font, Vector2(x1 - 220, a.end.y + 2), "filled = foot on the ground", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
