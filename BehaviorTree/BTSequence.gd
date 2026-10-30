# BTSequence.gd
class_name BTSequence
extends BTNode

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	for child in get_children():
		if child is BTNode:
			var status = child.tick(actor, blackboard)
			if status != Status.SUCCESS:
				return status
	return Status.SUCCESS
