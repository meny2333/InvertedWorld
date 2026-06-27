@tool
extends Node3D


@export var source_meshes: Array[MeshInstance3D]
@export var target_container: Node3D
@export var path_name_prefix: String = "GeneratedPath_"

@export_group("Tube/Road Settings")
@export var scan_radius: float = 1.5
@export var min_step_distance: float = 0.5

@export_group("Advanced")
@export var max_jump_distance: float = 10.0
@export var auto_adjust_endpoint: bool = true

@export_tool_button("Generate Centerlines", "_generate_centerline")
var action = _generate_centerline


var _path_index: int = 0



func _generate_centerline():
    if source_meshes.is_empty():
        printerr("请设置 Source Meshes。")
        return

    if not target_container:
        target_container = self

    _clear_previous_paths()

    var unique_points = {}
    for mesh_instance in source_meshes:
        if not is_instance_valid(mesh_instance) or not mesh_instance.mesh:
            continue

        var mesh = mesh_instance.mesh
        var xform = mesh_instance.global_transform

        for i in range(mesh.get_surface_count()):
            var arrays = mesh.surface_get_arrays(i)
            if not arrays:
                continue

            var raw_verts = arrays[Mesh.ARRAY_VERTEX]
            for v in raw_verts:
                var world_pos = xform * v
                var snap_pos = world_pos.snapped(Vector3(0.01, 0.01, 0.01))
                if not unique_points.has(snap_pos):
                    unique_points[snap_pos] = world_pos

    var pool = unique_points.values()

    if pool.is_empty():
        printerr("未找到顶点。")
        return

    var all_vertices = pool.duplicate()

    var start_vertex
    var best_score = - INF
    for v in pool:
        var score = v.z - v.x
        if score > best_score:
            best_score = score
            start_vertex = v

    if start_vertex == null:
        printerr("无法找到起点。")
        return

    var current_seed = start_vertex
    var iterations = 0
    var max_iterations = pool.size() + 200

    var current_path: Path3D = null
    var current_curve: Curve3D = null
    var paths_created_count = 0

    print("开始生成中心线... 去重后顶点数: ", pool.size())
    print("全局起点: ", start_vertex)

    while not pool.is_empty() and iterations < max_iterations:
        iterations += 1

        if not is_instance_valid(current_path):
            var new_path_data = _create_new_path()
            current_path = new_path_data.path
            current_curve = new_path_data.curve
            paths_created_count += 1
            print("\n--- 开始创建第 %d 条路径 ---" % paths_created_count)
            current_curve.add_point(current_path.to_local(current_seed))

        var cluster = []
        var remaining_pool = []
        var cluster_sum = Vector3.ZERO
        var radius_sq = scan_radius * scan_radius

        for p in pool:
            if p.distance_squared_to(current_seed) <= radius_sq:
                cluster.append(p)
                cluster_sum += p
            else:
                remaining_pool.append(p)

        if cluster.is_empty():
            if not remaining_pool.is_empty():
                var rescue_dist_sq = INF
                var rescue_seed = null

                for p in remaining_pool:
                    var d = p.distance_squared_to(current_seed)
                    if d < rescue_dist_sq:
                        rescue_dist_sq = d
                        rescue_seed = p

                if rescue_seed != null:
                    print("当前种子点 %s 搁浅，强制跳转到最近点 %s" % [current_seed, rescue_seed])
                    _adjust_final_endpoint(current_curve, current_path, all_vertices)
                    current_path = null
                    current_curve = null
                    current_seed = rescue_seed
                    pool = remaining_pool
                    continue

            break

        else:
            var centroid_global = cluster_sum / cluster.size()
            var last_pt_global = current_path.to_global(current_curve.get_point_position(current_curve.get_point_count() - 1))
            if last_pt_global.distance_to(centroid_global) >= min_step_distance:
                current_curve.add_point(current_path.to_local(centroid_global))

            pool = remaining_pool

            if pool.is_empty():
                break

            var nearest_dist_sq = INF
            var next_seed = null
            for p in pool:
                var d = p.distance_squared_to(centroid_global)
                if d < nearest_dist_sq:
                    nearest_dist_sq = d
                    next_seed = p

            if next_seed != null:
                var jump_distance = sqrt(nearest_dist_sq)
                if jump_distance > max_jump_distance:
                    print("路径在重心 %s 后断开。到下一个最近点的距离: %.2f (超过阈值 %.2f)" % [centroid_global.snapped(Vector3.ONE * 0.1), jump_distance, max_jump_distance])
                    _adjust_final_endpoint(current_curve, current_path, all_vertices)

                    current_path = null
                    current_curve = null
                    current_seed = next_seed
                else:
                    current_seed = next_seed
            else:
                break

    if is_instance_valid(current_path) and current_curve.get_point_count() > 0:
        _adjust_final_endpoint(current_curve, current_path, all_vertices)

    print("\n中心线生成完成！")
    print("总共创建了 %d 条路径。" % paths_created_count)
    print("总迭代次数: ", iterations)


func _create_new_path() -> Dictionary:
    _path_index += 1
    var new_path = Path3D.new()
    new_path.name = path_name_prefix + str(_path_index)

    var new_curve = Curve3D.new()
    new_path.curve = new_curve

    target_container.add_child(new_path)
    if Engine.is_editor_hint():
        new_path.owner = get_tree().edited_scene_root

    return {"path": new_path, "curve": new_curve}


func _clear_previous_paths():
    _path_index = 0
    for i in range(target_container.get_child_count() - 1, -1, -1):
        var child = target_container.get_child(i)
        if child is Path3D and child.name.begins_with(path_name_prefix):
            child.queue_free()


func _adjust_final_endpoint(curve: Curve3D, path: Path3D, all_verts: Array):
    if not auto_adjust_endpoint or curve.get_point_count() == 0:
        return

    var target_point = null
    var target_score = - INF
    for v in all_verts:
        var score = v.x - v.z
        if score > target_score:
            target_score = score
            target_point = v

    if target_point:
        var last_point_local = curve.get_point_position(curve.get_point_count() - 1)
        var last_point_global = path.to_global(last_point_local)
        var dist_to_target = last_point_global.distance_to(target_point)

        if dist_to_target > min_step_distance:
            if dist_to_target > scan_radius * 2.0:
                curve.add_point(path.to_local(target_point))
                print("路径 '%s' 已添加终点到X最大Z最小位置。" % path.name)
            else:
                curve.set_point_position(curve.get_point_count() - 1, path.to_local(target_point))
                print("路径 '%s' 已移动终点到X最大Z最小位置。" % path.name)

    curve.emit_signal("changed")
