"""
Força bruta, O(N): escolhe a interseção válida mais próxima da bola de taco.
"""
function find_contact_bruteforce(balls::Vector{Ball}, cue_index::Int)::Union{Contact, Nothing}
    cue = balls[cue_index]
    best_s = Inf
    best_point = Vec2(0.0, 0.0)
    best_index = 0
    n = length(balls)

    @inbounds for i in 1:n
        i == cue_index && continue
        valid, s, _, point = intersect_trajectories(cue, balls[i])
        if valid && s < best_s
            best_s = s
            best_point = point
            best_index = i
        end
    end

    best_index == 0 && return nothing
    speed = hypot(cue.velocity[1], cue.velocity[2])
    return Contact(best_point, best_index, best_s * speed)
end

"""
Força bruta da tacada, O(N): primeiro círculo atingido pelo raio da bola branca.
`direction` é o ângulo do taco, ou a velocidade quando a bola já está em movimento.
"""
function find_shot_contact(balls::Vector{Ball}, cue_index::Int, direction::Vec2)::Union{Contact, Nothing}
    cue = balls[cue_index]
    best_s = Inf
    best_point = Vec2(0.0, 0.0)
    best_index = 0
    n = length(balls)

    @inbounds for i in 1:n
        i == cue_index && continue
        other = balls[i]
        valid, s, point = ray_circle_hit(cue.position, direction, other.position, cue.radius + other.radius)
        if valid && s < best_s
            best_s = s
            best_point = point
            best_index = i
        end
    end

    best_index == 0 && return nothing
    return Contact(best_point, best_index, best_s)
end
