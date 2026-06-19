shader_type spatial;

// 砖块颜色参数 - 使用明确的三种颜色
uniform vec4 brick_color_black : source_color = vec4(0.1, 0.1, 0.1, 1.0);    // 黑色砖块
uniform vec4 brick_color_gray : source_color = vec4(0.5, 0.5, 0.5, 1.0);     // 灰色砖块  
uniform vec4 brick_color_white : source_color = vec4(0.9, 0.9, 0.9, 1.0);   // 白色砖块
uniform vec4 gap_color : source_color = vec4(0.05, 0.05, 0.05, 1.0);        // 缝隙颜色

// 颜色分布控制
uniform float color_variation_strength : hint_range(0.0, 1.0) = 1.0; // 颜色变化强度

// 表面物理属性
uniform float brick_roughness : hint_range(0.0, 1.0) = 0.4;    // 砖块粗糙度
uniform float gap_roughness : hint_range(0.0, 1.0) = 0.8;     // 缝隙粗糙度
uniform float brick_metallic : hint_range(0.0, 1.0) = 0.0;    // 砖块金属度
uniform float gap_metallic : hint_range(0.0, 1.0) = 0.0;       // 缝隙金属度

// 砖块参数
uniform float brick_length = 3.0;
uniform float scale = 8.0;

// 简单随机函数用于颜色分配
float hash(float n) { 
    return fract(sin(n) * 43758.5453);
}

// 混合函数
vec4 composit(in vec4 top, in vec4 bottom) {
    return vec4(mix(top.xyz, bottom.xyz, 1.0 - top.a), 1.0);
}

// 在三色之间选择砖块颜色 - 核心修改
vec3 select_brick_color(float plank, float item) {
    // 为每个砖块生成确定性但唯一的ID
    float brick_id = plank * 127.1 + item * 311.7;
    
    // 使用hash函数生成0-1之间的值，但避免噪声算法的复杂性
    float color_selector = hash(brick_id);
    
    // 根据选择器值在三色之间明确分配
    if (color_selector < 0.33) {
        return brick_color_black.rgb;  // 33%的概率为黑色
    } else if (color_selector < 0.66) {
        return brick_color_gray.rgb;   // 33%的概率为灰色
    } else {
        return brick_color_white.rgb;  // 34%的概率为白色
    }
}

void fragment() {
    vec2 uv = UV * scale;
    float plank = floor(uv.x); // 每行砖块的唯一标识
    float start = 10.0 * hash(plank);
    float item = floor(uv.y / brick_length + start);
    
    // 直接在三色之间选择砖块颜色 - 关键修改
    vec3 brick_final_color = select_brick_color(plank, item);
    
    // 可选的轻微亮度变化（保持黑白灰基调）
    float brightness_variation = mix(0.9, 1.1, hash(plank * 73.1 + item * 29.3));
    brick_final_color *= brightness_variation * color_variation_strength;
    brick_final_color = clamp(brick_final_color, 0.0, 1.0);
    
    // 计算缝隙遮罩
    float plankGapY = step(0.0, fract(uv.x)) * (1.0 - step(0.02, fract(uv.x)));
    float plankGapX = step(0.0, fract(uv.y / brick_length + start)) * 
                      (1.0 - step(0.02 / brick_length, fract(uv.y / brick_length + start)));
    float gap_mask = max(plankGapY, plankGapX);
    
    // 创建砖块和缝隙的混合颜色
    vec4 gap = vec4(gap_color.r, gap_color.g, gap_color.b, gap_mask);
    vec4 brick = vec4(brick_final_color, 1.0);
    
    // 计算最终颜色
    vec3 final_albedo = composit(gap, brick).rgb;
    
    // 输出材质属性
    ALBEDO = final_albedo;
    
    // 根据是否在缝隙区域选择不同的粗糙度和金属度
    ROUGHNESS = mix(brick_roughness, gap_roughness, gap_mask);
    METALLIC = mix(brick_metallic, gap_metallic, gap_mask);
    
    // 法线设置
    NORMAL = vec3(0.0, 0.0, 1.0);
    
    // 缝隙不受光照影响
    EMISSION = gap_color.rgb * gap_mask;
}