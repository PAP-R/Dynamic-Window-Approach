extends CharacterBody2D

@export var heading_weight: float = 1
@export var distance_weight: float = 1
@export var velocity_weight: float = 1

@export var sample_count: int = 1

@export var interval: float = 0.25

@export var acceleration_max: float = 1
@export var velocity_max: float = 90
@export var angular_acceleration_max: float = 1
@export var angular_velocity_max: float = PI / 4

var angular_velocity: float = 0

@onready var timer = $Timer

@export var goal: Vector2 = Vector2(0, 0)


var current_heading_min
var current_heading_max
var current_distance_min
var current_distance_max
var current_velocity_min
var current_velocity_max


signal finish


func _ready() -> void:
	timer.set_wait_time(interval)


func heading_rating(v: float, w: float) -> float:
	var diff = goal - (global_position + linear_to_2d(v * interval))

	return 2 * PI - abs(atan2(diff.y, diff.x) - (rotation + w * interval))


func distance_rating(v: float, w: float) -> float:

	return 0


func velocity_rating(v: float, _w: float) -> float:
	return v


func smooth(x: float) -> float:
	return x


func rating(v, w) -> float:
	var hr = heading_weight * heading_rating(v, w)
	var dr = distance_weight * distance_rating(v, w)
	var vr = velocity_weight * velocity_rating(v, w)
	var result = smooth(hr + dr + vr)
	
	print("rating(%f %f) = %f (h %f, d %f, v %f" % [v, w, result, hr, dr, vr])

	return result


func linear_to_2d(x: float) -> Vector2:
	return Vector2(cos(rotation), sin(rotation)) * x


func dwa():
	var v = velocity.length()
	var w = angular_velocity

	var max_v = 0
	var max_w = 0
	var max_rating = 0


	for vti in range(-sample_count, sample_count + 1):
		var vt = v + (vti / float(sample_count)) * acceleration_max * interval
		if abs(vt) > velocity_max:
			continue

		for wti in range(-sample_count, sample_count + 1):
			var wt = w + (wti / float(sample_count)) * angular_acceleration_max * interval
			if abs(wt) > angular_velocity_max:
				continue

			var result = rating(vt, wt)

			if result > max_rating:
				max_rating = result
				max_v = vt
				max_w = wt


	velocity = linear_to_2d(max_v)
	angular_velocity = max_w

	print("DWA selected [ %f ]:[ %f %f ] at [ %f / %f ][ %f ]" % [max_rating, max_v, max_w, position.x, position.y, rotation])


func set_goal(point: Vector2) -> void:
	goal = point


func _physics_process(delta: float) -> void:
	self.rotation = fmod(self.rotation + angular_velocity * delta, 2 * PI)
	move_and_slide()
