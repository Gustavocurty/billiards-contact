"""
Força bruta, O(N): menor s ≥ 0 em que a bola fantasma encosta num círculo de raio ri + r0.
"""
function find_contact_bruteforce(balls::Vector{Ball}, cue_index::Int, direction::Vec2)::Union{Contact, Nothing}
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

function find_shot_contact(balls::Vector{Ball}, cue_index::Int, direction::Vec2)::Union{Contact, Nothing}
    return find_contact_bruteforce(balls, cue_index, direction)
end
