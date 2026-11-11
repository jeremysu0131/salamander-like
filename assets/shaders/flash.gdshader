shader_type canvas_item;
// 受擊白閃（GDD 9.3）。flash 為 1 時整張圖變白，保留透明度。

uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(mix(c.rgb, vec3(1.0), flash), c.a);
}
