extends CharacterBody2D
class_name Robot

@export var sensor_count: int = 16

@export var heading_weight: float = 1
@export var distance_weight: float = 1
@export var velocity_weight: float = 1

@export var sample_count: int = 1

@export var interval: float = 0.25

@export var prediction_interval: float = 0.05

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


func heading_rating(points) -> Array[float]:
	var result: Array[float] = []
	var min_result = INF
	var max_result = -INF

	for p in points:
		var diff = goal - get_future_position(p[0], p[1])
		var r = PI - fmod(abs(diff.angle() - get_future_rotation(p[1])), PI * 2)

		result.append(r)
		if r < min_result:
			min_result = r
		if r > max_result:
			max_result = r

	min_result /= max_result
	for i in range(result.size()):
		result[i] = result[i] / max_result - min_result
	
	return result


func distance_rating(points) -> Array[float]:
	var result: Array[float] = []

	if collision_points.is_empty():
		result.resize(points.size())
		result.fill(1)
		return result

	var min_result = INF
	var max_result = -INF
		
	for p in points:
		var future_position = get_future_position(p[0], p[1])
		
		var distance_min = INF
	
		for c in collision_points:
			var dist = future_position.distance_to(c) - (radius + p[0] * velocity_safety)
			if dist < distance_min:
				distance_min = dist
		
		result.append(distance_min)
		if distance_min < min_result:
			min_result = distance_min
		if distance_min > max_result:
			max_result = distance_min
		

	min_result /= max_result
	for i in range(result.size()):
		result[i] = result[i] / max_result - min_result

	return result


func velocity_rating(points) -> Array[float]:
	var result: Array[float] = []

	var min_result = INF
	var max_result = -INF

	for p in points:
		result.append(p[0])
		if p[0] < min_result:
			min_result = p[0]
		if p[0] > max_result:
			max_result = p[0]

		
	min_result /= max_result
	for i in range(result.size()):
		result[i] = result[i] / max_result - min_result

	return result


func rating(points) -> Array[float]:
	var hrList = heading_rating(points)
	var drList = distance_rating(points)
	var vrList = velocity_rating(points)

	var max_result = -INF
	var max_v = 0
	var max_w = 0


	for i in range(points.size()):
		#if not (points[i][0] <= sqrt(2 * drList[i] * deceleration_max) and points[i][1] <= sqrt(2 * drList[i] * angular_deceleration_max)):
			#continue
		
		var hr = heading_weight * hrList[i]
		var dr = distance_weight * drList[i]
		var vr = velocity_weight * vrList[i]
	
		arrays[Mesh.ARRAY_VERTEX].push_back(get_future_position(points[i][0], points[i][1]))
		arrays[Mesh.ARRAY_COLOR].push_back(Color(hrList[i], drList[i], vrList[i]))
	
		var result = hr + dr + vr
		if result > max_result:
			max_result = result
			max_v = points[i][0]
			max_w = points[i][1]

	return Array([max_result, max_v, max_w], TYPE_FLOAT, "", null)


func linear_to_2d(x: float) -> Vector2:
	return Vector2(cos(rotation), sin(rotation)) * x
	
	
func get_future_position(v: float, w: float) -> Vector2:
	#var pos = global_position
#
	#if v == 0:
		#return pos
#
	#var t = 0
#
	#if w == 0:
		#while t < interval:
			#pos += v * Vector2(cos(rotation) * interval, sin(rotation) * interval)
			#t += prediction_interval
		#
	#else:
		#while t < interval:
			#pos += (v / w) * Vector2(cos(rotation) - cos(rotation + w * t), sin(rotation) - sin(rotation + w * t)) * prediction_interval
			#t += prediction_interval
	return global_position + (Vector2(cos(rotation), sin(rotation)) + Vector2(cos(rotation + w), sin(rotation + w))) / 2 * v

	#return pos


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
	
	var points = []
	
	while vt <= linear_end:
		var wt = angular_start
		while wt <= angular_end:
			points.append([vt, wt])
			wt += angular_step_size
		vt += linear_step_size
		
	var result = rating(points)
	var max_rating = result[0]
	var max_v = result[1]
	var max_w = result[2]

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
