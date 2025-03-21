extends CharacterBody3D

# Movement Parameters
@export var base_speed: float = 50.0           # Standard maximum speed
@export var base_acceleration: float = 15.0    # Base rate of velocity change
@export var boost_acceleration_factor: float = 2.0  # Acceleration multiplier during boost
@export var turn_smoothness: float = 10.0      # Rotation responsiveness
@export var mouse_sensitivity: float = 0.3     # Precision of aiming controls

# Gimbal aiming system parameters
@export var aim_follow_speed: float = 100.0    # Maximum rotation speed (degrees per second)

# Physics Settings
@export var max_drift_speed: float = 50.0      # Maximum velocity
@export var inertia_factor: float = 0.002      # Natural velocity decay rate

# Energy System
@export var max_energy: float = 100.0          # Maximum energy capacity
@export var energy_regen_rate: float = 15.0    # Energy regeneration per second
@export var boost_energy_cost: float = 25.0    # Energy consumption per second while boosting
@export var min_boost_energy: float = 10.0     # Minimum energy required to activate boost

# Weapon System
@export var laser_scene: PackedScene         # Reference to the laser scene
@export var laser_spawn_point: NodePath      # Path to the spawn point node
@export var fire_rate: float = 5.0           # Shots per second
@export var laser_energy_cost: float = 5.0   # Energy cost per shot

# Health System
@export var max_health: float = 100.0
var current_health: float = max_health
var is_alive: bool = true
var respawn_timer: float = 0.0
@export var respawn_time: float = 3.0

# Network configuration
@export var player_id: int = 1  # Default to player 1 for testing
var is_network_master: bool = false

# Movement State Tracking
var velocity_vector := Vector3.ZERO        # Actual movement vector
var yaw := 0.0                             # Current horizontal rotation
var pitch := 0.0                           # Current vertical rotation

# Ship Systems Status
var mouse_captured := true                 # Is mouse look active?
var boost_active := false                  # Is boost mode currently on?
var dampers_active := true                 # Are inertial dampeners active?
var current_energy: float = max_energy     # Current energy level

# Weapon state tracking
var can_fire: bool = true
var fire_cooldown: float = 0.0
var laser_spawn_node: Node3D

# Gimbal system reference
var aim_indicator = null                   # Reference to the aim indicator

# Signals
signal energy_changed(current, maximum)    # Signal to notify UI of energy changes
signal health_changed(current, maximum)
signal player_died(player_id, killer_id)
signal player_respawned(player_id)

# Optimization Caches
var current_acceleration: float            # Dynamic acceleration rate
var input_dir := Vector3.ZERO

# Debug variables
var debug_last_position = Vector3.ZERO
var debug_inputs_received = false

func _ready():
	# Initialize ship state
	velocity = Vector3.ZERO
	current_acceleration = base_acceleration
	current_energy = max_energy
	
	# Find aim indicator
	if has_node("GimballedAimIndicator"):
		aim_indicator = $GimballedAimIndicator
	
	# Set up laser spawn point
	if laser_spawn_point:
		laser_spawn_node = get_node(laser_spawn_point)
	elif has_node("LaserSpawnPoint"):
		laser_spawn_node = $LaserSpawnPoint
	else:
		laser_spawn_node = $Marker3D
	
	# Emit initial energy level
	emit_signal("energy_changed", current_energy, max_energy)
	emit_signal("health_changed", current_health, max_health)
	
	# Set network authority
	is_network_master = is_multiplayer_authority()
	
	# Make sure we're in the player group
	if not is_in_group("player"):
		add_to_group("player")
	
	print("Ship initialized for player: " + str(player_id))

# Called after being spawned by the MultiplayerManager
func setup_player():
	# Ensure visibility
	visible = true
	
	# Make sure controls are active
	is_alive = true
	
	# Make our camera current if we're the controlling player
	if has_node("Camera3D"):
		$Camera3D.current = is_network_master
	
	# If we are the network master, ensure mouse is captured for controls
	if is_network_master:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
		# Reset aim indicator if available
		if aim_indicator and aim_indicator.has_method("reset_aim_position"):
			aim_indicator.reset_aim_position()

func _physics_process(delta):
	# Skip processing if player is dead and waiting to respawn
	if !is_alive:
		handle_respawn(delta)
		return
	
	# Only process inputs if we're the controller of this ship
	if is_network_master:
		process_inputs(delta)
		debug_inputs_received = true
	
	# Handle energy regeneration and consumption
	handle_energy(delta)
	
	# Handle weapon systems
	handle_weapons(delta)
	
	# Calculate and apply ship movement physics
	handle_ship_physics(delta)
	
	# Apply rotation based on aim
	if aim_indicator:
		apply_aim_rotation(delta)
	
		# Add a simple banking effect based on aiming
		var aim_offset = aim_indicator.get_aim_offset()
		var bank_angle = -aim_offset.x * 5.0
		var pitch_angle = -aim_offset.y * 3.0
		
		# Apply banking to the ship model if it exists
		if has_node("MeshInstance3D"):
			$MeshInstance3D.rotation.z = lerp_angle($MeshInstance3D.rotation.z, deg_to_rad(bank_angle), 10.0 * delta)
			$MeshInstance3D.rotation.x = lerp_angle($MeshInstance3D.rotation.x, deg_to_rad(pitch_angle), 8.0 * delta)
	
	# Debug movement
	if global_position != debug_last_position:
		debug_last_position = global_position
	
	# Debug regular heartbeat
	if Engine.get_process_frames() % 60 == 0:  # Once per second at 60 FPS
		if is_network_master:
			print("Ship heartbeat - Position: ", global_position, " Inputs received: ", debug_inputs_received)

func process_inputs(_delta):
	# Boost Mechanics
	var boost_input_pressed = Input.is_action_pressed("boost")
	
	# Only allow boost if we have enough energy
	if boost_input_pressed and current_energy >= min_boost_energy:
		if !boost_active:
			boost_active = true
			current_acceleration = base_acceleration * boost_acceleration_factor
	elif boost_active:
		# Deactivate boost if released or energy depleted
		boost_active = false
		current_acceleration = base_acceleration
	
	# Toggle dampers
	if Input.is_action_just_pressed("toggle_dampers"):
		dampers_active = !dampers_active
		print("Dampers toggled: ", dampers_active)
	
	# Mouse Capture Toggle
	if Input.is_action_just_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		if mouse_captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			if aim_indicator:
				aim_indicator.reset_aim_position()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("Mouse capture toggled: ", mouse_captured)
	
	# Fire weapon
	if Input.is_action_pressed("fire") and can_fire and current_energy >= laser_energy_cost:
		fire_laser()
		print("Fire input received")

# Weapon System Management
func handle_weapons(delta):
	# Handle weapon cooldown
	if !can_fire:
		fire_cooldown -= delta
		if fire_cooldown <= 0:
			can_fire = true

func fire_laser():
	# Only allow the owner to actually fire
	if !is_network_master:
		return
	
	# Skip if missing components
	if not laser_scene or not laser_spawn_node:
		print("Cannot fire laser - missing scene or spawn point!")
		return
		
	# Energy check
	if current_energy < laser_energy_cost:
		print("Not enough energy to fire laser!")
		return
		
	# Consume energy
	current_energy -= laser_energy_cost
	emit_signal("energy_changed", current_energy, max_energy)
	
	# Get spawn position
	var spawn_pos = laser_spawn_node.global_position
	
	# Get aim direction
	var direction = -global_transform.basis.z  # Default forward direction
	
	# Use aim indicator for precise aiming if available
	if aim_indicator:
		var camera = find_camera()
		if camera:
			var aim_offset = aim_indicator.get_aim_offset()
			
			# Use camera basis for precise aiming
			var camera_basis = camera.global_transform.basis
			
			# Calculate rotations
			var horizontal_rotation = -aim_offset.x * deg_to_rad(25)
			var vertical_rotation = -aim_offset.y * deg_to_rad(25)
			
			# Apply rotations to direction
			var horizontal_rot = Basis(camera_basis.y, horizontal_rotation)
			var vertical_rot = Basis(camera_basis.x, vertical_rotation)
			direction = vertical_rot * horizontal_rot * (-camera_basis.z)
			direction = direction.normalized()
	
	# Create laser
	var laser = laser_scene.instantiate()
	get_tree().root.add_child(laser)
	
	# Initialize the laser
	laser.init(spawn_pos, direction, player_id)
	
	# Play sound if available
	if has_node("LaserSound"):
		$LaserSound.play()
	
	# Set cooldown
	can_fire = false
	fire_cooldown = 1.0 / fire_rate
	
	print("Laser fired by player ", player_id)

# Helper to calculate laser direction
func calculate_laser_direction() -> Vector3:
	var direction = -global_transform.basis.z  # Default forward direction
	
	# Use aim indicator for precise aiming if available
	if aim_indicator:
		var camera = find_camera()
		if camera:
			var aim_offset = aim_indicator.get_aim_offset()
			
			# Use camera basis for precise aiming
			var camera_basis = camera.global_transform.basis
			
			# Calculate rotations
			var horizontal_rotation = -aim_offset.x * deg_to_rad(25)
			var vertical_rotation = -aim_offset.y * deg_to_rad(25)
			
			# Apply rotations to direction
			var horizontal_rot = Basis(camera_basis.y, horizontal_rotation)
			var vertical_rot = Basis(camera_basis.x, vertical_rotation)
			direction = vertical_rot * horizontal_rot * (-camera_basis.z)
			direction = direction.normalized()
	
	return direction

# Find the camera
func find_camera() -> Camera3D:
	# Check for child camera
	for child in get_children():
		if child is Camera3D:
			return child
	
	# Return viewport camera
	return get_viewport().get_camera_3d()

# Energy Management
func handle_energy(delta):
	var previous_energy = current_energy
	
	# Consume energy while boosting
	if boost_active:
		current_energy = max(current_energy - boost_energy_cost * delta, 0.0)
		
		# Disable boost if energy depleted
		if current_energy < min_boost_energy:
			boost_active = false
			current_acceleration = base_acceleration
	else:
		# Regenerate energy
		current_energy = min(current_energy + energy_regen_rate * delta, max_energy)
	
	# Update UI if energy changed significantly
	if abs(previous_energy - current_energy) > 0.01:
		emit_signal("energy_changed", current_energy, max_energy)

# Ship Physics
func handle_ship_physics(delta):
	# Get input direction
	input_dir = get_input_direction()
	
	# Set target speed
	var target_speed = max_drift_speed
	if boost_active:
		target_speed *= boost_acceleration_factor
	
	if dampers_active:
		# Dampers On: Smooth velocity control
		var target_velocity = input_dir * target_speed
		velocity_vector = velocity_vector.move_toward(target_velocity, current_acceleration * delta)
	else:
		# Dampers Off: More direct control
		if input_dir != Vector3.ZERO:
			velocity_vector += input_dir * current_acceleration * delta
			
			# Cap maximum speed
			if velocity_vector.length() > target_speed:
				velocity_vector = velocity_vector.normalized() * target_speed
	
	# Apply velocity
	velocity = velocity_vector
	move_and_slide()

# Input Direction
func get_input_direction() -> Vector3:
	# Reset input direction
	input_dir = Vector3.ZERO
	
	# Get directional inputs
	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.z += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y -= 1.0
	
	# Debug input
	if input_dir != Vector3.ZERO:
		print("Input direction: ", input_dir)
	
	# Normalize input
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
	
	# Transform input to ship's local space
	return global_transform.basis * input_dir

# Aim Rotation
func apply_aim_rotation(delta):
	# Get the normalized aim offset
	var aim_offset = aim_indicator.get_aim_offset()
	
	# Calculate offset length
	var offset_length = aim_offset.length()
	
	# Apply dead zone
	if offset_length < aim_indicator.dead_zone_radius:
		return
	
	# Calculate effective offset past dead zone
	var normalized_distance = (offset_length - aim_indicator.dead_zone_radius) / (1.0 - aim_indicator.dead_zone_radius)
	normalized_distance = clamp(normalized_distance, 0.0, 1.0)
	normalized_distance = normalized_distance * normalized_distance  # Apply curve for better control
	
	# Calculate rotation rate
	var rotation_rate = normalized_distance * aim_follow_speed
	
	# Apply rotation based on direction
	if offset_length > 0.01:
		var normalized_aim = aim_offset / offset_length
		
		# Calculate rotation amounts
		var yaw_change = -normalized_aim.x * rotation_rate * delta
		var pitch_change = -normalized_aim.y * rotation_rate * delta
		
		# Apply rotation
		yaw += yaw_change
		pitch += pitch_change
		
		# Clamp pitch
		pitch = clamp(pitch, -80, 80)
	
	# Apply rotation
	rotation_degrees = Vector3(pitch, yaw, 0)

# Handle mouse input
func _input(event):
	# Only process mouse motion when captured and no aim indicator
	if is_network_master and mouse_captured and event is InputEventMouseMotion and not aim_indicator:
		var mouse_delta = event.relative
		yaw -= mouse_delta.x * mouse_sensitivity
		pitch -= mouse_delta.y * mouse_sensitivity
		pitch = clamp(pitch, -80, 80)
		print("Mouse motion processed")

# RPC for taking damage
@rpc("any_peer", "call_local")
func take_damage_rpc(amount, attacker_id):
	take_damage(amount, attacker_id)

# Update damage function to use RPC
func take_damage(amount, attacker_id):
	# If we're the authority for this ship, process the damage
	if is_network_master:
		# Apply damage locally
		current_health -= amount
		emit_signal("health_changed", current_health, max_health)
		
		# Check for death
		if current_health <= 0:
			die(attacker_id)
	else:
		# If we're not the authority, send damage to the authority
		rpc_id(int(name), "take_damage_rpc", amount, attacker_id)

# Handle player death
# Update die function for networking
func die(killer_id):
	is_alive = false
	respawn_timer = respawn_time
	
	# Hide ship
	visible = false
	
	# Disable collision
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true
	
	# Stop all movement
	velocity_vector = Vector3.ZERO
	velocity = Vector3.ZERO
	
	# Emit death signal and notify all clients
	emit_signal("player_died", player_id, killer_id)
	rpc("sync_death", killer_id)
	
	print("Player ", player_id, " died, killed by ", killer_id)

# RPC to sync death state
@rpc("any_peer", "call_local")
func sync_death(killer_id):
	is_alive = false
	respawn_timer = respawn_time
	visible = false
	
	# Disable collision
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = true
	
	# Stop all movement if this is our player
	if is_network_master:
		velocity_vector = Vector3.ZERO
		velocity = Vector3.ZERO

# Handle respawn timer and logic
func handle_respawn(delta):
	respawn_timer -= delta
	if respawn_timer <= 0:
		respawn()

# Respawn the player
# Update respawn for networking
func respawn():
	# Only network master handles actual respawn
	if is_network_master:
		# Reset health and state
		current_health = max_health
		is_alive = true
		
		# Reset position (in multiplayer this would use spawn points)
		var spawn_points = get_node_or_null("/root/MultiplayerLevel/SpawnPoints")
		if spawn_points and spawn_points.get_child_count() > 0:
			var spawn_point = spawn_points.get_child(randi() % spawn_points.get_child_count())
			global_position = spawn_point.global_position
		else:
			global_position = Vector3.ZERO
		
		# Reset velocity and rotation
		velocity_vector = Vector3.ZERO
		velocity = Vector3.ZERO
		
		# Notify all clients
		rpc("sync_respawn", global_position)
		print("Player ", player_id, " respawning")
	
	# Make visible again
	visible = true
	
	# Enable collision
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = false
	
	# Emit respawn signal
	emit_signal("player_respawned", player_id)
	emit_signal("health_changed", current_health, max_health)

# RPC to sync respawn state
@rpc("any_peer", "call_local")
func sync_respawn(spawn_position):
	# Update state
	is_alive = true
	visible = true
	
	# Set position
	global_position = spawn_position
	
	# Enable collision
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = false
	
	print("Player ", player_id, " synchronized respawn at position ", spawn_position)

# RPC to spawn laser on all clients
@rpc("any_peer", "call_local")
func spawn_laser(spawn_pos, direction, shooter_id):
	# Create laser
	var laser = laser_scene.instantiate()
	get_tree().root.add_child(laser)
	
	# Initialize the laser
	laser.init(spawn_pos, direction, shooter_id)
	
	# Play sound if available
	if has_node("LaserSound") and shooter_id == player_id:
		$LaserSound.play()
	
	# Set cooldown if we're the shooter
	if shooter_id == player_id and is_network_master:
		can_fire = false
		fire_cooldown = 1.0 / fire_rate
