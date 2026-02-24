shader_type canvas_item;

uniform vec2  light_pos   = vec2(0.5, 0.5); // in UV space (0..1)
uniform float light_radius = 0.15;           // fraction of screen
uniform float softness     = 0.08;           // edge feather width
uniform vec4  dark_color   : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	// Convert light_pos from UV to screen-space UV matching this fragment
	float dist = distance(UV, light_pos);

	// Smooth falloff: 0 at center, 1 at edge and beyond
	float darkness = smoothstep(light_radius, light_radius + softness, dist);

	COLOR = vec4(dark_color.rgb, dark_color.a * darkness);
}
