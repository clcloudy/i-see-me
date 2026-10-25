shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, shadows_disabled, blend_mix;

// L2/L3 全屏后处理。
// Compatibility 渲染器的 depth_texture 是反向 Z（near/depth ≈ 视空间距离），
// 所以用 near/depth 重建视空间位置，再和 focus_view 比较，得到真实的米制距离。
// 视空间是相机的刚体变换，因此距离与相机旋转/平移无关。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec3 focus_view = vec3(0.0);
uniform float near = 0.05;
uniform float tan_half_fov = 0.637;
uniform float aspect = 1.777;
uniform float radius = 2.0;
uniform float falloff = 1.2;
uniform float blur_pixels = 24.0;
uniform float strength = 0.0;
uniform float desaturate = 0.15;
uniform float edge_darken = 0.25;
// L3 抽离进度：1 = 只保留地板与主角，整幅画面转纯灰度。
uniform float grayscale = 0.0;
// 背景（天空）退成虚空的进度；地板与主角是几何体，不参与这一混合。
uniform float void_blend = 0.0;
// L3 的天空/背景退成这个中性灰。
uniform vec3 void_color = vec3(0.11);

const int TAPS = 24;
const float GOLDEN_ANGLE = 2.39996323;

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	// 反向 Z：近处 depth 大、远处 depth 小；near/depth 是线性视距离。
	float view_z = near / max(depth, 0.00001);
	float tan_half = tan_half_fov;
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	// 视空间中的屏幕射线（z = -1），乘以视距离得到该像素的视空间位置。
	vec3 p_view = vec3(ndc.x * tan_half * aspect, -ndc.y * tan_half, -1.0) * view_z;
	float distance_to_focus = length(p_view - focus_view);
	float blur_weight = smoothstep(radius, radius + falloff, distance_to_focus);

	vec2 texel = 1.0 / VIEWPORT_SIZE;
	float blur_scale = blur_pixels * (VIEWPORT_SIZE.y / 720.0) * blur_weight;
	vec3 base = texture(screen_texture, SCREEN_UV).rgb;
	vec3 blurred = base;
	// L3 时 blur_pixels 会降到 0；跳过 24 次采样，避免无意义的全屏开销。
	if (blur_scale > 0.01) {
		vec3 accumulated = vec3(0.0);
		for (int i = 0; i < TAPS; i++) {
			float angle = float(i) * GOLDEN_ANGLE;
			float ring = sqrt((float(i) + 0.5) / float(TAPS));
			vec2 offset = vec2(cos(angle), sin(angle)) * ring * blur_scale * texel;
			accumulated += texture(screen_texture, SCREEN_UV + offset).rgb;
		}
		blurred = accumulated / float(TAPS);
	}

	// 模糊区去饱和并轻微压暗，把注意力留在清晰球内。灰黑材质由 L2FlowState 的 clay 覆盖完成。
	float luma = dot(blurred, vec3(0.299, 0.587, 0.114));
	vec3 toned = mix(blurred, vec3(luma) * vec3(0.95, 0.98, 1.02), desaturate);
	toned *= mix(1.0, 1.0 - edge_darken, blur_weight);

	vec3 composed = mix(base, toned, clamp(strength, 0.0, 1.0));
	// L3：天空（反向 Z 下 depth≈0）渐隐为虚空；地板与主角是几何体，不受影响。
	float sky = step(depth, 0.00001);
	composed = mix(composed, void_color, sky * clamp(void_blend, 0.0, 1.0));
	// L3：连环境光带来的色偏一起去掉，保留纯灰度。
	float gray = dot(composed, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(composed, vec3(gray), clamp(grayscale, 0.0, 1.0));
	ALPHA = 1.0;
}
