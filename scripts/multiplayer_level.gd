extends Node3D

func _ready():
	print("Multiplayer level loaded successfully")
	
	# Ensure HUD is present
	if !has_node("HUD"):
		var hud_scene = load("res://scenes/hud.tscn")
		if hud_scene:
			var hud_instance = hud_scene.instantiate()
			add_child(hud_instance)
	
	# First, spawn our local player
	call_deferred("_spawn_local_player")

func _spawn_local_player():
	await get_tree().create_timer(0.5).timeout
	
	var local_player_id = MultiplayerManager.get_my_id()
	print("Spawning local player with ID: " + str(local_player_id))
	
	# Create player instance
	var player_scene = load("res://scenes/ship.tscn")
	if player_scene == null:
		print("ERROR: Failed to load ship scene!")
		return
		
	var player_instance = player_scene.instantiate()
	
	# Set player properties
	player_instance.name = str(local_player_id)
	player_instance.player_id = local_player_id
	
	# Configure network authority
	player_instance.set_multiplayer_authority(local_player_id)
	
	# Apply player color
	var color = Color(1, 0, 0) # Default red color
	if MultiplayerManager.player_info.has(local_player_id) and MultiplayerManager.player_info[local_player_id].has("color"):
		color = MultiplayerManager.player_info[local_player_id]["color"]
	
	# Apply color to ship
	if player_instance.has_node("MeshInstance3D"):
		var mesh = player_instance.get_node("MeshInstance3D")
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
	
	# First add to scene tree
	$Players.add_child(player_instance, true)
	
	# Find spawn point and set position after adding to scene
	var spawn_pos = Vector3(0, 0, 0)
	var spawn_points = get_node_or_null("SpawnPoints")
	if spawn_points and spawn_points.get_child_count() > 0:
		var spawn_index = randi() % spawn_points.get_child_count()
		var spawn_point = spawn_points.get_child(spawn_index)
		spawn_pos = spawn_point.global_position
		
		# Now it's safe to set the position
		player_instance.global_position = spawn_pos
	
	# Setup player
	if player_instance.has_method("setup_player"):
		player_instance.setup_player()
	
	# Now notify the server that we're ready to receive other players
	if !MultiplayerManager.is_server():
		# A short delay to ensure everything is ready
		await get_tree().create_timer(0.2).timeout
		MultiplayerManager.client_ready()
		print("Notified server that this client is ready")
	else:
		# For the server, make sure the GameManager connects to players
		if Gamemanager.has_method("connect_to_players"):
			await get_tree().create_timer(0.2).timeout
			Gamemanager.connect_to_players()
