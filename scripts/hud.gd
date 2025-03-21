extends CanvasLayer

@onready var health_bar = $HealthBar
@onready var energy_bar = $EnergyBar
@onready var message_label = $MessageLabel

var ship = null

func _ready():
	# Wait a frame to ensure all players are spawned
	await get_tree().process_frame
	
	# Find player ship that belongs to the local player
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		if player.is_multiplayer_authority():
			ship = player
			break
	
	if ship:
		# Connect signals
		ship.connect("health_changed", Callable(self, "_on_health_changed"))
		ship.connect("energy_changed", Callable(self, "_on_energy_changed"))
		ship.connect("player_died", Callable(self, "_on_player_died"))
		ship.connect("player_respawned", Callable(self, "_on_player_respawned"))
		
		# Initialize displays
		health_bar.max_value = ship.max_health
		health_bar.value = ship.current_health
		
		energy_bar.max_value = ship.max_energy
		energy_bar.value = ship.current_energy

func _on_health_changed(current, maximum):
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current

func _on_energy_changed(current, maximum):
	if energy_bar:
		energy_bar.max_value = maximum
		energy_bar.value = current

func _on_player_died(player_id, killer_id):
	if message_label:
		message_label.text = "You were destroyed!"
		message_label.show()

func _on_player_respawned(player_id):
	if message_label:
		message_label.text = ""
		message_label.hide()
