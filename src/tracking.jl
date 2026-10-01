"""
Derivada de X(t) = C₁ + s d₁ para velocidades constantes no passo.

Diferenciando s = (Δ × dᵢ) / (d₁ × dᵢ) com Δ' = dᵢ - d₁ obtém-se s' = -1
e portanto X' = (1 + s') d₁ = 0. As retas são invariantes enquanto a
velocidade não muda. A reflexão na borda é uma descontinuidade: o ponto
rastreado só é corrigido no próximo recálculo por força bruta.
"""
function contact_derivative(cue::Ball, target::Ball)::Vec2
    d1 = cue.velocity
    di = target.velocity
    δ = cross2(d1, di)
    scale = max(hypot(d1[1], d1[2]) * hypot(di[1], di[2]), 1.0)
    if abs(δ) <= PARALLEL_EPS * scale
        return Vec2(0.0, 0.0)
    end
    s_dot = cross2(di - d1, di) / δ
    return (1.0 + s_dot) * d1
end

function euler_step(x::Vec2, xdot::Vec2, dt::Float64)::Vec2
    return x + dt * xdot
end

"""
Euler explícito para X' = f(h, X), com h medido a partir do início do passo.
"""
function euler(x::Vec2, dt::Float64, f)::Vec2
    return euler_step(x, f(0.0, x), dt)
end

"""
RK4 clássico para X' = f(h, X).
"""
function rk4(x::Vec2, dt::Float64, f)::Vec2
    k1::Vec2 = f(0.0, x)
    k2::Vec2 = f(dt / 2, x + (dt / 2) * k1)
    k3::Vec2 = f(dt / 2, x + (dt / 2) * k2)
    k4::Vec2 = f(dt, x + dt * k3)
    return x + (dt / 6) * (k1 + 2 * k2 + 2 * k3 + k4)
end

function shifted(ball::Ball, h::Float64)::Ball
    return Ball(ball.position + h * ball.velocity, ball.velocity, ball.radius)
end

struct ContactRHS
    cue::Ball
    target::Ball
end

@inline function (rhs::ContactRHS)(h::Float64, ::Vec2)::Vec2
    return contact_derivative(shifted(rhs.cue, h), shifted(rhs.target, h))
end

function rk4_step(x::Vec2, cue::Ball, target::Ball, dt::Float64)::Vec2
    return rk4(x, dt, ContactRHS(cue, target))
end
