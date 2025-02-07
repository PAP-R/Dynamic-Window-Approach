extends RayCast2D
class_name DistanceSensor

@onready var line = $Line

func _physics_process(delta: float) -> void:
	if self.is_colliding():
		line.global_position = get_collision_point()
		line.scale.y = global_position.distance_to(line.global_position) / 2
		line.show()
	else :
		line.hide()
