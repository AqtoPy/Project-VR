extends CharacterBody3D

# Настройки движения
@export var walk_speed := 4.0
@export var sprint_speed := 8.0
@export var crouch_speed := 2.0
@export var jump_force := 5.0
@export var air_control := 0.3
@export var mouse_sensitivity := 0.002

# Эффекты камеры
@export var head_bob_frequency := 2.0
@export var head_bob_amplitude := 0.05
@export var fov_change_speed := 8.0
@export var base_fov := 75.0
@export var sprint_fov := 85.0
@export var camera_tilt_amount := 8.0
@export var tilt_smoothness := 10.0

# Физические параметры
@export var gravity_multiplier := 2.0
@export var crouch_depth := 0.5
@export var slide_threshold := 10.0

# Система шагов
@export var footstep_interval := 0.5
@export var footstep_sounds: Array[AudioStream]

@onready var camera := $Camera3D
@onready var camera_pivot := $CameraPivot
@onready var raycast := $CameraPivot/Camera3D/RayCast3D
@onready var footsteps_timer := $FootstepsTimer
@onready var audio_player := $AudioStreamPlayer3D

var current_speed := walk_speed
var is_sprinting := false
var is_crouching := false
var is_sliding := false
var normal_height := 2.0
var head_bob_time := 0.0
var current_tilt := 0.0
var gravity: float
var fall_damage_threshold := 8.0

func _ready():
    gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_multiplier
    Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
    normal_height = camera_pivot.position.y

func _input(event):
    if event is InputEventMouseMotion:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -PI/2, PI/2)
    
    if Input.is_action_just_pressed("toggle_crouch"):
        toggle_crouch()
    
    if Input.is_action_just_pressed("interact"):
        interact()

func _physics_process(delta):
    handle_movement(delta)
    handle_camera_effects(delta)
    handle_footsteps()
    apply_gravity(delta)
    move_and_slide()
    handle_fall_damage()

func handle_movement(delta):
    var input_dir = Input.get_vector("left", "right", "forward", "backward")
    var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    
    # Управление скоростью
    is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and !is_crouching
    current_speed = sprint_speed if is_sprinting else walk_speed
    current_speed = crouch_speed if is_crouching else current_speed
    
    # Плавное управление в воздухе
    var air_control_factor = air_control if !is_on_floor() else 1.0
    velocity.x = lerp(velocity.x, direction.x * current_speed * air_control_factor, delta * 10)
    velocity.z = lerp(velocity.z, direction.z * current_speed * air_control_factor, delta * 10)
    
    # Прыжок
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = jump_force
        if is_crouching:
            toggle_crouch()

func handle_camera_effects(delta):
    # Боб головы
    var velocity_magnitude = Vector2(velocity.x, velocity.z).length()
    var head_bob_intensity = clamp(velocity_magnitude / sprint_speed, 0.0, 1.0)
    
    head_bob_time += delta * velocity_magnitude * head_bob_frequency
    var head_bob_offset = Vector3(
        sin(head_bob_time * 2) * head_bob_amplitude * head_bob_intensity,
        cos(head_bob_time) * head_bob_amplitude * head_bob_intensity,
        0
    )
    
    # Наклон камеры при движении вбок
    var target_tilt = -Input.get_action_strength("right") + Input.get_action_strength("left")
    target_tilt *= deg_to_rad(camera_tilt_amount)
    current_tilt = lerp_angle(current_tilt, target_tilt, delta * tilt_smoothness)
    
    # Изменение FOV
    var target_fov = sprint_fov if is_sprinting else base_fov
    camera.fov = lerp(camera.fov, target_fov, delta * fov_change_speed)
    
    # Применение всех трансформаций камеры
    camera.transform.origin = head_bob_offset
    camera.rotation.z = current_tilt

func handle_footsteps():
    if is_on_floor() and !footsteps_timer.is_stopped() and velocity.length() > 1.0:
        if footsteps_timer.time_left <= 0:
            play_random_footstep()
            footsteps_timer.start(footstep_interval)

func play_random_footstep():
    if footstep_sounds.size() > 0:
        audio_player.stream = footstep_sounds[randi() % footstep_sounds.size()]
        audio_player.pitch_scale = randf_range(0.9, 1.1)
        audio_player.play()

func apply_gravity(delta):
    if not is_on_floor():
        velocity.y -= gravity * delta

func toggle_crouch():
    is_crouching = !is_crouching
    var target_height = normal_height - crouch_depth if is_crouching else normal_height
    var tween = create_tween().set_trans(Tween.TRANS_QUAD)
    tween.tween_property(camera_pivot, "position:y", target_height, 0.3)

func handle_fall_damage():
    if velocity.y < -fall_damage_threshold:
        # Логика урона от падения
        var fall_force = abs(velocity.y)
        if fall_force > 15:
            camera_shake(0.5, 10)
            # Здесь можно добавить урон игроку

func camera_shake(intensity: float, duration: float):
    var shake_tween = create_tween().set_loops(duration).set_trans(Tween.TRANS_SINE)
    for i in duration:
        var offset = Vector3(
            randf_range(-intensity, intensity),
            randf_range(-intensity, intensity),
            0
        )
        shake_tween.tween_property(camera, "position", offset, 0.1)
        shake_tween.tween_property(camera, "position", Vector3.ZERO, 0.1)

func interact():
    if raycast.is_colliding():
        var target = raycast.get_collider()
        if target.is_in_group("interactable"):
            # Логика взаимодействия
            pass

func _on_landed():
    var fall_speed = abs(velocity.y)
    if fall_speed > 5:
        camera_shake(fall_speed * 0.1, 5)
        play_random_footstep()

func _on_hurt(damage):
    camera_shake(damage * 0.1, 15)
    # Эффект красной рамки или другие визуальные эффекты
