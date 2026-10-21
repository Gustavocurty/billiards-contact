const DEFAULT_RADIUS = 18.0
const DEFAULT_SPEED = 180.0
const FRICTION = 140.0
const STOPPED_SPEED = 8.0
const EVENT_EPS = 1e-9
const MAX_EVENTS = 48
const SAMPLE_CAP = 4096

function apply_friction!(balls::Vector{Ball}, dt::Float64, friction::Float64)
    drop = friction * dt
    @inbounds for i in eachindex(balls)
        b = balls[i]
        speed = hypot(b.velocity[1], b.velocity[2])
        if speed <= drop || speed <= 1e-8
            speed > 0.0 && (balls[i] = Ball(b.position, Vec2(0.0, 0.0), b.radius))
            continue
        end
        balls[i] = Ball(b.position, b.velocity * ((speed - drop) / speed), b.radius)
    end
    return balls
end

function resolve_pair!(balls::Vector{Ball}, i::Int, j::Int)
    bi = balls[i]
    bj = balls[j]
    dx = bj.position[1] - bi.position[1]
    dy = bj.position[2] - bi.position[2]
    dist = hypot(dx, dy)
    dist < 1e-8 && return balls
    nx = dx / dist
    ny = dy / dist
    min_dist = bi.radius + bj.radius
    if dist < min_dist
        overlap = min_dist - dist
        bi = Ball(bi.position - (0.5 * overlap) * Vec2(nx, ny), bi.velocity, bi.radius)
        bj = Ball(bj.position + (0.5 * overlap) * Vec2(nx, ny), bj.velocity, bj.radius)
        dx = bj.position[1] - bi.position[1]
        dy = bj.position[2] - bi.position[2]
        dist = hypot(dx, dy)
        dist < 1e-8 && return balls
        nx = dx / dist
        ny = dy / dist
    end
    rel_n = (bi.velocity[1] - bj.velocity[1]) * nx + (bi.velocity[2] - bj.velocity[2]) * ny
    rel_n > 0.0 || return balls
    normal = Vec2(nx, ny)
    balls[i] = Ball(bi.position, bi.velocity - rel_n * normal, bi.radius)
    balls[j] = Ball(bj.position, bj.velocity + rel_n * normal, bj.radius)
    return balls
end

function collision_time(a::Ball, b::Ball)::Float64
    dx = b.position[1] - a.position[1]
    dy = b.position[2] - a.position[2]
    dvx = b.velocity[1] - a.velocity[1]
    dvy = b.velocity[2] - a.velocity[2]
    radius_sum = a.radius + b.radius
    c = dx * dx + dy * dy - radius_sum * radius_sum
    bcoef = dx * dvx + dy * dvy
    if bcoef >= 0.0
        return Inf
    end
    if c < -1e-6
        return 0.0
    end
    a_coef = dvx * dvx + dvy * dvy
    a_coef < 1e-16 && return Inf
    disc = bcoef * bcoef - a_coef * c
    disc < 0.0 && return Inf
    root = sqrt(disc)
    t1 = (-bcoef - root) / a_coef
    t2 = (-bcoef + root) / a_coef
    if t1 >= -1e-9
        return max(t1, 0.0)
    elseif t2 >= -1e-9
        return max(t2, 0.0)
    end
    return Inf
end

function wall_time(ball::Ball, width::Float64, height::Float64)
    r = ball.radius
    vx = ball.velocity[1]
    vy = ball.velocity[2]
    best = Inf
    axis = 0
    if vx > SPEED_EPS
        t = (width - r - ball.position[1]) / vx
        if 0.0 <= t < best
            best = t
            axis = 1
        end
    elseif vx < -SPEED_EPS
        t = (r - ball.position[1]) / vx
        if 0.0 <= t < best
            best = t
            axis = 1
        end
    end
    if vy > SPEED_EPS
        t = (height - r - ball.position[2]) / vy
        if 0.0 <= t < best
            best = t
            axis = 2
        end
    elseif vy < -SPEED_EPS
        t = (r - ball.position[2]) / vy
        if 0.0 <= t < best
            best = t
            axis = 2
        end
    end
    return best, axis
end

function friction_stop_time(ball::Ball, friction::Float64)::Float64
    friction <= 0.0 && return Inf
    speed = hypot(ball.velocity[1], ball.velocity[2])
    speed <= 1e-8 && return Inf
    return speed / friction
end

function reflect_wall!(balls::Vector{Ball}, i::Int, axis::Int, width::Float64, height::Float64)
    b = balls[i]
    x = b.position[1]
    y = b.position[2]
    vx = b.velocity[1]
    vy = b.velocity[2]
    r = b.radius
    if axis == 1
        if vx >= 0.0
            x = min(x, width - r)
            vx = -abs(vx)
        else
            x = max(x, r)
            vx = abs(vx)
        end
    else
        if vy >= 0.0
            y = min(y, height - r)
            vy = -abs(vy)
        else
            y = max(y, r)
            vy = abs(vy)
        end
    end
    balls[i] = Ball(Vec2(x, y), Vec2(vx, vy), r)
    return balls
end

function next_event(balls::Vector{Ball}, width::Float64, height::Float64, friction::Float64, collide::Bool)
    best_t = Inf
    kind = :none
    bi = 0
    bj = 0
    n = length(balls)
    for i in 1:n
        speed = hypot(balls[i].velocity[1], balls[i].velocity[2])
        speed <= 1e-8 && continue
        tw, axis = wall_time(balls[i], width, height)
        if tw < best_t
            best_t = tw
            kind = :wall
            bi = i
            bj = axis
        end
        ts = friction_stop_time(balls[i], friction)
        if ts < best_t
            best_t = ts
            kind = :stop
            bi = i
            bj = 0
        end
    end
    if collide
        for i in 1:(n - 1)
            for j in (i + 1):n
                tc = collision_time(balls[i], balls[j])
                if tc < best_t
                    best_t = tc
                    kind = :ball
                    bi = i
                    bj = j
                end
            end
        end
    end
    return best_t, kind, bi, bj
end

"""
Avança até o próximo evento (bola, parede ou parada por atrito) e repete dentro de `dt`.
Entre eventos a velocidade é constante, então o tempo de colisão é a raiz quadrática.
O atrito constante é aplicado ao fim de cada trecho.
"""
function advance_events!(balls::Vector{Ball}, dt::Float64, width::Float64, height::Float64, friction::Float64, collide::Bool)
    left = dt
    guard = 0
    while left > EVENT_EPS && guard < MAX_EVENTS
        guard += 1
        t_event, kind, i, j = next_event(balls, width, height, friction, collide)
        t = min(left, t_event)
        if !isfinite(t) || t < 0.0
            t = left
            kind = :none
        end
        hit = kind != :none && t + 1e-8 >= min(left, t_event) && t_event <= left + 1e-8
        if t > EVENT_EPS
            @inbounds for k in eachindex(balls)
                b = balls[k]
                balls[k] = Ball(b.position + t * b.velocity, b.velocity, b.radius)
            end
        end
        if hit && kind == :ball
            resolve_pair!(balls, i, j)
        elseif hit && kind == :wall
            reflect_wall!(balls, i, j, width, height)
        elseif hit && kind == :stop
            b = balls[i]
            balls[i] = Ball(b.position, Vec2(0.0, 0.0), b.radius)
        end
        friction > 0.0 && t > 0.0 && apply_friction!(balls, t, friction)
        left -= max(t, 0.0)
        kind == :none && break
        t <= EVENT_EPS && kind == :none && break
    end
    return balls
end

function advance_balls!(balls::Vector{Ball}, dt::Float64, width::Float64, height::Float64; friction::Float64 = 0.0, collide::Bool = false)
    return advance_events!(balls, dt, width, height, friction, collide)
end

function shot_direction(state::SimulationState)::Vec2
    cue = state.balls[state.cue_index]
    speed = hypot(cue.velocity[1], cue.velocity[2])
    if speed > STOPPED_SPEED
        return cue.velocity
    end
    return direction_from(state.aim_angle)
end

function locate_contact(state::SimulationState)::Union{Contact, Nothing}
    return find_contact_bruteforce(state.balls, state.cue_index, shot_direction(state))
end

function push_sample!(samples::Vector{Float64}, value::Float64)
    isfinite(value) || return samples
    push!(samples, value)
    if length(samples) > SAMPLE_CAP
        deleteat!(samples, 1)
    end
    return samples
end

function remember_contact!(state::SimulationState, contact::Union{Contact, Nothing})
    state.contact = contact
    if contact === nothing
        state.tracked_s = NaN
        state.track_ball = 0
    else
        state.tracked_s = contact.distance
        state.track_ball = contact.ball_index
    end
    return state
end

function apply_bruteforce!(state::SimulationState)
    t0 = time_ns()
    contact = locate_contact(state)
    elapsed = (time_ns() - t0) / 1.0e9
    remember_contact!(state, contact)
    state.brute_force_time = elapsed
    state.last_algorithm_time = elapsed
    state.last_kind = :brute_force
    state.recalculations += 1
    push_sample!(state.sample_times, elapsed)
    return state
end

function initialize!(state::SimulationState)
    state.frame = 0
    state.time = 0.0
    state.tracking_time = 0.0
    state.recalculations = 0
    state.tracking_error = NaN
    state.reference_contact = nothing
    empty!(state.sample_times)
    empty!(state.sample_errors)
    state.wrong_ball_count = 0
    state.comparisons = 0
    state.error_frame = -1
    apply_bruteforce!(state)
    return state
end

function balls_have_speed(state::SimulationState)::Bool
    for ball in state.balls
        hypot(ball.velocity[1], ball.velocity[2]) > 1e-8 && return true
    end
    return false
end

"""
Integra s(θ) um passo. Quase tangência, resíduo alto ou s inválido disparam a força bruta.
K = 1, ou frame múltiplo de K, também recalcula.
"""
function aim_step!(state::SimulationState, config::SimulationConfig, dtheta::Float64)
    isfinite(dtheta) || return state
    dtheta = clamp(dtheta, -π, π)
    state.frame += 1
    interval = max(config.recalculation_interval, 1)
    theta0 = state.aim_angle
    state.aim_angle = theta0 + dtheta
    use_ode = state.algorithm == :tracking && state.frame % interval != 0 && state.track_ball != 0 && isfinite(state.tracked_s)
    if !use_ode || abs(dtheta) <= 1e-15
        apply_bruteforce!(state)
        return state
    end

    cue = state.balls[state.cue_index]
    target = state.balls[state.track_ball]
    radius_sum = cue.radius + target.radius
    t0 = time_ns()
    s_new = integrate_s(config.numerical_method, theta0, state.tracked_s, dtheta, cue.position, target.position)
    elapsed = (time_ns() - t0) / 1.0e9
    theta1 = state.aim_angle
    residual = isfinite(s_new) ? circle_residual(theta1, s_new, cue.position, target.position, radius_sum) : Inf
    ds_end = isfinite(s_new) ? s_derivative(theta1, s_new, cue.position, target.position) : NaN
    if !isfinite(s_new) || s_new < -S_EPS || residual > RESIDUAL_LIMIT || !isfinite(ds_end)
        apply_bruteforce!(state)
        return state
    end
    d = direction_from(theta1)
    point = cue.position + s_new * d
    state.tracked_s = s_new
    state.contact = Contact(point, state.track_ball, s_new)
    state.tracking_time = elapsed
    state.last_algorithm_time = elapsed
    state.last_kind = :tracking
    push_sample!(state.sample_times, elapsed)
    return state
end

"""
Tacada por eventos dentro do frame. O contato exibido segue a velocidade atual
pela mesma busca do círculo; a EDO em θ só vale na mira, com as bolas paradas.
"""
function step!(state::SimulationState, config::SimulationConfig)
    dt = config.dt
    dt > 0 || throw(ArgumentError("dt deve ser positivo"))
    state.algorithm == :brute_force || state.algorithm == :tracking || (state.algorithm = :tracking)

    if balls_have_speed(state)
        friction = state.live_shot ? FRICTION : 0.0
        advance_events!(state.balls, dt, config.width, config.height, friction, state.live_shot)
        state.frame += 1
        state.time += dt
        apply_bruteforce!(state)
        return state
    end

    state.frame += 1
    state.time += dt
    return state
end

function strike!(state::SimulationState, power::Float64)
    i = state.cue_index
    ball = state.balls[i]
    speed = hypot(ball.velocity[1], ball.velocity[2])
    if speed > STOPPED_SPEED
        return false
    end
    direction = direction_from(state.aim_angle)
    state.balls[i] = Ball(ball.position, max(power, 0.0) * direction, ball.radius)
    return true
end

"""
Bolas paradas. A branca fica à esquerda; as demais formam um grupo à direita, na linha do taco em ângulo 0.
"""
function rack_balls(n::Int = 6)
    n = max(n, 2)
    r = DEFAULT_RADIUS
    balls = Vector{Ball}(undef, n)
    balls[1] = Ball(Vec2(220.0, 500.0), Vec2(0.0, 0.0), r)
    cols = max(ceil(Int, sqrt(n - 1)), 1)
    gap = 2.4 * r
    for k in 0:(n - 2)
        col = k % cols
        row = k ÷ cols
        x = min(560.0 + col * gap, 1000.0 - r - 8.0)
        y = 500.0 + (row - (cols - 1) / 2) * gap
        y = clamp(y, r + 8.0, 1000.0 - r - 8.0)
        balls[k + 2] = Ball(Vec2(x, y), Vec2(0.0, 0.0), r)
    end
    return balls
end

function random_resting_balls(n::Int, config::SimulationConfig = SimulationConfig(); rng::AbstractRNG = Random.default_rng())
    n = max(n, 2)
    r = DEFAULT_RADIUS
    balls = rack_balls(n)
    balls[1] = Ball(Vec2(220.0, 500.0), Vec2(0.0, 0.0), r)
    for i in 2:n
        for _ in 1:50
            pos = Vec2(
                420.0 + rand(rng) * (config.width - 420.0 - r - 8.0),
                r + 8.0 + rand(rng) * (config.height - 2 * r - 16.0),
            )
            clear = true
            for j in 1:(i - 1)
                if distance(pos, balls[j].position) < 2.3 * r
                    clear = false
                    break
                end
            end
            if clear
                balls[i] = Ball(pos, Vec2(0.0, 0.0), r)
                break
            end
        end
    end
    return balls
end

"""Cenas determinísticas usadas na apresentação da interface."""
function demo_scenario(name::Symbol, n::Int = 6; config::SimulationConfig = SimulationConfig())
    n = clamp(n, 2, 16)
    r = DEFAULT_RADIUS
    if name == :random
        return random_resting_balls(n, config; rng = MersenneTwister(20261020))
    elseif name == :aligned
        balls = rack_balls(n)
        balls[1] = Ball(Vec2(220.0, 500.0), Vec2(0.0, 0.0), r)
        # Duas entradas muito próximas: uma pequena mudança troca a primeira bola.
        balls[2] = Ball(Vec2(570.0, 482.0), Vec2(0.0, 0.0), r)
        balls[3] = Ball(Vec2(570.0, 518.0), Vec2(0.0, 0.0), r)
        return balls
    elseif name == :tangent
        balls = rack_balls(n)
        balls[1] = Ball(Vec2(220.0, 500.0), Vec2(0.0, 0.0), r)
        # A reta horizontal é quase tangente ao círculo fantasma da bola 2.
        balls[2] = Ball(Vec2(590.0, 535.7), Vec2(0.0, 0.0), r)
        return balls
    end
    return rack_balls(n)
end

function demo_balls()
    r = DEFAULT_RADIUS
    return Ball[
        Ball(Vec2(200.0, 500.0), Vec2(140.0, 30.0), r),
        Ball(Vec2(400.0, 200.0), Vec2(10.0, 90.0), r),
        Ball(Vec2(700.0, 650.0), Vec2(-20.0, -80.0), r),
        Ball(Vec2(80.0, 420.0), Vec2(-30.0, 20.0), r),
        Ball(Vec2(500.0, 800.0), Vec2(140.0, 30.0), r),
        Ball(Vec2(800.0, 250.0), Vec2(-90.0, 70.0), r),
    ]
end

function demo_state(; algorithm::Symbol = :tracking, config::SimulationConfig = SimulationConfig())
    state = SimulationState(demo_balls(); algorithm = algorithm)
    initialize!(state)
    return state
end

function random_balls(n::Int, config::SimulationConfig = SimulationConfig();
    radius::Float64 = DEFAULT_RADIUS,
    speed::Float64 = 0.0,
    rng::AbstractRNG = Random.default_rng(),
)
    n >= 2 || throw(ArgumentError("sao necessarias pelo menos 2 bolas"))
    balls = Vector{Ball}(undef, n)
    span_x = max(config.width - 2 * radius, 1.0)
    span_y = max(config.height - 2 * radius, 1.0)
    for i in 1:n
        pos = Vec2(radius + rand(rng) * span_x, radius + rand(rng) * span_y)
        if speed <= 0.0
            balls[i] = Ball(pos, Vec2(0.0, 0.0), radius)
        else
            θ = 2π * rand(rng)
            mag = speed * (0.7 + 0.6 * rand(rng))
            balls[i] = Ball(pos, Vec2(mag * cos(θ), mag * sin(θ)), radius)
        end
    end
    balls[1] = Ball(Vec2(config.width * 0.22, config.height * 0.5), Vec2(0.0, 0.0), radius)
    return balls
end

"""
Escala o raio para a fração de área ficar baixa quando N cresce.
"""
function benchmark_radius(n::Int; base::Float64 = DEFAULT_RADIUS, reference_n::Int = 10)::Float64
    n = max(n, 1)
    return base * sqrt(reference_n / n)
end
