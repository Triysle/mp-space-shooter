extends Node3D

# Laser Properties
@export var speed: float = 1000.0        # Speed in units per second
@export var max_distance: float = 1000.0  # Maximum travel distance
@export var damage: int = 10              # Damage inflicted on targets

# State tracking
var distance_traveled: float = 0.0
var direction: Vector3 = Vector3.ZERO
var origin_point: Vector3 = Vector3.ZERO
var shooter_id: int = 0                   # ID of the player who fired this laser

# Visual effect properties
@export var laser_color: Color = Color(1.0, 0.125, 0.125, 0.47)

func _ready():
	# Set up visual appearance if needed
	if has_node("MeshInstance3D"):
		var mesh_instance = $MeshInstance3D
		if mesh_instance.get_mesh() and mesh_instance.get_mesh().get_surface_count() > 0:
			var material = mesh_instance.get_mesh().surface_get_material(0)
			if material is StandardMaterial3D:
				material.albedo_color = laser_color

func _process(delta):
	# Move the laser
	var movement = direction * speed * delta
	global_position += movement
	
	# Track distance
	distance_traveled += movement.length()
	
	# Destroy if maximum distance reached
	if distance_traveled >= max_distance:
		queue_free()

# Initialize the laser with a direction and origin point
func init(pos: Vector3, dir: Vector3, _shooter_id: int = 0):
	global_position = pos
	origin_point = pos
	direction = dir.normalized()
	shooter_id = _shooter_id
	
	# Point in the correct direction
	look_at(pos + dir, Vector3.UP)

# Called when laser hits something
func _on_area_entered(area):
	handle_collision(area.get_parent())

func _on_body_entered(body):
	handle_collision(body)

func handle_collision(object):
	# Check if we hit a player
	if object.is_in_group("player") and object.has_method("take_damage"):
		object.take_damage(damage, shooter_id)
	
	# Destroy the laser on any collision
	queue_free()
