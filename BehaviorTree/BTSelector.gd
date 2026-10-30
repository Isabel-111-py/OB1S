# BTSelector.gd
class_name BTSelector
extends BTNode

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	for child in get_children():
		if child is BTNode:
			var status = child.tick(actor, blackboard)
			if status != Status.FAILURE:
				return status
	return Status.FAILURE
