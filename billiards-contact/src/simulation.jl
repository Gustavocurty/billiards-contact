const DEFAULT_RADIUS = 18.0
const DEFAULT_SPEED = 180.0
const FRICTION = 140.0
const STOPPED_SPEED = 8.0

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

function resolve_collisions!(balls::Vector{Ball})
    n = length(balls)
    for i in 1:(n - 1)
        for j in (i + 1):n
            bi = balls[i]
            bj = balls[j]
            dx = bj.position[1] - bi.position[1]
            dy = bj.position[2] - bi.position[2]
            dist = hypot(dx, dy)
            min_dist = bi.radius + bj.radius
            (dist >= min_dist || dist < 1e-8) && continue
            nx = dx / dist
            ny = dy / dist
            overlap = min_dist - dist
            balls[i] = Ball(bi.position - (0.5 * overlap) * Vec2(nx, ny), bi.velocity, bi.radius)
            balls[j] = Ball(bj.position + (0.5 * overlap) * Vec2(nx, ny), bj.velocity, bj.radius)
            bi = balls[i]
            bj = balls[j]
            rel_n = (bi.velocity[1] - bj.velocity[1]) * nx + (bi.velocity[2] - bj.velocity[2]) * ny
            rel_n > 0.0 || continue
            normal = Vec2(nx, ny)
            balls[i] = Ball(bi.position, bi.velocity - rel_n * normal, bi.radius)
            balls[j] = Ball(bj.position, bj.velocity + rel_n * normal, bj.radius)
        end
    end
    return balls
end

function advance_balls!(balls::Vector{Ball}, dt::Float64, width::Float64, height::Float64; friction::Float64 = 0.0, collide::Bool = false)
    friction > 0.0 && apply_friction!(balls, dt, friction)
    @inbounds for i in eachindex(balls)
        b = balls[i]
        r = b.radius
        x = b.position[1] + dt * b.velocity[1]
        y = b.position[2] + dt * b.velocity[2]
        vx = b.velocity[1]
        vy = b.velocity[2]
        if x < r
            x = r
            vx = abs(vx)
        elseif x > width - r
            x = width - r
            vx = -abs(vx)
        end
        if y < r
            y = r
            vy = abs(vy)
        elseif y > height - r
            y = height - r
            vy = -abs(vy)
        end
        balls[i] = Ball(Vec2(x, y), Vec2(vx, vy), r)
    end
    if !isempty(balls) && collide
        resolve_collisions!(balls)
    end
    return balls
end

function shot_direction(state::SimulationState)::Vec2
    cue = state.balls[state.cue_index]
    speed = hypot(cue.velocity[1], cue.velocity[2])
    if speed > STOPPED_SPEED
        return cue.velocity
    end
    return Vec2(cos(state.aim_angle), sin(state.aim_angle))
end

function locate_contact(state::SimulationState)::Union{Contact, Nothing}
    if state.live_shot
        return find_shot_contact(state.balls, state.cue_index, shot_direction(state))
    end
    return find_contact_bruteforce(state.balls, state.cue_index)
end

function apply_bruteforce!(state::SimulationState)
    elapsed = @elapsed contact = locate_contact(state)
    state.contact = contact
    state.brute_force_time = elapsed
    state.last_algorithm_time = elapsed
    state.last_kind = :brute_force
    state.recalculations += 1
    return state
end

function initialize!(state::SimulationState)
    state.frame = 0
    state.time = 0.0
    state.tracking_time = 0.0
    state.recalculations = 0
    state.tracking_error = NaN
    apply_bruteforce!(state)
    return state
end

"""
Avança a física e o ponto de contato um passo.

No rastreamento, a força bruta roda no frame 0 (via `initialize!`) e sempre que
`frame % K == 0`. Nos demais frames o ponto segue a EDO. Um valor não finito
dispara uma nova busca. Reflexões nas bordas não disparam busca imediata:
esse atraso é o erro controlado por K.
"""
function step!(state::SimulationState, config::SimulationConfig)
    dt = config.dt
    dt > 0 || throw(ArgumentError("dt deve ser positivo"))
    interval = max(config.recalculation_interval, 1)

    contact = state.contact
    cue_index = state.cue_index
    ode_index = contact === nothing ? 0 : contact.ball_index
    ode_point = contact === nothing ? Vec2(0.0, 0.0) : contact.point
    cue_before = state.balls[cue_index]
    target_ok = 1 <= ode_index <= length(state.balls) && ode_index != cue_index
    target_before = target_ok ? state.balls[ode_index] : cue_before

    if state.live_shot
        advance_balls!(state.balls, dt, config.width, config.height; friction = FRICTION, collide = true)
    else
        advance_balls!(state.balls, dt, config.width, config.height)
    end
    state.frame += 1
    state.time += dt

    use_tracking = state.algorithm == :tracking
    need_brute = !use_tracking || contact === nothing || !target_ok || (state.frame % interval == 0)

    if need_brute
        apply_bruteforce!(state)
        return state
    end

    t0 = time_ns()
    xnew = if config.numerical_method == :rk4
        rk4_step(ode_point, cue_before, target_before, dt)
    else
        euler_step(ode_point, contact_derivative(cue_before, target_before), dt)
    end
    elapsed = (time_ns() - t0) / 1.0e9

    if !isfinite(xnew[1]) || !isfinite(xnew[2])
        apply_bruteforce!(state)
        return state
    end

    cue_now = state.balls[cue_index]
    state.contact = Contact(xnew, ode_index, distance(xnew, cue_now.position))
    state.tracking_time = elapsed
    state.last_algorithm_time = elapsed
    state.last_kind = :tracking
    return state
end

function strike!(state::SimulationState, power::Float64)
    i = state.cue_index
    ball = state.balls[i]
    speed = hypot(ball.velocity[1], ball.velocity[2])
    if speed > STOPPED_SPEED
        return false
    end
    direction = Vec2(cos(state.aim_angle), sin(state.aim_angle))
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
    speed::Float64 = DEFAULT_SPEED,
    rng::AbstractRNG = Random.default_rng(),
)
    n >= 2 || throw(ArgumentError("sao necessarias pelo menos 2 bolas"))
    balls = Vector{Ball}(undef, n)
    span_x = max(config.width - 2 * radius, 1.0)
    span_y = max(config.height - 2 * radius, 1.0)
    for i in 1:n
        pos = Vec2(radius + rand(rng) * span_x, radius + rand(rng) * span_y)
        θ = 2π * rand(rng)
        mag = speed * (0.7 + 0.6 * rand(rng))
        balls[i] = Ball(pos, Vec2(mag * cos(θ), mag * sin(θ)), radius)
    end
    return balls
end
