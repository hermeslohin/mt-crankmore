extends ColorRect
## The dark, over the world and under the HUD: the screen is multiplied by Skies.tint() (dusk orange, night blue, grey
## under rain clouds) except in the pools of warm light around street lamps, headlights and bike lights. The pools
## come in a few hard steps of brightness, for the 16-bit look. `source` hands over the lights each frame:
## night_lights() -> [[world position on screen (canvas coords), radius px, strength 0-1], ...].

const MAX_LIGHTS := 48

var source: Callable          # returns the lights to draw, or an empty array
var _lights := PackedVector4Array()

const SHADER := """
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 warm = vec3(1.0, 0.9, 0.68);
uniform vec2 size = vec2(640.0, 360.0);
uniform int count = 0;
uniform vec4 lights[48];

void fragment() {
	vec2 p = UV * size;
	float l = 0.0;
	for (int i = 0; i < count; i++) {
		vec2 d = p - lights[i].xy;
		d.y *= 1.8;   // pools lie flat on the isometric ground
		float f = 1.0 - smoothstep(0.0, lights[i].z, length(d));
		l = max(l, f * lights[i].w);
		l = min(1.0, l + f * lights[i].w * 0.25);
	}
	l = floor(l * 5.0 + 0.5) / 5.0;
	COLOR = vec4(mix(tint.rgb, warm, l), 1.0);
}
"""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	material = ShaderMaterial.new()
	material.shader = sh
	_lights.resize(MAX_LIGHTS)


func _process(_delta: float) -> void:
	size = get_viewport_rect().size   # under a CanvasLayer the anchors alone leave it at 0x0
	var t := Skies.tint()
	var lit: Array = source.call() if source.is_valid() and Skies.dark() > 0.05 else []
	visible = t.r < 0.995 or t.g < 0.995 or t.b < 0.995 or not lit.is_empty()
	if not visible:
		return
	var xf := get_viewport().get_canvas_transform()
	var zoom := xf.x.x
	var view := Rect2(Vector2.ZERO, size).grow(80.0)
	var n := 0
	for li in lit:
		var at: Vector2 = xf * (li[0] as Vector2)
		if n >= MAX_LIGHTS or not view.has_point(at):
			continue
		_lights[n] = Vector4(at.x, at.y, float(li[1]) * zoom, float(li[2]))
		n += 1
	var m := material as ShaderMaterial
	m.set_shader_parameter("tint", t)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("count", n)
	m.set_shader_parameter("lights", _lights)
