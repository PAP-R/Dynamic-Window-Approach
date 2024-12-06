extends CharacterBody2D
class_name Robot

@export var sensor_count: int = 16

@export var heading_weight: float = 1
@export var distance_weight: float = 1
@export var velocity_weight: float = 1

@export var sample_count: int = 1

@export var interval: float = 0.25

@export var acceleration_max: float = 1
@export var deceleration_max: float = 1
@export var velocity_max: float = 90
@export var angular_acceleration_max: float = 1
@export var angular_deceleration_max: float = 1
@export var angular_velocity_max: float = PI / 4

@export var velocity_safety:float = 1

var angular_velocity: float = 0

@onready var timer = $Timer

var goal: Vector2


var dwa_velocity: Vector2
var dwa_angular_velocity: float


var current_heading_min
var current_heading_max
var current_distance_min
var current_distance_max
var current_velocity_min
var current_velocity_max


signal finish

@onready var radius:float = sqrt($Arrow.texture.get_width() / 2 * $Arrow.texture.get_width() / 2) * sqrt($Arrow.scale.x * $Arrow.scale.y) * sqrt(scale.x * scale.y)

var sensors = []
@onready var sensor_length = radius * 2 + (velocity_max + angular_velocity_max) * interval * 200

var collision_points

@onready var mesh = $MeshInstance2D.mesh

var arrays = []


func _ready() -> void:
	arrays.resize(Mesh.ARRAY_MAX)
	
	$CollisionShape2D.shape.radius = radius / sqrt(scale.x * scale.y)
	
	timer.set_wait_time(interval)
	
	var sensor_step = 2 * PI / sensor_count
	
	for i in range(sensor_count):
		var s = preload("res://distance_sensor.tscn").instantiate()
		add_child(s)
		s.set_target_position(Vector2(sensor_length, 0))
		s.rotation = i * sensor_step
		#s.position = Vector2(cos(s.rotation), sin(s.rotation)) * radius
		sensors.append(s)


func heading_rating(v: float, w: float) -> float:
	var diff = goal - get_future_position(v, w)
	#return (Vector2(cos(get_future_rotation(w)), sin(get_future_rotation(w))).dot(diff.normalized()) + 1) / 2
	
	return PI - fmod(abs(diff.angle() - get_future_rotation(w)), PI * 2)


func distance_rating(v: float, w: float) -> float:
	if collision_points.is_empty():
		return sensor_length
		
	var future_position = get_future_position(v, w)
		
		
	var distance_min = INF
	
	
	for p in collision_points:
		var dist = future_position.distance_to(p) - (radius + v * velocity_safety)
		if dist < distance_min:
			distance_min = dist
			
	return distance_min


func velocity_rating(v: float, _w: float) -> float:
	return v


func smooth(x: float) -> float:
	return x * x


func rating(v, w) -> float:
	var hr = heading_weight * heading_rating(v, w)
	var dr = distance_weight * distance_rating(v, w) / sensor_length
	var vr = velocity_weight * velocity_rating(v, w)
	
	arrays[Mesh.ARRAY_VERTEX].push_back(get_future_position(v, w))
	arrays[Mesh.ARRAY_COLOR].push_back(Color(smooth(hr), smooth(dr), smooth(vr)))
	
	var result = smooth(hr + dr + vr)
	
	#print("rating(%f %f) = %f (h %f, d %f, v %f" % [v, w, result, hr, dr, vr])

	return result


func linear_to_2d(x: float) -> Vector2:
	return Vector2(cos(rotation), sin(rotation)) * x
	
	
func get_future_position(v: float, w: float) -> Vector2:
	return global_position + (Vector2(cos(rotation), sin(rotation)) + Vector2(cos(rotation + w), sin(rotation + w))) / 2 * v


func get_future_rotation(w: float) -> float:
	return rotation + w


func dwa():

	mesh.clear_surfaces()

	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array()
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray()

	collision_points = []
	
	if global_position.distance_to(goal) < radius:
		dwa_velocity = Vector2(0, 0)
		dwa_angular_velocity = 0
		return

	for s in sensors:
		if s.is_colliding():
			collision_points.append(s.get_collision_point())

	var v = velocity.length()
	var w = angular_velocity

	var max_v = 0
	var max_w = 0
	var max_rating = -INF


	var linear_acceleration = (acceleration_max + deceleration_max) * interval
	var angular_acceleration = (angular_acceleration_max + angular_deceleration_max) * interval

	var linear_step_size = linear_acceleration / sample_count
	var angular_step_size = angular_acceleration / sample_count

	var linear_start = max(v - deceleration_max * interval, 0)
	var linear_end = min(v + acceleration_max * interval, velocity_max) + linear_step_size / 2

	var angular_start = max(w - angular_acceleration_max * interval, -angular_velocity_max)
	var angular_end = min(w + angular_acceleration_max * interval, angular_velocity_max) + angular_step_size / 2
	
	if w > 0:
		angular_start = max(w - angular_deceleration_max * interval, -angular_velocity_max)
	elif w < 0:
		angular_end = min(w + angular_deceleration_max * interval, angular_velocity_max) + angular_step_size / 2
	
	var vt = linear_start
	
	while vt <= linear_end:
		var wt = angular_start
		while wt <= angular_end:
			if vt <= sqrt(2 * distance_rating(vt, wt) * deceleration_max) and wt <= sqrt(2 * distance_rating(vt, wt) * angular_deceleration_max):
				var result = rating(vt, wt)

				if result > max_rating:
					max_rating = result
					max_v = vt
					max_w = wt
			wt += angular_step_size
		vt += linear_step_size
		

	if max_rating == -INF or max_v == 0:
		var mean = Vector2(0, 0)
		for c in collision_points:
			mean += c
			
		mean / collision_points.size()
		var diff = mean - global_position
		if atan2(diff.y, diff.x) < 0:
			max_w = angular_start
		else:
			max_w = angular_end
	
	else:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
		

	dwa_velocity = linear_to_2d(max_v)
	dwa_angular_velocity = max_w

	#print("DWA selected [ %f ]:[ %f %f ] at [ %f / %f ][ %f ]" % [max_rating, max_v, max_w, position.x, position.y, rotation])


func set_goal(point: Vector2) -> void:
	goal = point


func _physics_process(delta: float) -> void:
	velocity = lerp(velocity, dwa_velocity, delta / interval)
	angular_velocity = lerp(angular_velocity, dwa_angular_velocity, delta / interval)
	self.rotation = fmod(self.rotation + angular_velocity * delta, 2 * PI)
	move_and_slide()
