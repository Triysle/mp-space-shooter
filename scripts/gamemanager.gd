extends Node

var score_board = {}

func _ready():
	print("GameManager initializing...")
	
	# Initialize scores for all players
	for player_id in MultiplayerManager.player_info.keys():
		score_board[player_id] = {
			"kills": 0,
			"deaths": 0
		}
	
	# Connect to signals from MultiplayerManager
	MultiplayerManager.player_connected.connect(_on_player_connected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

func connect_to_players():
	# This can be called once players are spawned
	var players = get_tree().get_nodes_in_group("player")
	print("Found ", players.size(), " players to connect to")
	
	for player in players:
		if !player.is_connected("player_died", Callable(self, "_on_player_died")):
			player.player_died.connect(_on_player_died)
		
		if !player.is_connected("player_respawned", Callable(self, "_on_player_respawned")):
			player.player_respawned.connect(_on_player_respawned)

func _on_player_connected(peer_id, player_data):
	# Add new player to scoreboard
	if !score_board.has(peer_id):
		score_board[peer_id] = {
			"kills": 0,
			"deaths": 0
		}

func _on_player_disconnected(peer_id):
	# Remove player from scoreboard
	if score_board.has(peer_id):
		score_board.erase(peer_id)

func _on_player_died(victim_id, killer_id):
	# Update scores
	if score_board.has(killer_id) and killer_id != victim_id:
		score_board[killer_id].kills += 1
	
	if score_board.has(victim_id):
		score_board[victim_id].deaths += 1
	
	# Broadcast updated scores
	if MultiplayerManager.is_server():
		rpc("update_scores", score_board)

func _on_player_respawned(player_id):
	# Player has respawned, could trigger events or powerups
	pass

@rpc("authority", "reliable")
func update_scores(new_scores):
	# Update local scoreboard
	score_board = new_scores
	
	# Update UI display
	update_score_display()

func update_score_display():
	# Update the UI with current scores
	# (in a full game, this would update a scoreboard UI element)
	pass
