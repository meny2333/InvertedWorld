shader_type spatial;
render_mode cull_back;

// Cylinder params (world space)
uniform vec3 cylinder_axis_point = vec3(0.0, 0.0, 0.0);
uniform vec3 cylinder_axis = vec3(0.707, 0.0, -0.707); // will be normalized
uniform float cylinder_radius = 14.5;

// Line params (world space)
uniform vec3 line_start_position;
uniform vec3 line_end_position;

// Mesh param (model space)
// BoxMesh's Z size (used to normalize local_pos.z to [0, 1]).
uniform float mesh_z_size = 1.0;

// Cylinder frame hints (world space). Will be orthonormalized in vertex().
uniform vec3 reference_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 perpendicular_direction = vec3(1.0, 0.0, 0.0);

// Material params
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform bool use_emission = false;
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 1.0;

// Join overlap support (extends geometry along the curve tangent).
uniform float start_extend = 0.0;
uniform float end_extend = 0.0;

// Cap control (per-segment).
uniform bool discard_start_cap = false;
uniform bool discard_end_cap = false;

// 奇数次TP效果参数
uniform bool is_odd_tp = false;
uniform bool is_active_line = false;
uniform vec4 odd_tp_emission_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float odd_tp_emission_energy : hint_range(0.0, 16.0) = 2.0;
// 时间渐变参数 - 线头白蓝色，掠过位置随时间变蓝黑色
uniform float current_time = 0.0; // 当前游戏时间
uniform float segment_start_time = 0.0; // 线段开始时间
uniform float segment_end_time = 0.0; // 线段结束时间（活动段会持续更新为当前时间）
uniform float fade_duration = 2.0; // 褪色持续时间（秒）
uniform vec3 trail_head_color : source_color = vec3(0.85, 0.92, 1.0); // 线头白蓝色（偏淡蓝）
uniform vec3 trail_tail_color : source_color = vec3(0.1, 0.2, 0.4); // 线尾蓝黑色

varying float v_is_cap;
varying float v_cap_nz;
varying float v_t; // 用于渐变效果，t=0是线尾，t=1是线头

vec3 project_to_axis(vec3 point, vec3 axis_point, vec3 axis_dir) {
vec3 to_point = point - axis_point;
float axial_distance = dot(to_point, axis_dir);
return axis_point + axis_dir * axial_distance;
}

vec3 get_radial_from_angle(float angle, vec3 ref_dir, vec3 perp_dir) {
return normalize(ref_dir * cos(angle) + perp_dir * sin(angle));
}

float get_angle_on_cylinder(vec3 point, vec3 axis_point, vec3 axis_dir, vec3 ref_dir, vec3 perp_dir) {
vec3 projection = project_to_axis(point, axis_point, axis_dir);
vec3 radial = point - projection;
float len = length(radial);
if (len < 0.001) return 0.0;
radial /= len;

float cos_angle = dot(radial, ref_dir);
float sin_angle = dot(radial, perp_dir);
return atan(sin_angle, cos_angle);
}

vec3 calculate_cylinder_normal(vec3 surface_point, vec3 axis_point, vec3 axis_dir) {
vec3 axial_projection = project_to_axis(surface_point, axis_point, axis_dir);
vec3 radial = surface_point - axial_projection;
float len = length(radial);
return (len > 0.001) ? (radial / len) : vec3(0.0, 1.0, 0.0);
}

vec3 interpolate_on_cylinder(
vec3 start_pos, vec3 end_pos, float t,
vec3 axis_point, vec3 axis_dir, float radius,
vec3 ref_dir, vec3 perp_dir
) {
float start_angle = get_angle_on_cylinder(start_pos, axis_point, axis_dir, ref_dir, perp_dir);
float end_angle = get_angle_on_cylinder(end_pos, axis_point, axis_dir, ref_dir, perp_dir);

float angle_diff = end_angle - start_angle;
if (angle_diff > 3.14159) {
start_angle += 6.28318;
} else if (angle_diff < -3.14159) {
end_angle += 6.28318;
}

float a = mix(start_angle, end_angle, t);

vec3 start_axial = project_to_axis(start_pos, axis_point, axis_dir);
vec3 end_axial = project_to_axis(end_pos, axis_point, axis_dir);
vec3 axial = mix(start_axial, end_axial, t);

vec3 radial_dir = get_radial_from_angle(a, ref_dir, perp_dir);
return axial + radial_dir * radius;
}

vec3 any_perp(vec3 n) {
return (abs(n.y) < 0.999)
? normalize(cross(n, vec3(0.0, 1.0, 0.0)))
: normalize(cross(n, vec3(1.0, 0.0, 0.0)));
}

void vertex() {
// Original box normal in model space (encodes which face we're on)
vec3 n0 = NORMAL;
v_is_cap = step(0.9, abs(n0.z));
v_cap_nz = n0.z;

// Model-space vertex
vec3 local_pos = VERTEX;

// Progress along the box's local Z. Supports BoxMesh.size.z != 1.
float inv_z = (abs(mesh_z_size) > 0.000001) ? (1.0 / mesh_z_size) : 1.0;
float t = clamp(local_pos.z * inv_z + 0.5, 0.0, 1.0);
v_t = t; // 传递给fragment用于渐变计算

// Orthonormalize cylinder frame (world space)
vec3 axis_dir = normalize(cylinder_axis);

vec3 ref_dir = reference_direction - axis_dir * dot(reference_direction, axis_dir);
float ref_len = length(ref_dir);
ref_dir = (ref_len < 0.001) ? any_perp(axis_dir) : (ref_dir / ref_len);

vec3 perp_dir = perpendicular_direction - axis_dir * dot(perpendicular_direction, axis_dir);
perp_dir = perp_dir - ref_dir * dot(perp_dir, ref_dir);
float perp_len = length(perp_dir);
perp_dir = (perp_len < 0.001) ? normalize(cross(axis_dir, ref_dir)) : (perp_dir / perp_len);

// Center point on cylinder (world space)
vec3 curved_center = interpolate_on_cylinder(
line_start_position, line_end_position, t,
cylinder_axis_point, axis_dir, cylinder_radius,
ref_dir, perp_dir
);

// Tangent (world space) via finite difference
float epsilon = 0.01;
float t_before = clamp(t - epsilon, 0.0, 1.0);
float t_after = clamp(t + epsilon, 0.0, 1.0);

vec3 point_before = interpolate_on_cylinder(
line_start_position, line_end_position, t_before,
cylinder_axis_point, axis_dir, cylinder_radius,
ref_dir, perp_dir
);

vec3 point_after = interpolate_on_cylinder(
line_start_position, line_end_position, t_after,
cylinder_axis_point, axis_dir, cylinder_radius,
ref_dir, perp_dir
);

vec3 tangent_dir = point_after - point_before;
float tan_len = length(tangent_dir);
if (tan_len < 0.0001) {
tangent_dir = line_end_position - line_start_position;
float tl = length(tangent_dir);
tangent_dir = (tl < 0.0001) ? axis_dir : (tangent_dir / tl);
} else {
tangent_dir /= tan_len;
}

// Radial (world space) from cylinder, orthogonalize against tangent
vec3 radial_dir = calculate_cylinder_normal(curved_center, cylinder_axis_point, axis_dir);
radial_dir = radial_dir - tangent_dir * dot(radial_dir, tangent_dir);
float rlen = length(radial_dir);
radial_dir = (rlen < 0.0001) ? any_perp(tangent_dir) : (radial_dir / rlen);

// IMPORTANT: use a right-handed frame (fixes "faces pointing inward" with cull_back)
vec3 lateral_dir = cross(radial_dir, tangent_dir); // L = R x T so (L x R) == T
float llen = length(lateral_dir);
lateral_dir = (llen < 0.0001) ? any_perp(radial_dir) : (lateral_dir / llen);

// Re-orthonormalize tangent, keep its original direction
vec3 tangent_ortho = normalize(cross(lateral_dir, radial_dir));
if (dot(tangent_ortho, tangent_dir) < 0.0) {
tangent_ortho = -tangent_ortho;
lateral_dir = normalize(cross(radial_dir, tangent_ortho));
}
tangent_dir = tangent_ortho;

// Apply thickness offsets in world space
vec3 final_position_world = curved_center + lateral_dir * local_pos.x + radial_dir * local_pos.y;
// Extend ends to overlap at joins without changing endpoints.
final_position_world += (-tangent_dir) * start_extend * (1.0 - t) + tangent_dir * end_extend * t;

// Write back vertex in model space
mat4 inv_model = inverse(MODEL_MATRIX);
VERTEX = (inv_model * vec4(final_position_world, 1.0)).xyz;

// Bend the box's original face normals into the curved frame (world space)
vec3 final_normal_world = normalize(
lateral_dir * n0.x +
radial_dir * n0.y +
tangent_dir * n0.z
);

// World normal -> model normal (so engine transforms it normally)
mat3 m = mat3(MODEL_MATRIX);
NORMAL = normalize(transpose(m) * final_normal_world);
}

void fragment() {
if (v_is_cap > 0.5) {
if (discard_start_cap && v_cap_nz < -0.9) {
discard;
}
if (discard_end_cap && v_cap_nz > 0.9) {
discard;
}
}
vec3 tex_rgb = texture(texture_albedo, UV).rgb;

// 奇数次TP模式：时间渐变效果
// 线头（v_t=1）是当前正在延伸的位置，始终白蓝色发光
// 掠过的位置随时间从白蓝色褪色为黑色
if (is_odd_tp) {
// 整段时间插值：每个像素对应“主线掠过它”的时间点。
// 旧段会在切段时冻结 segment_end_time，活动段则持续更新到 current_time。
float seg_start = segment_start_time;
float seg_end = max(segment_end_time, seg_start);
float pass_time = mix(seg_start, seg_end, clamp(v_t, 0.0, 1.0));
float time_since_created = max(current_time - pass_time, 0.0);

// 计算褪色进度（0=刚生成白蓝色，1=完全褪色黑色）
float fade_progress = clamp(time_since_created / fade_duration, 0.0, 1.0);

// 颜色：从白蓝色（线头）渐变到黑色（线尾/旧位置）
vec3 final_color = mix(trail_head_color, trail_tail_color, fade_progress);
ALBEDO = final_color * tex_rgb;

		// 发光：线头发光，随时间减弱
		float emission_factor = (1.0 - fade_progress) * odd_tp_emission_energy;
		// 发光颜色也从白蓝色过渡到蓝黑色，再随强度衰减
		vec3 emission_mix = mix(trail_head_color, trail_tail_color, fade_progress);
		EMISSION = emission_mix * emission_factor;
} else {
ALBEDO = albedo_color.rgb * tex_rgb;
if (use_emission) {
EMISSION = emission_color.rgb * emission_energy;
}
}

METALLIC = metallic;
ROUGHNESS = roughness;
}
