@icon("icons/clipmap_3d_icon.svg")
@tool
class_name Clipmap3D extends Node3D

const MAX_TEXTURE_COUNT: int = 32

## The Node3D which the terrain snaps to on the X and Z axes.
@export var follow_target: Node3D

# TODO: turn this category into a resource
@export_group("Compute")

@export var compute_shader: RDShaderFile:
	set(value):
		compute_shader = value
		if _compute_handler:
			_compute_handler.compute_shader = compute_shader

## The random number seed passed to the compute shader.
@export var compute_seed: int = 0:
	set(value):
		compute_seed = value
		if _compute_handler:
			_compute_handler.compute_seed = compute_seed

@export var texels_per_vertex := Vector2i.ONE:
	set(value):
		texels_per_vertex = value.maxi(1)
		if _compute_handler:
			_compute_handler.texels_per_vertex = texels_per_vertex
		_update_material()

@export var max_height: float = 10000.0:
	set(value):
		max_height = value
		if _mesh_handler:
			_mesh_handler.max_height = max_height

@export var texture_assets: Array[Clipmap3DTextureAsset]:
	set(value):
		if texture_assets:
			for texture_asset: Clipmap3DTextureAsset in texture_assets:
				if not texture_asset:
					continue
				if texture_asset.changed.is_connected(_on_texture_asset_changed):
					texture_asset.changed.disconnect(_on_texture_asset_changed)
		texture_assets = value
		if texture_assets:
			for texture_asset: Clipmap3DTextureAsset in texture_assets:
				if not texture_asset:
					continue
				if not texture_asset.changed.is_connected(_on_texture_asset_changed):
					texture_asset.changed.connect(_on_texture_asset_changed)
		_on_texture_asset_changed()

@export_group("Mesh", "mesh")

## World spacing between vertices. Power-of-two values are recommended.
@export_custom(PROPERTY_HINT_LINK, "suffix:m") var mesh_vertex_spacing := Vector2.ONE:
	set(value):
		mesh_vertex_spacing = value
		if _mesh_handler:
			_mesh_handler.vertex_spacing = mesh_vertex_spacing
		if _compute_handler:
			_compute_handler.vertex_spacing = mesh_vertex_spacing
		_update_material()

## The base tile size used to build the clipmap.
@export var mesh_tile_size := Vector2i(32, 32):
	set(value):
		value = value.clampi(1, 128)
		mesh_tile_size = value
		if _mesh_handler:
			_mesh_handler.tile_size = mesh_tile_size
		if _compute_handler:
			_compute_handler.tile_size = mesh_tile_size
		_update_material()

# NOTE: lower limit of 2 because of https://github.com/godotengine/godot/issues/115103
# NOTE: upper limit of 10 rings is arbitrary
## The amount of level of detail (LOD) rings that form this mesh.
@export_range(2, 10, 1) var mesh_lod_count: int = 5:
	set(value):
		mesh_lod_count = value
		if _mesh_handler:
			_mesh_handler.lod_count = mesh_lod_count
		if _compute_handler:
			_compute_handler.lod_count = mesh_lod_count
		_update_material()

@export_group("Rendering")

## The ShaderMaterial assigned to all meshes in this clipmap.
@export var material: ShaderMaterial:
	set(value):
		material = value
		if _mesh_handler:
			_mesh_handler.material_rid = material.get_rid() if material else RID()
		_update_material()

@export_flags_3d_render var render_layer: int = 1:
	set(value):
		render_layer = value
		if _mesh_handler:
			_mesh_handler.render_layer = render_layer

# NOTE: Manual enum is used since directly exporting looks different than other Godot editor properties of this type
@export_enum("Off:0", "On:1", "Double-Sided:2", "Shadows Only:3") var cast_shadows: int = 1:
	set(value):
		cast_shadows = value
		if _mesh_handler:
			_mesh_handler.cast_shadows = cast_shadows as RenderingServer.ShadowCastingSetting

@export_group("Collision", "collision")
@export_custom(PROPERTY_HINT_GROUP_ENABLE, "") var collision_enabled: bool = true:
	set(value):
		collision_enabled = value

@export var collision_mesh_radius := Vector2i(4, 4):
	set(value):
		collision_mesh_radius = value
	
## WIP: must currently only contain the follow target
@export var collision_targets: Array[PhysicsBody3D]

@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value

@export_group("Debug")

@export var generate_debug_canvas_items: bool = false

var _compute_handler: Clipmap3DComputeHandler
var _mesh_handler: Clipmap3DMeshHandler
var _collision_handler: Clipmap3DCollisionHandler

var _last_position := Vector3(INF, INF, INF)

var _textures_need_rebuild: bool = true

var _albedo_textures_rid: RID
var _albedo_remap := PackedInt32Array()
var _normal_textures_rid: RID
var _normal_remap := PackedInt32Array()

var _uv_scales := PackedVector2Array()
var _albedo_modulates := PackedColorArray()
var _roughness_offsets := PackedFloat32Array()
var _normal_depths := PackedFloat32Array()
var _flags := PackedInt32Array()

func _enter_tree() -> void:
	request_ready()

func _ready():
	if not _compute_handler:
		_compute_handler = Clipmap3DComputeHandler.new()
	
	_compute_handler.compute_shader = compute_shader
	_compute_handler.compute_seed = compute_seed
	_compute_handler.lod_count = mesh_lod_count
	_compute_handler.texels_per_vertex = texels_per_vertex
	_compute_handler.tile_size = mesh_tile_size
	_compute_handler.vertex_spacing = mesh_vertex_spacing
	
	if not _mesh_handler:
		_mesh_handler = Clipmap3DMeshHandler.new()
	
	_mesh_handler.vertex_spacing = mesh_vertex_spacing
	_mesh_handler.tile_size = mesh_tile_size
	_mesh_handler.lod_count = mesh_lod_count
	_mesh_handler.cast_shadows = cast_shadows
	_mesh_handler.render_layer = render_layer
	_mesh_handler.material_rid = material.get_rid() if material else RID()
	_mesh_handler.visible = is_visible_in_tree()
	_mesh_handler.scenario_rid = get_world_3d().scenario
	_mesh_handler.max_height = max_height
	
	_update_position() # This is already doing the update_state shit. Why not make a method that does all of it?
	
	_compute_handler.compute_finished.connect(_update_material)
	
	_compute_handler.build()
	_mesh_handler.build()
	

func _exit_tree() -> void:
	if _compute_handler:
		_compute_handler.clear()
	if _mesh_handler:
		_mesh_handler.clear()
	_clear_textures()

func _process(_delta: float) -> void:
	_update_position()

func _update_position():
	if follow_target:
		global_position.x = follow_target.global_position.x
		global_position.z = follow_target.global_position.z
	
	if global_position == _last_position:
		return
	_last_position = global_position
	
	if _compute_handler:
		_compute_handler.world_origin = Vector2(global_position.x, global_position.z)
	if _mesh_handler:
		_mesh_handler.target_position = global_position

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_WORLD:
			if _mesh_handler:
				_mesh_handler.scenario_rid = RID()
		NOTIFICATION_VISIBILITY_CHANGED:
			if _mesh_handler:
				_mesh_handler.visible = is_visible_in_tree()

## Material

func _update_material():
	if not material:
		return
	
	material.set_shader_parameter(&"_vertex_spacing", mesh_vertex_spacing)
	material.set_shader_parameter(&"_lod_count", mesh_lod_count)
	material.set_shader_parameter(&"_tile_size", mesh_tile_size)
	material.set_shader_parameter(&"_target_position", _last_position)
	material.set_shader_parameter(&"_texels_per_vertex", texels_per_vertex)
	
	material.set_shader_parameter(&"_albedo_textures", _albedo_textures_rid)
	material.set_shader_parameter(&"_albedo_remap", _albedo_remap)
	
	material.set_shader_parameter(&"_normal_textures", _normal_textures_rid)
	material.set_shader_parameter(&"_normal_remap", _normal_remap)
	
	material.set_shader_parameter(&"_uv_scales", _uv_scales)
	material.set_shader_parameter(&"_albedo_modulates", _albedo_modulates)
	material.set_shader_parameter(&"_roughness_offsets", _roughness_offsets)
	material.set_shader_parameter(&"_normal_depths", _normal_depths)
	material.set_shader_parameter(&"_flags", _flags)
	
	if _compute_handler:
		material.set_shader_parameter(&"_height_buffer", _compute_handler.get_height_buffer_rid())
		material.set_shader_parameter(&"_gradient_buffer", _compute_handler.get_gradient_buffer_rid())
		material.set_shader_parameter(&"_control_buffer", _compute_handler.get_control_buffer_rid())

## Textures

func _check_format(image: Image, format: Image.Format, size: Vector2i, has_mipmaps: bool) -> bool:
	if not image:
		return false
	
	if image.get_format() != format:
		push_error("Texture asset format mismatch.")
		return false
	if image.get_size() != size:
		push_error("Texture size mismatch.")
		return false
	if image.has_mipmaps() != has_mipmaps:
		push_error("Texture mipmaps enabled mismatch.")
		return false
	
	return true

func _rebuild_textures():
	_clear_textures()
	
	var albedo_images: Array[Image] = []
	_albedo_remap.resize(MAX_TEXTURE_COUNT)
	_albedo_remap.fill(-1)
	var albedo_format := Image.Format.FORMAT_MAX
	var albedo_size: Vector2i
	var albedo_has_mipmaps: bool
	
	var normal_images: Array[Image] = []
	_normal_remap.resize(MAX_TEXTURE_COUNT)
	_normal_remap.fill(-1)
	var normal_format := Image.Format.FORMAT_MAX
	var normal_size: Vector2i
	var normal_has_mipmaps: bool
	
	_uv_scales.resize(MAX_TEXTURE_COUNT)
	_uv_scales.fill(Clipmap3DTextureAsset.UV_SCALE_DEFAULT)
	
	_albedo_modulates.resize(MAX_TEXTURE_COUNT)
	_albedo_modulates.fill(Clipmap3DTextureAsset.ALBEDO_MODULATE_DEFAULT)
	
	_roughness_offsets.resize(MAX_TEXTURE_COUNT)
	_roughness_offsets.fill(Clipmap3DTextureAsset.ROUGHNESS_OFFSET_DEFAULT)
	
	_normal_depths.resize(MAX_TEXTURE_COUNT)
	_normal_depths.fill(Clipmap3DTextureAsset.NORMAL_DEPTH_DEFAULT)
	
	_flags.resize(MAX_TEXTURE_COUNT)
	_flags.fill(Clipmap3DTextureAsset.FLAGS_DEFAULT)
	
	for i: int in texture_assets.size():
		var texture_asset := texture_assets[i]
		if not texture_asset:
			continue
		
		_uv_scales[i] = texture_asset.uv_scale
		_albedo_modulates[i] = texture_asset.albedo_modulate
		_roughness_offsets[i] = texture_asset.roughness_offset
		_normal_depths[i] = texture_asset.normal_depth
		_flags[i] = texture_asset.flags
		
		if texture_asset.albedo_texture:
			var albedo_image := texture_asset.albedo_texture.get_image()
		
			if albedo_format == Image.Format.FORMAT_MAX:
				albedo_format = albedo_image.get_format()
				albedo_size = albedo_image.get_size()
				albedo_has_mipmaps = albedo_image.has_mipmaps()
				
				_albedo_remap[i] = albedo_images.size()
				albedo_images.append(albedo_image)
			else:
				if _check_format(albedo_image, albedo_format, albedo_size, albedo_has_mipmaps):
					_albedo_remap[i] = albedo_images.size()
					albedo_images.append(albedo_image)
		
		if texture_asset.normal_texture:
			var normal_image := texture_asset.normal_texture.get_image()
		
			if normal_format == Image.Format.FORMAT_MAX:
				normal_format = normal_image.get_format()
				normal_size = normal_image.get_size()
				normal_has_mipmaps = normal_image.has_mipmaps()
				
				_normal_remap[i] = normal_images.size()
				normal_images.append(normal_image)
			else:
				if _check_format(normal_image, normal_format, normal_size, normal_has_mipmaps):
					_normal_remap[i] = normal_images.size()
					normal_images.append(normal_image)
	
	if not albedo_images.is_empty():
		_albedo_textures_rid = RenderingServer.texture_2d_layered_create(albedo_images, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	if not normal_images.is_empty():
		_normal_textures_rid = RenderingServer.texture_2d_layered_create(normal_images, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
	
	_update_material()

func _clear_textures():
	if _albedo_textures_rid.is_valid():
		RenderingServer.free_rid(_albedo_textures_rid)
	_albedo_remap = PackedInt32Array()
	if _normal_textures_rid.is_valid():
		RenderingServer.free_rid(_normal_textures_rid)
	_normal_remap = PackedInt32Array()
	
	_uv_scales = PackedVector2Array()
	_albedo_modulates = PackedColorArray()
	_roughness_offsets = PackedFloat32Array()
	_normal_depths = PackedFloat32Array()
	_flags = PackedInt32Array()

func _on_texture_asset_changed():
	_textures_need_rebuild = true
	_rebuild_textures()
