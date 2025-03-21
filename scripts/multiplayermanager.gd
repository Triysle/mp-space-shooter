extends Node

# Networking configuration
const DEFAULT_PORT = 28960
const MAX_CLIENTS = 8

# Player management
var player_info = {}
var my_player_id = 0
var players_ready = []  # Track which players have loaded the scene

# Server information
var server_info = {
	"name": "Default Server",
	"max_players": MAX_CLIENTS
}

# Signals
signal player_connected(peer_id, player_data)
signal player_disconnected(peer_id)
signal server_disconnected
signal connection_failed
signal connection_succeeded
signal game_started
signal game_ended

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# Host a new server
func create_server(server_name, max_players):
	server_info.name = server_name
	server_info.max_players = max_players
	
	# Create the server peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, max_players)
	
	if error != OK:
		print("Failed to create server: ", error)
		return error
	
	# Set multiplayer peer
	multiplayer.multiplayer_peer = peer
	
	# Register ourselves (server) with peer id 1
	my_player_id = 1
	player_info[1] = {
		"name": "Server Host",
		"color": Color(1, 0, 0)  # Red for the host
	}
	
	print("Server created successfully on port ", DEFAULT_PORT)
	return OK

# Connect to an existing server
func join_server(ip_address):
	# Create client peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, DEFAULT_PORT)
	
	if error != OK:
		print("Failed to create client: ", error)
		return error
	
	# Set multiplayer peer
	multiplayer.multiplayer_peer = peer
	
	print("Connecting to server at ", ip_address, ":", DEFAULT_PORT)
	return OK

# Disconnect from server or shut down server
func disconnect_from_server():
	multiplayer.multiplayer_peer = null
	player_info.clear()
	players_ready.clear()
	
	print("Disconnected from server")

# Check if we're acting as the server
func is_server():
	return multiplayer.is_server()

# Get the local player ID
func get_my_id():
	return my_player_id

# Register player information
func register_player(player_name, player_color):
	if multiplayer.multiplayer_peer != null:
		my_player_id = multiplayer.get_unique_id()
		var player_data = {
			"name": player_name,
			"color": player_color
		}
		
		# If we're the server, update directly
		if is_server():
			player_info[my_player_id] = player_data
		else:
			# Otherwise, send info to server
			rpc_id(1, "register_player_info", my_player_id, player_data)

# NEW: Notify server that the client has loaded the multiplayer scene
func client_ready():
	# Only relevant for clients connecting to a server
	if !is_server() and multiplayer.multiplayer_peer != null:
		# Notify the server we're ready
		rpc_id(1, "register_client_ready", multiplayer.get_unique_id())
		print("Notified server that client is ready")

# Start the game on all clients
func start_game():
	print("Starting game...")
	rpc("begin_game")

# RPC functions (called across the network)
@rpc("any_peer", "reliable")
func register_player_info(peer_id, player_data):
	# Only the server should handle this directly
	if !is_server():
		return
	
	# Update player info
	player_info[peer_id] = player_data
	
	# Inform all clients about the new player
	rpc("update_player_list", player_info)
	
	# Let all existing players know about this new player
	emit_signal("player_connected", peer_id, player_data)

# NEW: Register that a client is ready for gameplay
@rpc("any_peer", "reliable")
func register_client_ready(peer_id):
	# Only the server processes this
	if !is_server():
		return
	
	print("Client " + str(peer_id) + " is ready")
	
	# Mark this player as ready
	if !players_ready.has(peer_id):
		players_ready.append(peer_id)
	
	# Spawn this player for everyone
	spawn_player(peer_id)
	
	# Spawn all existing players for this new client
	for existing_peer in player_info.keys():
		if existing_peer != peer_id:  # Don't spawn the player's own character again
			# Send this only to the new client
			rpc_id(peer_id, "spawn_player_character", existing_peer, player_info[existing_peer])

@rpc("authority", "reliable")
func update_player_list(updated_player_info):
	# Update our local player info
	player_info = updated_player_info

@rpc("authority", "reliable")
func begin_game():
	print("Game starting...")
	# Just emit the signal - scene change is handled directly in lobby.gd
	emit_signal("game_started")

# Spawn a player on all clients
func spawn_player(peer_id):
	print("Attempting to spawn player with ID: ", peer_id)
	
	# Check if player info exists
	if !player_info.has(peer_id):
		print("ERROR: No player info for peer ID: ", peer_id)
		return
	
	# Check if client is ready (if not server or self)
	if is_server() and peer_id != 1 and !players_ready.has(peer_id):
		print("Client " + str(peer_id) + " is not ready yet, delaying spawn")
		return
		
	print("Player info found, sending spawn RPC")
	
	# Let all clients know to spawn this player
	rpc("spawn_player_character", peer_id, player_info[peer_id])

@rpc("authority", "reliable")
func spawn_player_character(peer_id, player_data):
	print("Network: Spawning player: " + str(peer_id))
	
	# Skip if player already exists
	var players_node = get_node_or_null("/root/MultiplayerLevel/Players")
	if players_node and players_node.has_node(str(peer_id)):
		print("Player " + str(peer_id) + " already exists, not spawning again")
		return
	
	# Check if the scene is loaded
	var level = get_node_or_null("/root/MultiplayerLevel")
	if level == null:
		print("ERROR: MultiplayerLevel scene not found! Can't spawn player.")
		return
	
	# Create player character
	var player_scene = load("res://scenes/ship.tscn")
	if player_scene == null:
		print("ERROR: Failed to load ship scene!")
		return
		
	var player_instance = player_scene.instantiate()
	
	# Set player properties
	player_instance.name = str(peer_id)
	player_instance.player_id = peer_id
	
	# Configure network settings
	player_instance.set_multiplayer_authority(peer_id)
	
	# Apply player customization
	if player_data.has("color"):
		apply_player_color(player_instance, player_data.color)
	
	# Find spawn point
	var spawn_pos = Vector3(0, 0, 0)  # Default position
	var spawn_points = level.get_node_or_null("SpawnPoints")
	if spawn_points and spawn_points.get_child_count() > 0:
		var spawn_index = randi() % spawn_points.get_child_count()
		var spawn_point = spawn_points.get_child(spawn_index)
		spawn_pos = spawn_point.global_position
	
	# Set position
	player_instance.global_position = spawn_pos
	
	# Add to Players container
	level.get_node("Players").add_child(player_instance)
	print("Player " + str(peer_id) + " added to scene")
	
	# Setup player
	if player_instance.has_method("setup_player"):
		player_instance.setup_player()

@rpc("authority", "reliable")
func remove_player_character(peer_id):
	# Remove the player character
	var level = get_node_or_null("/root/MultiplayerLevel")
	if level and level.has_node("Players/" + str(peer_id)):
		level.get_node("Players/" + str(peer_id)).queue_free()

# Helper function to apply color to a player ship
func apply_player_color(player_instance, color):
	if player_instance.has_node("MeshInstance3D"):
		var mesh = player_instance.get_node("MeshInstance3D")
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.5
		mesh.material_override = material

# Network event handlers
func _on_player_connected(peer_id):
	print("Player connected: ", peer_id)
	
	# If we're the server, send the existing player list to the new player
	if is_server():
		rpc_id(peer_id, "update_player_list", player_info)

func _on_player_disconnected(peer_id):
	print("Player disconnected: ", peer_id)
	
	# Clean up player information
	if player_info.has(peer_id):
		player_info.erase(peer_id)
	
	if players_ready.has(peer_id):
		players_ready.erase(peer_id)
	
	# Inform other systems
	emit_signal("player_disconnected", peer_id)
	
	# Update all clients with new player list
	if is_server():
		rpc("update_player_list", player_info)
		
		# Remove character from all clients
		remove_player(peer_id)

# Remove a player from all clients
func remove_player(peer_id):
	print("Removing player: " + str(peer_id))
	
	# Let all clients know to remove this player's character
	rpc("remove_player_character", peer_id)

func _on_connected_to_server():
	print("Successfully connected to server")
	my_player_id = multiplayer.get_unique_id()
	emit_signal("connection_succeeded")

func _on_connection_failed():
	print("Connection failed")
	multiplayer.multiplayer_peer = null
	emit_signal("connection_failed")

func _on_server_disconnected():
	print("Server disconnected")
	multiplayer.multiplayer_peer = null
	player_info.clear()
	players_ready.clear()
	emit_signal("server_disconnected")
