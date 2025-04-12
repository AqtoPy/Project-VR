extends RigidBody3D

# Настройки
@export var max_health := 150.0
@export var hit_response_force := 12.0
@export var bone_mass := 4.0
@export var damage_multiplier := 0.8
@export var blood_particles: GPUParticles3D
@export var hit_sounds: Array[AudioStream]
@export var death_sounds: Array[AudioStream]

@onready var health: float = max_health
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var hurt_box: Area3D = $HurtBox
@onready var skeleton: Skeleton3D = $Armature/Skeleton3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var death_timer: Timer = $DeathTimer

var is_alive := true
var initial_position: Vector3
var hit_accumulator := Vector3.ZERO

func _ready():
    initial_position = global_transform.origin
    setup_physics()
    hurt_box.body_entered.connect(_on_hurt_box_body_entered)

func setup_physics():
    mass = bone_mass
    physics_material_override = PhysicsMaterial.new()
    physics_material_override.bounce = 0.25
    physics_material_override.friction = 0.8

func _physics_process(delta):
    if is_alive && health > 0:
        # Плавное возвращение в исходное положение
        if global_transform.origin.distance_to(initial_position) > 0.5:
            var direction = (initial_position - global_transform.origin).normalized()
            apply_central_force(direction * 50.0 * delta)

func take_damage(damage: float, hit_point: Vector3, impact_force: Vector3):
    if !is_alive: return
    
    # Применение урона
    health -= damage * damage_multiplier
    health = clamp(health, 0, max_health)
    
    # Эффекты попадания
    spawn_blood(hit_point)
    play_random_sound(hit_sounds)
    apply_hit_force(impact_force, hit_point)
    
    # Реакция на смерть
    if health <= 0:
        die()

func apply_hit_force(force: Vector3, hit_point: Vector3):
    var force_vector = force.normalized() * hit_response_force
    var hit_position = hit_point - global_transform.origin
    
    # Применяем силу к конкретной кости
    var closest_bone = skeleton.find_closest_bone(hit_point)
    if closest_bone != -1:
        var bone_global_pos = skeleton.get_bone_global_pose(closest_bone).origin
        apply_impulse(force_vector, bone_global_pos - global_transform.origin)
    
    # Эффект "мягкого тела"
    hit_accumulator += force * 0.1
    add_constant_force(hit_accumulator)

func die():
    is_alive = false
    play_random_sound(death_sounds)
    enable_ragdoll()
    death_timer.start(randf_range(15.0, 25.0))

func enable_ragdoll():
    collision_shape.disabled = true
    set_collision_layer_value(1, false)
    set_collision_mask_value(1, false)
    
    # Активация физических костей
    for child in get_children():
        if child is PhysicalBone3D:
            child.set_simulate_physics(true)

func spawn_blood(position: Vector3):
    if blood_particles:
        var new_blood = blood_particles.duplicate()
        get_parent().add_child(new_blood)
        new_blood.global_transform.origin = position
        new_blood.emitting = true
        await get_tree().create_timer(2.0).timeout
        new_blood.queue_free()

func play_random_sound(sounds: Array):
    if sounds.size() > 0:
        audio_player.stream = sounds[randi() % sounds.size()]
        audio_player.pitch_scale = randf_range(0.9, 1.1)
        audio_player.play()

func _on_hurt_box_body_entered(body):
    if body.has_method("get_attack_info") && is_alive:
        var attack_info = body.get_attack_info()
        take_damage(
            attack_info.damage,
            attack_info.position,
            attack_info.direction * attack_info.force
        )

func _on_death_timer_timeout():
    queue_free()
