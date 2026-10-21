# Contato com raio: a branca fantasma está em c0 + s d, |d| = 1,
# e encosta na bola i quando |c0 + s d − ci| = ri + r0 (2R se os raios são iguais).
# A raiz usada é a entrada do círculo, s = −b − sqrt(b² − c),
# com b = w·d, c = |w|² − R² e w = c0 − ci.

const SPEED_EPS = 1e-12
const S_EPS = 1e-9
const TANGENT_EPS = 1e-3
const RESIDUAL_LIMIT = 2.0

@inline function cross2(a::Vec2, b::Vec2)::Float64
    return a[1] * b[2] - a[2] * b[1]
end

function distance(a::Vec2, b::Vec2)::Float64
    return hypot(a[1] - b[1], a[2] - b[2])
end

function direction_from(angle::Float64)::Vec2
    return Vec2(cos(angle), sin(angle))
end

"""
Primeira raiz s ≥ 0 de |origem + s d − centro| = raio.
`d` não precisa estar normalizado. Sem raiz à frente, o encontro é inválido.
"""
function ray_circle_hit(origin::Vec2, direction::Vec2, center::Vec2, radius_sum::Float64)
    dir_len = hypot(direction[1], direction[2])
    if dir_len <= SPEED_EPS || radius_sum < 0.0
        return (false, 0.0, Vec2(0.0, 0.0))
    end
    dx = direction[1] / dir_len
    dy = direction[2] / dir_len
    wx = origin[1] - center[1]
    wy = origin[2] - center[2]
    b = wx * dx + wy * dy
    c = wx * wx + wy * wy - radius_sum * radius_sum
    disc = b * b - c
    if disc < 0.0
        return (false, 0.0, Vec2(0.0, 0.0))
    end
    s = -b - sqrt(disc)
    if s < -S_EPS
        return (false, s, origin + s * Vec2(dx, dy))
    end
    s_use = s < 0.0 ? 0.0 : s
    return (true, s_use, origin + s_use * Vec2(dx, dy))
end

"""
ds/dθ = −s (w·d′) / (w·d), com w = c0 + s d − ci e d′ = (−sin θ, cos θ).
`NaN` marca quase tangência (w·d → 0) e obriga recálculo.
"""
function s_derivative(theta::Float64, s::Float64, origin::Vec2, center::Vec2)::Float64
    d = direction_from(theta)
    dp = Vec2(-sin(theta), cos(theta))
    w = origin + s * d - center
    denom = w[1] * d[1] + w[2] * d[2]
    if abs(denom) < TANGENT_EPS
        return NaN
    end
    return -s * (w[1] * dp[1] + w[2] * dp[2]) / denom
end

function circle_residual(theta::Float64, s::Float64, origin::Vec2, center::Vec2, radius_sum::Float64)::Float64
    d = direction_from(theta)
    w = origin + s * d - center
    return abs(hypot(w[1], w[2]) - radius_sum)
end
