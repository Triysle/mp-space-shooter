extends Node3D
class_name GimballedAimIndicator

# References
var ship: Node3D

# Crosshair settings
@export var crosshair_size: int = 15
@export var crosshair_thickness: int = 2
@export var crosshair_gap: int = 5
@export var crosshair_color: Color = Color(0.3, 0.3, 0.3, 0.7)

# Gimbal settings
@export var max_gimbal_angle: float = 25.0  # Maximum angle the crosshair can move from center
@export var gimbal_smooth_factor: float = 5.0  # How smoothly the crosshair follows mouse
@export var mouse_sensitivity: float = 0.3  # How fast the crosshair moves with mouse input
@export var dead_zone_radius: float = 0.15  # Percentage of max radius where no rotation occurs

# UI elements
var _canvas_layer: CanvasLayer
var _crosshair: Control

# Tracking variables
var viewport_center: Vector2 = Vector2.ZERO
var crosshair_position: Vector2 = Vector2.ZERO
var target_crosshair_position: Vector2 = Vector2.ZERO
var normalized_aim_offset: Vector2 = Vector2.ZERO  # -1.0 to 1.0 range

func _ready():
	# Add to aim_indicator group for easy identification
	add_to_group("aim_indicator")
	
	# Get reference to parent ship
	ship = get_parent()
	
	# Set up UI elements after the scene is ready
	call_deferred("_setup_ui")

func _setup_ui():
	# Create canvas layer for UI
	_canvas_layer = CanvasLayer.new()
	add_child(_canvas_layer)
	
	# Create crosshair control
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas_layer.add_child(_crosshair)
	_crosshair.connect("draw", Callable(self, "_draw_crosshair"))
	
	# Force initial draw
	_crosshair.queue_redraw()
	
	# Initialize positions
	viewport_center = _crosshair.get_viewport_rect().size / 2
	crosshair_position = viewport_center
	target_crosshair_position = viewport_center

func _process(delta):
	# Update viewport center (for window resizing)
	if _crosshair:
		viewport_center = _crosshair.get_viewport_rect().size / 2
	
	# Calculate max offset
	var max_offset = viewport_center.y * tan(deg_to_rad(max_gimbal_angle))
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Update crosshair position
		crosshair_position = crosshair_position.lerp(target_crosshair_position, gimbal_smooth_factor * delta)
		
		# Calculate normalized aim offset
		normalized_aim_offset = Vector2.ZERO
		if max_offset > 0:
			normalized_aim_offset = (crosshair_position - viewport_center) / max_offset
	else:
		# Reset to center when mouse not captured
		target_crosshair_position = viewport_center
		crosshair_position = crosshair_position.lerp(viewport_center, gimbal_smooth_factor * delta)
		normalized_aim_offset = Vector2.ZERO
	
	# Update the crosshair
	if _crosshair:
		_crosshair.queue_redraw()

func reset_aim_position():
	target_crosshair_position = viewport_center
	crosshair_position = viewport_center
	normalized_aim_offset = Vector2.ZERO

func _input(event):
	# Only handle mouse motion when mouse is captured
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and event is InputEventMouseMotion:
		# Calculate max offset
		var max_offset = viewport_center.y * tan(deg_to_rad(max_gimbal_angle))
		
		# Update target position with mouse movement
		target_crosshair_position += event.relative * mouse_sensitivity
		
		# Enforce circular boundary
		var offset_from_center = target_crosshair_position - viewport_center
		var distance_from_center = offset_from_center.length()
		
		# Scale back to boundary if outside
		if distance_from_center > max_offset:
			offset_from_center = offset_from_center.normalized() * max_offset
			target_crosshair_position = viewport_center + offset_from_center

func _draw_crosshair():
	if not _crosshair:
		return
	
	var color = crosshair_color
	var half_thickness = crosshair_thickness / 2.0
	
	# Draw boundary indicators
	var max_offset = viewport_center.y * tan(deg_to_rad(max_gimbal_angle))
	var dead_zone_size = max_offset * dead_zone_radius
	
	# Draw dead zone circle
	if dead_zone_radius > 0.0:
		var dead_zone_color = Color(color.r, color.g, color.b, color.a * 0.3)
		draw_circle(_crosshair, viewport_center, dead_zone_size, dead_zone_color, false)
	
	# Draw maximum range circle
	var boundary_color = Color(color.r, color.g, color.b, color.a * 0.2)
	draw_circle(_crosshair, viewport_center, max_offset, boundary_color, false)
	
	# Draw center reference point
	draw_circle(_crosshair, viewport_center, 2, Color(color.r, color.g, color.b, 0.5), true)
	
	# Draw crosshair lines
	# Horizontal lines
	_crosshair.draw_rect(Rect2(
		crosshair_position.x - crosshair_size, 
		crosshair_position.y - half_thickness,
		crosshair_size - crosshair_gap, 
		crosshair_thickness
	), color)
	
	_crosshair.draw_rect(Rect2(
		crosshair_position.x + crosshair_gap, 
		crosshair_position.y - half_thickness,
		crosshair_size - crosshair_gap, 
		crosshair_thickness
	), color)
	
	# Vertical lines
	_crosshair.draw_rect(Rect2(
		crosshair_position.x - half_thickness, 
		crosshair_position.y - crosshair_size,
		crosshair_thickness, 
		crosshair_size - crosshair_gap
	), color)
	
	_crosshair.draw_rect(Rect2(
		crosshair_position.x - half_thickness, 
		crosshair_position.y + crosshair_gap,
		crosshair_thickness, 
		crosshair_size - crosshair_gap
	), color)

# Helper function to draw circles
func draw_circle(control, center: Vector2, radius: float, color: Color, filled: bool = true):
	if filled:
		control.draw_circle(center, radius, color)
	else:
		# Draw circle outline
		var points = PackedVector2Array()
		var segments = 32
		for i in range(segments + 1):
			var angle = i * TAU / segments
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		
		for i in range(segments):
			control.draw_line(points[i], points[i+1], color)

# Get aim offset for the ship
func get_aim_offset() -> Vector2:
	return normalized_aim_offset
