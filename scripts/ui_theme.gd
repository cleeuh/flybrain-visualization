class_name UITheme
extends RefCounted
## Radiology-viewer look (CT / MRI workstation) shared by the overlays — narration panel and
## key strip: monospace grey-white annotation text on near-black, yellow highlights, thin
## grey rules and L-shaped corner brackets instead of boxed panels.

const BG := Color(0.0, 0.0, 0.0, 0.78)
const BRACKET := Color(0.85, 0.85, 0.85, 0.75)
const BRACKET_LEN := 18.0

## BBCode hex colours for RichTextLabel text.
const H_TEXT := "e4e4e4"
const H_DIM := "8a8a8a"
const H_FAINT := "5a5a5a"
const H_HI := "ffd84a"      ## annotation yellow: header, abbreviations, current slide
const H_SUB := "b8c4cc"     ## formal names

static var _fonts := {}


## Monospace system font; weight 700 for bold, italic for the formal names.
static func mono(weight := 400, italic := false) -> Font:
	var k := "%d%s" % [weight, italic]
	if not _fonts.has(k):
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Consolas",
			"Menlo", "Liberation Mono", "monospace"])
		f.font_weight = weight
		f.font_italic = italic
		_fonts[k] = f
	return _fonts[k]


## Flat black backing with no border; the corners come from add_brackets().
static func panel(margin := 24.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_content_margin_all(margin)
	return sb


## Gives a control the four L-shaped corner marks of a viewer's image frame.
static func add_brackets(c: Control) -> void:
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if corner.x == r.position.x else -1.0
			var sy := 1.0 if corner.y == r.position.y else -1.0
			c.draw_line(corner, corner + Vector2(BRACKET_LEN * sx, 0), BRACKET, 1.5)
			c.draw_line(corner, corner + Vector2(0, BRACKET_LEN * sy), BRACKET, 1.5))
