shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

// L3 专用地面：纯色 + 细分格线，远处淡入虚空，不接收光照/烘焙阴影。
uniform vec3 base_color = vec3(0.42, 0.44, 0.46);
uniform vec3 line_color = vec3(0.22, 0.23, 0.24);
uniform vec3 void_color = vec3(0.11);
uniform float tile_size = 3.0;
uniform float line_width = 0.8;
uniform float fade_start = 12.0;
uniform float fade_end = 30.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 世界空间网格：线条不随相机/物体移动，接缝在 2 m 方格上。
	vec2 coord = world_pos.xz / tile_size;
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / max(fwidth(coord), vec2(0.0001));
	float line = 1.0 - smoothstep(0.0, max(line_width, 0.0001), min(grid.x, grid.y));

	vec3 color = mix(base_color, line_color, line);
	// 远处淡入虚空，避免 200 m 平面的硬边/远裁剪硬线。
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(fade_start, max(fade_end, fade_start + 0.01), dist);
	ALBEDO = mix(void_color, color, fade);
}
