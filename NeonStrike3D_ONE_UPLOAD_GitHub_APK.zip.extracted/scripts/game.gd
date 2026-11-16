extends Node3D

const ARENA := 24.0
const SPEED := 9.0
const PLAYER_MAX_HP := 100
const SOLDIER_PATH := "res://assets/soldier.glb"
const RIFLE_PATH := "res://assets/AK-74_pack.fbx"
const DRONE_PATH := "res://assets/drone.fbx"
var player: CharacterBody3D
var camera: Camera3D
var enemies: Array[CharacterBody3D] = []
var enemy_hp := {}
var enemy_cooldown := {}
var enemy_is_drone := {}
var soldier_scene: PackedScene
var rifle_scene: PackedScene
var drone_scene: PackedScene
var pickups: Array[Node3D] = []
var pickup_kind := {}
var muzzle_flash: MeshInstance3D
var muzzle_clock := 0.0
var hit_marker: Label
var hit_clock := 0.0
var move_touch := -1
var aim_touch := -1
var move_origin := Vector2.ZERO
var move_vector := Vector2.ZERO
var look_delta := Vector2.ZERO
var fire_pressed := false
var hp := PLAYER_MAX_HP
var ammo := 30
var kills := 0
var wave := 1
var alive := true
var spawn_clock := 0.0
var shot_clock := 0.0
var reload_clock := 0.0
var damage_flash := 0.0
var hud: Label
var status: Label
var crosshair: Label
var joystick: Control
var stick: ColorRect
var fire_button: Button
var reload_button: Button
var restart_button: Button
var canvas: CanvasLayer
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	soldier_scene = _load_scene(SOLDIER_PATH)
	rifle_scene = _load_scene(RIFLE_PATH)
	drone_scene = _load_scene(DRONE_PATH)
	_build_world()
	_build_player()
	_build_ui()
	_spawn_wave()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# Each model is optional: if an FBX import fails, the procedural visuals remain playable.
func _load_scene(path: String) -> PackedScene:
	var resource := ResourceLoader.load(path)
	if resource is PackedScene:
		return resource as PackedScene
	push_warning("Optional 3D asset could not load: " + path)
	return null

# Fit arbitrarily scaled user-provided FBX scenes to a practical in-game size.
# This inspects meshes after instancing, including their nested transforms.
func _fit_model(model: Node3D, target_span: float) -> void:
	var parts := model.find_children("*", "MeshInstance3D", true, false)
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var reverse := model.global_transform.affine_inverse()
	for part in parts:
		var part_mesh := part as MeshInstance3D
		if part_mesh.mesh == null:
			continue
		var bounds := part_mesh.get_aabb()
		var xf := reverse * part_mesh.global_transform
		for c in range(8):
			var corner := bounds.position + Vector3(
				bounds.size.x if (c & 1) != 0 else 0.0,
				bounds.size.y if (c & 2) != 0 else 0.0,
				bounds.size.z if (c & 4) != 0 else 0.0
			)
			var vertex := xf * corner
			low = low.min(vertex)
			high = high.max(vertex)
	if low.x == INF:
		return
	var span := high - low
	var maximum := maxf(maxf(span.x, span.y), span.z)
	if maximum < 0.001:
		return
	var factor := target_span / maximum
	model.scale *= factor
	model.position -= (low + high) * 0.5 * factor

func _model(parent: Node3D, model_scene: PackedScene, target_span: float) -> bool:
	if model_scene == null:
		return false
	var instance := model_scene.instantiate() as Node3D
	if instance == null:
		return false
	parent.add_child(instance)
	_fit_model(instance, target_span)
	return true

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, collision := true) -> Node3D:
	var root: Node3D = StaticBody3D.new() if collision else Node3D.new()
	parent.add_child(root)
	root.position = pos
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.48
	mesh.material_override = material
	root.add_child(mesh)
	if collision:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		root.add_child(col)
	return root

func _build_world() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("11182a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8798b4")
	env.ambient_light_energy = 0.65
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, -15)
	sun.light_energy = 1.5
	add_child(sun)
	_box(self, Vector3(0, -0.6, 0), Vector3(ARENA * 2, 1, ARENA * 2), Color("26334a"))
	for i in range(-4, 5):
		_box(self, Vector3(i * 5, -0.07, 0), Vector3(0.08, 0.02, ARENA * 2), Color("345d77"), false)
		_box(self, Vector3(0, -0.06, i * 5), Vector3(ARENA * 2, 0.02, 0.08), Color("345d77"), false)
	for side in [-1, 1]:
		_box(self, Vector3(side * ARENA, 2.5, 0), Vector3(1, 5, ARENA * 2), Color("14243b"))
		_box(self, Vector3(0, 2.5, side * ARENA), Vector3(ARENA * 2, 5, 1), Color("14243b"))
	# Landing-pad markings and modular cover give the space a battle-arena look.
	for z in [-16, -8, 8, 16]:
		_box(self, Vector3(0, -0.035, z), Vector3(ARENA * 2 - 1, 0.02, 0.10), Color("11a8c7"), false)
	for x in [-16, -8, 8, 16]:
		_box(self, Vector3(x, -0.03, 0), Vector3(0.10, 0.02, ARENA * 2 - 1), Color("115e88"), false)
	for i in range(18):
		var p := Vector3(rng.randf_range(-19, 19), 0, rng.randf_range(-19, 19))
		if p.length() < 7:
			continue
		var height := rng.randf_range(1.5, 4.0)
		_box(self, Vector3(p.x, height / 2.0, p.z), Vector3(rng.randf_range(1.5, 3.0), height, rng.randf_range(1.5, 3.0)), Color("354961"))

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 1.2, 0)
	add_child(player)
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.8
	col.shape = shape
	player.add_child(col)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0.5, 0)
	camera.current = true
	camera.fov = 74
	player.add_child(camera)
	# Use the supplied AK-74 scene as the held weapon where its FBX imports.
	var weapon_mount := Node3D.new()
	weapon_mount.position = Vector3(0.43, -0.38, -0.85)
	weapon_mount.rotation_degrees = Vector3(-9, -6, -5)
	camera.add_child(weapon_mount)
	if not _model(weapon_mount, rifle_scene, 0.82):
		_box(weapon_mount, Vector3.ZERO, Vector3(0.18, 0.20, 0.75), Color("1b2331"), false)
		_box(weapon_mount, Vector3(0, 0.04, -0.5), Vector3(0.08, 0.08, 0.40), Color("00d7d9"), false)
	muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.15
	flash_mesh.height = 0.30
	muzzle_flash.mesh = flash_mesh
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color("ffe89a")
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.emission_enabled = true
	flash_mat.emission = Color("ff9b23")
	flash_mat.emission_energy_multiplier = 2.0
	muzzle_flash.material_override = flash_mat
	muzzle_flash.position = Vector3(0.43, -0.31, -1.28)
	muzzle_flash.visible = false
	camera.add_child(muzzle_flash)

func _build_ui() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(ui)
	hud = Label.new()
	hud.position = Vector2(22, 14)
	hud.add_theme_font_size_override("font_size", 26)
	hud.add_theme_color_override("font_color", Color("c5ffff"))
	ui.add_child(hud)
	status = Label.new()
	status.anchor_left = 0.5
	status.anchor_right = 0.5
	status.offset_left = -280
	status.offset_right = 280
	status.offset_top = 20
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 25)
	status.add_theme_color_override("font_color", Color("ffe38a"))
	ui.add_child(status)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.add_theme_color_override("font_color", Color("00f4f1"))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(crosshair)
	hit_marker = Label.new()
	hit_marker.text = "X"
	hit_marker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hit_marker.offset_left += 22
	hit_marker.offset_right += 22
	hit_marker.add_theme_font_size_override("font_size", 24)
	hit_marker.add_theme_color_override("font_color", Color("ff6a75"))
	hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hit_marker.visible = false
	ui.add_child(hit_marker)
	joystick = Control.new()
	joystick.anchor_top = 1
	joystick.anchor_bottom = 1
	joystick.offset_left = 35
	joystick.offset_top = -195
	joystick.offset_right = 205
	joystick.offset_bottom = -25
	joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(joystick)
	var ring := ColorRect.new()
	ring.color = Color(0.07, 0.78, 0.86, 0.18)
	ring.position = Vector2(0, 0)
	ring.size = Vector2(170, 170)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick.add_child(ring)
	stick = ColorRect.new()
	stick.color = Color(0.12, 0.95, 0.96, 0.68)
	stick.position = Vector2(62, 62)
	stick.size = Vector2(46, 46)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick.add_child(stick)
	fire_button = _button(ui, "FIRE", -165, -170, 135, 125)
	fire_button.button_down.connect(func(): fire_pressed = true)
	fire_button.button_up.connect(func(): fire_pressed = false)
	reload_button = _button(ui, "RELOAD", -315, -100, 135, 60)
	reload_button.pressed.connect(_reload)
	restart_button = _button(ui, "RESTART", -145, -320, 220, 65)
	restart_button.anchor_left = 0.5
	restart_button.anchor_right = 0.5
	restart_button.visible = false
	restart_button.pressed.connect(func(): get_tree().reload_current_scene())
	_refresh_hud()

func _button(ui: Control, title: String, left: float, top: float, width: float, height: float) -> Button:
	var b := Button.new()
	b.text = title
	b.anchor_left = 1
	b.anchor_right = 1
	b.anchor_top = 1
	b.anchor_bottom = 1
	b.offset_left = left
	b.offset_top = top
	b.offset_right = left + width
	b.offset_bottom = top + height
	b.add_theme_font_size_override("font_size", 23)
	ui.add_child(b)
	return b

func _spawn_wave() -> void:
	if not alive:
		return
	status.text = "WAVE %d  |  ELIMINATE HOSTILES" % wave
	for i in range(min(3 + wave * 2, 18)):
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy := CharacterBody3D.new()
	var is_drone := wave >= 2 and rng.randf() < minf(0.10 * wave, 0.40)
	var angle := rng.randf_range(0, TAU)
	var radius := rng.randf_range(12, 20)
	enemy.position = Vector3(cos(angle) * radius, 3.0 if is_drone else 1.0, sin(angle) * radius)
	add_child(enemy)
	var col := CollisionShape3D.new()
	if is_drone:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.62
		col.shape = sphere
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.55
		capsule.height = 2
		col.shape = capsule
	enemy.add_child(col)
	var appearance := Node3D.new()
	enemy.add_child(appearance)
	if is_drone:
		if not _model(appearance, drone_scene, 1.5):
			_box(appearance, Vector3.ZERO, Vector3(1.2, 0.32, 0.65), Color("f84c77"), false)
			_box(appearance, Vector3.ZERO, Vector3(2.0, 0.12, 0.15), Color("16b8d0"), false)
	else:
		if not _model(appearance, soldier_scene, 2.0):
			var mesh := MeshInstance3D.new()
			var body := CapsuleMesh.new()
			body.radius = 0.55
			body.height = 2
			mesh.mesh = body
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("ff506d")
			mesh.material_override = mat
			appearance.add_child(mesh)
	# A bright marker keeps realistic dark soldier meshes readable on mobile.
	var marker := MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.20
	marker_mesh.bottom_radius = 0.20
	marker_mesh.height = 0.08
	marker.mesh = marker_mesh
	marker.position = Vector3(0, 1.24 if not is_drone else 0.82, 0)
	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color("ff365f")
	marker_mat.emission_enabled = true
	marker_mat.emission = Color("ff365f")
	marker_mat.emission_energy_multiplier = 2.0
	marker.material_override = marker_mat
	enemy.add_child(marker)
	enemies.append(enemy)
	enemy_is_drone[enemy] = is_drone
	enemy_hp[enemy] = 4 if is_drone else 3
	enemy_cooldown[enemy] = rng.randf_range(0.5, 2.0)

func _spawn_pickup(at: Vector3) -> void:
	if rng.randf() > 0.30:
		return
	var kind := "health" if rng.randf() < 0.35 else "ammo"
	var pickup := Node3D.new()
	pickup.position = Vector3(at.x, 0.45, at.z)
	add_child(pickup)
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.65, 0.65, 0.65)
	box.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("40e1ac") if kind == "health" else Color("ffdc76")
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.8
	box.material_override = material
	pickup.add_child(box)
	pickups.append(pickup)
	pickup_kind[pickup] = kind

func _update_pickups(delta: float) -> void:
	for pickup in pickups.duplicate():
		if not is_instance_valid(pickup):
			continue
		pickup.rotate_y(delta * 1.5)
		if player.global_position.distance_to(pickup.global_position) < 1.55:
			if pickup_kind[pickup] == "health":
				hp = mini(PLAYER_MAX_HP, hp + 25)
				status.text = "HEALTH +25"
			else:
				ammo = mini(30, ammo + 15)
				status.text = "AMMO +15"
			pickup_kind.erase(pickup)
			pickups.erase(pickup)
			pickup.queue_free()
			_refresh_hud()

func _physics_process(delta: float) -> void:
	if not alive:
		return
	shot_clock = maxf(0, shot_clock - delta)
	muzzle_clock = maxf(0.0, muzzle_clock - delta)
	muzzle_flash.visible = muzzle_clock > 0.0
	hit_clock = maxf(0.0, hit_clock - delta)
	hit_marker.visible = hit_clock > 0.0
	_update_pickups(delta)
	if reload_clock > 0:
		reload_clock -= delta
		if reload_clock <= 0:
			ammo = 30
			_refresh_hud()
	if fire_pressed or Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_shoot()
	var input_dir := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if move_vector.length() > 0.1:
		input_dir = move_vector
	input_dir = input_dir.limit_length(1)
	var direction := player.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)
	player.velocity.x = direction.x * SPEED
	player.velocity.z = direction.z * SPEED
	player.velocity.y -= 24.0 * delta
	player.move_and_slide()
	player.position.x = clampf(player.position.x, -22.5, 22.5)
	player.position.z = clampf(player.position.z, -22.5, 22.5)
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		var towards := player.global_position - enemy.global_position
		towards.y = 0
		var dist := towards.length()
		var flying: bool = enemy_is_drone.get(enemy, false)
		if flying:
			var hover_height := 3.1 + sin(Time.get_ticks_msec() * 0.0018 + enemy.get_instance_id() % 10) * 0.24
			var fly_speed := minf(4.5, 2.2 + wave * 0.18)
			var travel := towards.normalized() * fly_speed if dist > 3.8 else Vector3.ZERO
			enemy.velocity = Vector3(travel.x, clampf((hover_height - enemy.position.y) * 3.5, -1.5, 1.5), travel.z)
			enemy.move_and_slide()
		elif dist > 2.4:
			var direction_enemy := towards.normalized()
			enemy.velocity = Vector3(direction_enemy.x * (2.3 + wave * 0.25), -1, direction_enemy.z * (2.3 + wave * 0.25))
			enemy.move_and_slide()
		else:
			enemy.velocity = Vector3.ZERO
		enemy.look_at(Vector3(player.global_position.x, enemy.global_position.y, player.global_position.z), Vector3.UP)
		enemy_cooldown[enemy] -= delta
		if dist < 13 and enemy_cooldown[enemy] <= 0:
			enemy_cooldown[enemy] = rng.randf_range(1.4, 2.4)
			_take_damage(6 if dist > 3 else 12)
	if enemies.is_empty():
		wave += 1
		_spawn_wave()

func _shoot() -> void:
	if shot_clock > 0 or reload_clock > 0:
		return
	if ammo <= 0:
		_reload()
		return
	shot_clock = 0.14
	muzzle_clock = 0.06
	ammo -= 1
	_refresh_hud()
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 80
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit and enemy_hp.has(hit.collider):
		var target: CharacterBody3D = hit.collider
		hit_clock = 0.15
		enemy_hp[target] -= 1
		if enemy_hp[target] <= 0:
			_spawn_pickup(target.position)
			enemy_hp.erase(target)
			enemy_cooldown.erase(target)
			enemy_is_drone.erase(target)
			enemies.erase(target)
			target.queue_free()
			kills += 1
			_refresh_hud()

func _reload() -> void:
	if reload_clock <= 0 and ammo < 30:
		reload_clock = 1.3
		status.text = "RELOADING..."

func _take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	_refresh_hud()
	if hp == 0:
		alive = false
		fire_pressed = false
		status.text = "GAME OVER  |  %d KILLS" % kills
		restart_button.visible = true

func _refresh_hud() -> void:
	if hud:
		hud.text = "NEON STRIKE  |  HP %d  |  AMMO %d/30  |  KILLS %d  |  WAVE %d" % [hp, ammo, kills, wave]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var screen_width := get_viewport().get_visible_rect().size.x
		if touch.pressed:
			if touch.position.x < screen_width * 0.42 and move_touch == -1:
				move_touch = touch.index
				move_origin = touch.position
			elif aim_touch == -1:
				aim_touch = touch.index
		else:
			if touch.index == move_touch:
				move_touch = -1
				move_vector = Vector2.ZERO
				stick.position = Vector2(62, 62)
			if touch.index == aim_touch:
				aim_touch = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == move_touch:
			move_vector = ((drag.position - move_origin) / 75.0).limit_length(1)
			stick.position = Vector2(62, 62) + move_vector * 48
		elif drag.index == aim_touch:
			_look(drag.relative)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look((event as InputEventMouseMotion).relative)

func _look(relative: Vector2) -> void:
	player.rotate_y(-relative.x * 0.0035)
	camera.rotation.x = clampf(camera.rotation.x - relative.y * 0.0035, -1.25, 1.25)
