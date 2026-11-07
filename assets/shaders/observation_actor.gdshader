shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// 黑色覆盖层均匀压暗整个人；透明时完整露出原来的颜色与光照。
	ALBEDO = vec3(0.0);
	ALPHA = 0.72 * pulse;
}
