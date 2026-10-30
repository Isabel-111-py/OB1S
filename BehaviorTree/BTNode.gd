# BTNode.gd
class_name BTNode
extends Node

enum Status { SUCCESS, FAILURE, RUNNING }

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	return Status.FAILURE
