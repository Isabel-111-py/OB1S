# BehaviorTree.gd
class_name BehaviorTree
extends Node

@export var actor: Node2D
var blackboard: Dictionary = {}

func _ready() -> void:
	if actor == null:
		actor = get_parent() as Node2D
	
	buscar_jugador()

func buscar_jugador() -> void:
	var player = get_tree().get_first_node_in_group("Player")
	if player:
		blackboard["player"] = player

func _physics_process(_delta: float) -> void:
	if not blackboard.has("player") or not is_instance_valid(blackboard["player"]):
		buscar_jugador()

	if get_child_count() > 0:
		var root_node = get_child(0) as BTNode
		if root_node:
			root_node.tick(actor, blackboard)
