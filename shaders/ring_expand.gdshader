shader_type spatial;
render_mode unshaded, transparent, cull_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ring_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform float max_radius : hint_range(0.2, 6.0) = 1.6;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	// 归一化半径 0..1 对应 max_radius；progress 从 0 到 1 表示波纹向外扩散
	float r = progress;
	float ring = smoothstep(0.10, 0.0, abs(d - r));
	// 第二圈更细的内环，做出「声纹」的层次
	float ring2 = smoothstep(0.07, 0.0, abs(d - r * 0.6)) * 0.5;
	float rings = clamp(ring + ring2, 0.0, 1.0);
	float fade = 1.0 - progress;            // 越扩散越淡
	float edge = smoothstep(1.0, 0.9, d);   // 裁掉四边形边缘外
	float alpha = rings * fade * edge;
	ALBEDO = ring_color.rgb;
	ALPHA = ring_color.a * alpha;
}
