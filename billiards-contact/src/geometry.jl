# Trajetórias com raio desprezível (r → 0): a interseção é entre retas.
# A bola de taco só considera o futuro da própria velocidade (s ≥ 0).
# τ fica livre: a trajetória da outra bola é a reta suporte de d_i.
# Retas paralelas, inclusive as colineares, não têm interseção única.

const SPEED_EPS = 1e-12
const PARALLEL_EPS = 1e-10
const S_EPS = 1e-9

@inline function cross2(a::Vec2, b::Vec2)::Float64
    return a[1] * b[2] - a[2] * b[1]
end

function distance(a::Vec2, b::Vec2)::Float64
    return hypot(a[1] - b[1], a[2] - b[2])
end

"""
Interseção de `C₁ + s d₁` com `Cᵢ + τ dᵢ`.

Retorna `(válida, s, τ, ponto)`. Interseções com `s < 0` ficam atrás da bola de taco.
"""
function intersect_trajectories(cue::Ball, other::Ball)
    d1 = cue.velocity
    di = other.velocity
    speed1 = hypot(d1[1], d1[2])
    if speed1 <= SPEED_EPS
        return (false, 0.0, 0.0, Vec2(0.0, 0.0))
    end

    δ = cross2(d1, di)
    scale = max(speed1 * hypot(di[1], di[2]), 1.0)
    if abs(δ) <= PARALLEL_EPS * scale
        return (false, 0.0, 0.0, Vec2(0.0, 0.0))
    end

    Δ = other.position - cue.position
    s = cross2(Δ, di) / δ
    τ = cross2(Δ, d1) / δ
    if s < -S_EPS
        return (false, s, τ, cue.position + s * d1)
    end

    s_use = s < 0.0 ? 0.0 : s
    return (true, s_use, τ, cue.position + s_use * d1)
end

"""
Primeiro encontro do raio `origem + s·direção` (s ≥ 0) com um círculo.
`s` é a distância até o centro da bola de taco no contato.
Usado quando as bolas estão paradas: a rota é a direção do taco, não a velocidade.
"""
function ray_circle_hit(origin::Vec2, direction::Vec2, center::Vec2, radius_sum::Float64)
    dir_len = hypot(direction[1], direction[2])
    if dir_len <= SPEED_EPS || radius_sum < 0.0
        return (false, 0.0, Vec2(0.0, 0.0))
    end
    ux = direction[1] / dir_len
    uy = direction[2] / dir_len
    wx = center[1] - origin[1]
    wy = center[2] - origin[2]
    along = wx * ux + wy * uy
    disc = along * along - (wx * wx + wy * wy - radius_sum * radius_sum)
    if disc < 0.0
        return (false, 0.0, Vec2(0.0, 0.0))
    end
    root = sqrt(disc)
    s = along - root
    if s < -S_EPS
        s = along + root
    end
    if s < -S_EPS
        return (false, 0.0, Vec2(0.0, 0.0))
    end
    s_use = s < 0.0 ? 0.0 : s
    return (true, s_use, origin + s_use * Vec2(ux, uy))
end
