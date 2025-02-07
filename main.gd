extends Node2D

var robots = []

@onready var goal = $Goal

func _ready() -> void:
	var scaling = get_viewport_rect().size / 1000
	
	for child in get_children():
		child.position *= scaling
			
		if child is Robot:
			robots.append(child)
			child.set_goal(goal.global_position)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		goal.global_position = event.position
		
		for r in robots:
			r.set_goal(event.position)
