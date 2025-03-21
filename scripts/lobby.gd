extends Control

@onready var ip_text_edit = $VBoxContainer/ServerIP
@onready var name_text_edit = $VBoxContainer/PlayerName
@onready var status_label = $VBoxContainer/StatusLabel
@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var local_ip_label = $VBoxContainer/LocalIPLabel  # Add this to your scene

func _ready():
	# Connect signals from multiplayer manager
	MultiplayerManager.connection_succeeded.connect(_on_connection_success)
	MultiplayerManager.connection_failed.connect(_on_connection_failed)
	MultiplayerManager.player_connected.connect(_on_player_connected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
	MultiplayerManager.server_disconnected.connect(_on_server_disconnected)
	MultiplayerManager.game_started.connect(_on_game_started)
	
	# Set default name and IP
	name_text_edit.text = "Player" + str(randi() % 1000)
	ip_text_edit.text = "127.0.0.1"  # Default to localhost
	
	# Display local IP address for easier network testing
	var ip = get_local_ip()
	if local_ip_label:
		local_ip_label.text = "Your IP: " + ip
	
	# Update status
	status_label.text = "Not connected"

func get_local_ip() -> String:
	# Get the local IP address
	var ip = "127.0.0.1"  # Default fallback
	
	# Try to get the actual IP
	for address in IP.get_local_addresses():
		# Filter out loopback and IPv6 addresses
		if not address.begins_with("127.") and not address.contains(":"):
			ip = address
			break
	
	return ip

func _on_host_button_pressed():
	# Disable buttons during connection
	host_button.disabled = true
	join_button.disabled = true
	
	# Update status
	status_label.text = "Creating server..."
	
	# Create server
	var result = MultiplayerManager.create_server("Game Server", 8)
	
	if result == OK:
		# Register player info
		_register_player_info()
		
		# Update status
		status_label.text = "Server created. Starting game..."
		
		# Slight delay before starting the game
		await get_tree().create_timer(0.5).timeout
		
		# Start the game
		MultiplayerManager.start_game()
		
		# Change scene
		get_tree().change_scene_to_file("res://scenes/multiplayer_level.tscn")
	else:
		# Re-enable buttons
		host_button.disabled = false
		join_button.disabled = false
		
		# Show error
		status_label.text = "Failed to create server (Error: " + str(result) + ")"

func _on_join_button_pressed():
	# Get server IP
	var ip = ip_text_edit.text
	
	if ip.is_empty():
		status_label.text = "Please enter a server IP"
		return
	
	# Disable buttons during connection
	host_button.disabled = true
	join_button.disabled = true
	
	# Update status
	status_label.text = "Connecting to " + ip + "..."
	
	# Connect to server
	var result = MultiplayerManager.join_server(ip)
	
	if result == OK:
		# Listen for connection success
		await MultiplayerManager.connection_succeeded
		
		# Register our player info
		_register_player_info()
		
		# Update status
		status_label.text = "Connected to server. Loading game..."
		
		# Wait a moment
		await get_tree().create_timer(0.5).timeout
		
		# Load the game scene (client will notify server when ready)
		get_tree().change_scene_to_file("res://scenes/multiplayer_level.tscn")
	else:
		# Re-enable buttons
		host_button.disabled = false
		join_button.disabled = false
		
		# Show error
		status_label.text = "Failed to connect to server"

func _register_player_info():
	# Get player name
	var player_name = name_text_edit.text
	
	if player_name.is_empty():
		player_name = "Player" + str(randi() % 1000)
	
	# Generate random color
	var player_color = Color(randf(), randf(), randf())
	
	# Register with multiplayer manager
	MultiplayerManager.register_player(player_name, player_color)

# Signal handlers
func _on_connection_success():
	status_label.text = "Connected to server"
	
	# Register our player info
	_register_player_info()

func _on_connection_failed():
	status_label.text = "Connection failed"
	
	# Re-enable buttons
	host_button.disabled = false
	join_button.disabled = false

func _on_player_connected(peer_id, player_data):
	status_label.text = "Player joined: " + player_data.name
	
	# Update player list display if you have one
	# update_player_list()

func _on_player_disconnected(peer_id):
	status_label.text = "Player left: " + str(peer_id)
	
	# Update player list display if you have one
	# update_player_list()

func _on_server_disconnected():
	status_label.text = "Disconnected from server"
	
	# Re-enable buttons
	host_button.disabled = false
	join_button.disabled = false

func _on_game_started():
	# Scene change is handled in the host/join functions
	pass
