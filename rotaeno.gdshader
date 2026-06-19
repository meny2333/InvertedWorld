shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D note_texture : source_color;
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;

uniform float ring_radius : hint_range(0.0, 1.0) = 0.7;
uniform float ring_thickness : hint_range(0.0, 0.5) = 0.15;
uniform int note_count : hint_range(1, 64) = 16;
uniform float note_width : hint_range(0.0, 1.0) = 0.6;
uniform float rotation_speed : hint_range(-5.0, 5.0) = 0.5;
uniform float time : hint_range(0.0, 100.0);

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    float angle = atan(uv.y, uv.x);
    
    float norm_angle = angle / (2.0 * 3.14159265) + 0.5;
    norm_angle += time * rotation_speed * 0.1;
    norm_angle = fract(norm_angle);
    
    // 环的径向范围
    float inner_r = ring_radius - ring_thickness * 0.5;
    float outer_r = ring_radius + ring_thickness * 0.5;
    float in_ring = smoothstep(inner_r - 0.02, inner_r, dist) 
                  * (1.0 - smoothstep(outer_r, outer_r + 0.02, dist));
    
    // 音符分段
    float note_float = norm_angle * float(note_count);
    float note_frac = fract(note_float);
    
    float in_note = step(note_frac, note_width);
    
    // 切向排列：UV旋转90度
    // X = 径向位置（上下），Y = 切向位置（左右，即箭头指向）
    vec2 sample_uv;
    sample_uv.x = (dist - inner_r) / (outer_r - inner_r);  // 0~1 径向
    sample_uv.y = 1.0 - (note_frac / note_width);          // 0~1 切向，翻转让箭头朝正确方向
    
    // 如果方向反了，改这行：sample_uv.y = note_frac / note_width;
    
    vec4 tex = texture(note_texture, sample_uv);
    
    float alpha = tex.a * in_ring * in_note;
    
    ALBEDO = tex.rgb * glow_intensity;
    ALPHA = alpha;
    EMISSION = tex.rgb * glow_intensity * 0.8;
}