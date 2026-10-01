struct TimeRamp end
(::TimeRamp)(h::Float64, ::Vec2) = Vec2(h, 0.0)

norm_of(v::Vec2) = hypot(v[1], v[2])

function uniform_state(method::Symbol; interval::Int = 100)
    balls = [
        Ball(Vec2(500.0, 500.0), Vec2(10.0, 0.0), 0.0),
        Ball(Vec2(600.0, 600.0), Vec2(0.0, -10.0), 0.0),
    ]
    config = SimulationConfig(
        dt = 0.05,
        recalculation_interval = interval,
        numerical_method = method,
    )
    state = SimulationState(balls; algorithm = :tracking)
    initialize!(state)
    return state, config
end

@testset "Rastreamento" begin
    @test euler_step(Vec2(1.0, 2.0), Vec2(3.0, -4.0), 0.5) ≈ Vec2(2.5, 0.0) atol = 1e-12

    x0 = Vec2(0.0, 0.0)
    @test euler(x0, 0.2, TimeRamp()) ≈ Vec2(0.0, 0.0) atol = 1e-12
    @test rk4(x0, 0.2, TimeRamp()) ≈ Vec2(0.02, 0.0) atol = 1e-12

    cue = Ball(Vec2(500.0, 500.0), Vec2(10.0, 0.0), 0.0)
    other = Ball(Vec2(600.0, 600.0), Vec2(0.0, -10.0), 0.0)
    @test norm_of(contact_derivative(cue, other)) < 1e-12

    state_euler, config_euler = uniform_state(:euler)
    x_euler = state_euler.contact.point
    for _ in 1:20
        step!(state_euler, config_euler)
    end
    @test state_euler.last_kind == :tracking
    @test state_euler.recalculations == 1
    @test norm_of(state_euler.contact.point - x_euler) < 1e-9
    @test tracking_error(state_euler) < 1e-8

    state_rk4, config_rk4 = uniform_state(:rk4)
    x_rk4 = state_rk4.contact.point
    for _ in 1:20
        step!(state_rk4, config_rk4)
    end
    @test norm_of(state_rk4.contact.point - x_rk4) < 1e-9
    @test tracking_error(state_rk4) < 1e-8
    @test norm_of(state_rk4.contact.point - state_euler.contact.point) < 1e-8

    state_k, config_k = uniform_state(:euler; interval = 5)
    for _ in 1:5
        step!(state_k, config_k)
    end
    @test state_k.frame == 5
    @test state_k.recalculations == 2
    @test state_k.last_kind == :brute_force
    reference = find_contact_bruteforce(state_k.balls, 1)
    @test reference !== nothing
    @test norm_of(state_k.contact.point - reference.point) < 1e-9
end

@testset "Simulação" begin
    balls = [Ball(Vec2(990.0, 10.0), Vec2(100.0, -100.0), 0.0)]
    advance_balls!(balls, 0.2, 1000.0, 1000.0)
    @test balls[1].position[1] == 1000.0
    @test balls[1].position[2] == 0.0
    @test balls[1].velocity[1] == -100.0
    @test balls[1].velocity[2] == 100.0

    balls = [
        Ball(Vec2(960.0, 400.0), Vec2(200.0, 100.0), 0.0),
        Ball(Vec2(800.0, 700.0), Vec2(80.0, -36.0), 0.0),
    ]
    config = SimulationConfig(dt = 0.1, recalculation_interval = 20, numerical_method = :euler)
    state = SimulationState(balls; algorithm = :tracking)
    initialize!(state)
    @test state.contact !== nothing
    for _ in 1:4
        step!(state, config)
    end
    @test state.balls[1].velocity[1] < 0
    @test state.recalculations == 1
    @test tracking_error(state) > 1.0

    while state.frame < 20
        step!(state, config)
    end
    @test state.recalculations == 2
    reference = find_contact_bruteforce(state.balls, 1)
    if reference === nothing
        @test state.contact === nothing
    else
        @test norm_of(state.contact.point - reference.point) < 1e-6
    end

    demo = demo_state()
    @test demo.contact !== nothing
    @test demo.recalculations == 1
end

@testset "Benchmark" begin
    path = tempname() * ".csv"
    rows = run_benchmark(
        ball_counts = [8],
        intervals = [1, 5],
        frames = 12,
        outfile = path,
        seed = 1,
    )
    @test length(rows) == 6
    @test isfile(path)
    @test occursin("mean_error", read(path, String))

    k1 = filter(row -> row.algorithm == "tracking" && row.recalculation_interval == 1 && row.numerical_method == "euler", rows)
    k5 = filter(row -> row.algorithm == "tracking" && row.recalculation_interval == 5 && row.numerical_method == "euler", rows)
    @test only(k1).recalculations > only(k5).recalculations
    @test only(k1).mean_error < 1e-6
end
