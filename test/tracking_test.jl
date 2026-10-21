function head_on_error(method::Symbol, h::Float64, total::Float64)
    radius = 18.0
    balls = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(220.0, 24.0), Vec2(0.0, 0.0), radius),
    ]
    config = SimulationConfig(recalculation_interval = 1_000_000_000, numerical_method = method)
    state = SimulationState(balls; algorithm = :tracking, aim_angle = 0.0, live_shot = true)
    initialize!(state)
    n = max(round(Int, total / h), 1)
    for _ in 1:n
        aim_step!(state, config, h)
        @test state.last_kind == :tracking
    end
    reference = locate_contact(state)
    @test reference !== nothing
    return distance(state.contact.point, reference.point)
end

@testset "EDO da mira" begin
    radius = 18.0
    balls = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(180.0, 0.0), Vec2(0.0, 0.0), radius),
    ]
    config = SimulationConfig(recalculation_interval = 5, numerical_method = :euler)
    state = SimulationState(balls; algorithm = :tracking, live_shot = true)
    initialize!(state)
    @test state.contact !== nothing
    @test state.recalculations == 1
    for _ in 1:4
        aim_step!(state, config, 0.002)
    end
    @test state.last_kind == :tracking
    aim_step!(state, config, 0.002)
    @test state.frame == 5
    @test state.last_kind == :brute_force
    @test state.recalculations == 2

    k1 = SimulationConfig(recalculation_interval = 1, numerical_method = :rk4)
    forced = SimulationState(copy(balls); algorithm = :tracking, live_shot = true)
    initialize!(forced)
    aim_step!(forced, k1, 0.02)
    @test forced.last_kind == :brute_force

    grazing = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(200.0, 36.0), Vec2(0.0, 0.0), radius),
    ]
    grazing_state = SimulationState(grazing; algorithm = :tracking, live_shot = true)
    initialize!(grazing_state)
    before = grazing_state.recalculations
    aim_step!(grazing_state, SimulationConfig(recalculation_interval = 100, numerical_method = :rk4), 0.01)
    @test grazing_state.last_kind == :brute_force
    @test grazing_state.recalculations == before + 1

    spinning = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(180.0, 0.0), Vec2(0.0, 0.0), radius),
    ]
    variable = SimulationState(spinning; algorithm = :tracking, live_shot = true)
    initialize!(variable)
    for h in (0.004, -0.001, 0.008, 0.002, -0.003)
        aim_step!(variable, SimulationConfig(recalculation_interval = 50, numerical_method = :rk4), h)
        @test variable.last_kind == :tracking
    end
    @test tracking_error(variable) < 1e-3
end

@testset "Convergência" begin
    h = 2e-3
    total = 0.04
    e_euler = head_on_error(:euler, h, total)
    e_euler_half = head_on_error(:euler, h / 2, total)
    order_euler = log2(e_euler / e_euler_half)
    @test e_euler > e_euler_half
    @test 0.7 < order_euler < 1.4

    e_rk = head_on_error(:rk4, h, total)
    e_rk_half = head_on_error(:rk4, h / 2, total)
    order_rk = log2(e_rk / e_rk_half)
    @test e_rk < e_euler
    @test order_rk > 3.0
end

@testset "Alvos quase alinhados" begin
    radius = 18.0
    balls = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(220.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(150.0, 55.0), Vec2(0.0, 0.0), radius),
    ]
    indices = Int[]
    for degree in 0:12
        state = SimulationState(copy(balls); aim_angle = deg2rad(Float64(degree)), live_shot = true)
        contact = locate_contact(state)
        contact === nothing || push!(indices, contact.ball_index)
    end
    @test length(unique(indices)) >= 2

    tracked = SimulationState(copy(balls); algorithm = :tracking, aim_angle = 0.0, live_shot = true)
    config = SimulationConfig(recalculation_interval = 80, numerical_method = :euler)
    initialize!(tracked)
    changed = false
    for _ in 1:30
        aim_step!(tracked, config, deg2rad(0.35))
        reference = locate_contact(tracked)
        if reference !== nothing && tracked.contact !== nothing && reference.ball_index != tracked.contact.ball_index
            changed = true
            @test tracked.last_kind == :tracking
            break
        end
    end
    @test changed
end

@testset "Benchmark da mira" begin
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
    text = read(path, String)
    @test occursin("mean_error", text)
    @test occursin("wrong_ball_rate", text)
    @test occursin("p99_frame_time_s", text)
    @test isfile(replace(path, ".csv" => "_pareto.svg"))

    k1 = filter(row -> row.algorithm == "tracking" && row.recalculation_interval == 1 && row.numerical_method == "euler", rows)
    @test only(k1).mean_error < 1e-6

    pair = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), 18.0),
        Ball(Vec2(180.0, 0.0), Vec2(0.0, 0.0), 18.0),
    ]
    function counted(interval)
        config = SimulationConfig(recalculation_interval = interval, numerical_method = :euler)
        state = SimulationState(copy(pair); algorithm = :tracking, live_shot = true)
        initialize!(state)
        state.recalculations = 0
        for _ in 1:12
            aim_step!(state, config, 0.002)
        end
        return state.recalculations
    end
    @test counted(1) > counted(5)
end
