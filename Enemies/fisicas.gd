extends CharacterBody2D
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	move_and_slide()


func _on_area_2d_body_entered(_body: Node2D) -> void:
	pass # Replace with function body.


func _on_area_2d_body_exited(_body: Node2D) -> void:
	pass # Replace with function body.


func _on_area_2d_input_event(_viewport: Node, _event: InputEvent, _shape_idx: int) -> void:
	pass # Replace with function body.
