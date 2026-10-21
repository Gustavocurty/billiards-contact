"""
Um passo de Euler em θ: s ← s + Δθ · ds/dθ.
"""
function euler_theta(theta::Float64, s::Float64, dtheta::Float64, origin::Vec2, center::Vec2)::Float64
    ds = s_derivative(theta, s, origin, center)
    isfinite(ds) || return NaN
    return s + dtheta * ds
end

"""
RK4 em θ para s' = f(θ, s). Qualquer estágio tangente devolve `NaN`.
"""
function rk4_theta(theta::Float64, s::Float64, dtheta::Float64, origin::Vec2, center::Vec2)::Float64
    k1 = s_derivative(theta, s, origin, center)
    isfinite(k1) || return NaN
    k2 = s_derivative(theta + dtheta / 2, s + (dtheta / 2) * k1, origin, center)
    isfinite(k2) || return NaN
    k3 = s_derivative(theta + dtheta / 2, s + (dtheta / 2) * k2, origin, center)
    isfinite(k3) || return NaN
    k4 = s_derivative(theta + dtheta, s + dtheta * k3, origin, center)
    isfinite(k4) || return NaN
    return s + (dtheta / 6) * (k1 + 2 * k2 + 2 * k3 + k4)
end

function integrate_s(method::Symbol, theta::Float64, s::Float64, dtheta::Float64, origin::Vec2, center::Vec2)::Float64
    if method == :rk4
        return rk4_theta(theta, s, dtheta, origin, center)
    end
    return euler_theta(theta, s, dtheta, origin, center)
end
