"""
Erro do rastreamento contra a força bruta no estado atual.

A busca de referência é independente do tempo medido em `step!`.
Se só um dos dois lados tem contato, o erro é a distância desse ponto até a bola de taco.
"""
function tracking_error(state::SimulationState)::Float64
    reference = locate_contact(state)
    current = state.contact
    cue = state.balls[state.cue_index].position
    if reference === nothing && current === nothing
        return 0.0
    elseif reference === nothing
        return distance(current.point, cue)
    elseif current === nothing
        return reference.distance
    else
        return distance(current.point, reference.point)
    end
end

function _mean(total::Float64, count::Int)::Float64
    return count == 0 ? 0.0 : total / count
end

function _measure_run(initial_balls::Vector{Ball}, config::SimulationConfig, algorithm::Symbol, frames::Int)
    state = SimulationState(copy(initial_balls); algorithm = algorithm)
    initialize!(state)

    sum_frame = 0.0
    sum_brute = 0.0
    n_brute = 0
    sum_track = 0.0
    n_track = 0
    sum_error = 0.0
    max_error = 0.0

    for _ in 1:frames
        step!(state, config)
        sum_frame += state.last_algorithm_time
        if state.last_kind == :brute_force
            sum_brute += state.last_algorithm_time
            n_brute += 1
        else
            sum_track += state.last_algorithm_time
            n_track += 1
        end
        err = algorithm == :tracking ? tracking_error(state) : 0.0
        sum_error += err
        max_error = max(max_error, err)
    end

    method = algorithm == :tracking ? string(config.numerical_method) : "-"
    return (
        n_balls = length(initial_balls),
        recalculation_interval = max(config.recalculation_interval, 1),
        algorithm = string(algorithm),
        numerical_method = method,
        frames = frames,
        mean_frame_time_s = _mean(sum_frame, frames),
        mean_brute_force_time_s = _mean(sum_brute, n_brute),
        mean_tracking_time_s = _mean(sum_track, n_track),
        mean_error = _mean(sum_error, frames),
        max_error = max_error,
        recalculations = state.recalculations,
    )
end

function _write_benchmark_csv(path::String, rows)
    header = (
        "n_balls",
        "recalculation_interval",
        "algorithm",
        "numerical_method",
        "frames",
        "mean_frame_time_s",
        "mean_brute_force_time_s",
        "mean_tracking_time_s",
        "mean_error",
        "max_error",
        "recalculations",
    )
    open(path, "w") do io
        println(io, join(header, ","))
        for row in rows
            values = (
                row.n_balls,
                row.recalculation_interval,
                row.algorithm,
                row.numerical_method,
                row.frames,
                row.mean_frame_time_s,
                row.mean_brute_force_time_s,
                row.mean_tracking_time_s,
                row.mean_error,
                row.max_error,
                row.recalculations,
            )
            println(io, join(values, ","))
        end
    end
    return path
end

"""
Compara força bruta e rastreamento para vários N e K.

O tempo de frame não inclui a força bruta extra usada só para medir o erro.
"""
function run_benchmark(;
    ball_counts = [10, 20, 50, 100, 200, 500, 1000],
    intervals = [1, 5, 10, 20, 30, 60, 120],
    frames::Int = 240,
    dt::Float64 = 1 / 60,
    seed::Int = 1,
    outfile::String = joinpath(pkgdir(BilliardsContact), "benchmark_results.csv"),
)
    warmup_config = SimulationConfig(dt = dt, recalculation_interval = 5, numerical_method = :rk4)
    warmup = SimulationState(random_balls(12, warmup_config; rng = MersenneTwister(0)); algorithm = :tracking)
    initialize!(warmup)
    for _ in 1:3
        step!(warmup, warmup_config)
        tracking_error(warmup)
    end

    rows = NamedTuple[]
    rng = MersenneTwister(seed)
    base = SimulationConfig(dt = dt, recalculation_interval = 1, numerical_method = :euler)

    for n in ball_counts
        balls = random_balls(Int(n), base; rng = rng)
        for k in intervals
            brute_config = SimulationConfig(dt = dt, recalculation_interval = Int(k), numerical_method = :euler)
            push!(rows, _measure_run(balls, brute_config, :brute_force, frames))
            for method in (:euler, :rk4)
                config = SimulationConfig(dt = dt, recalculation_interval = Int(k), numerical_method = method)
                push!(rows, _measure_run(balls, config, :tracking, frames))
            end
            last = rows[end]
            println(
                "N=$(last.n_balls) K=$(last.recalculation_interval) ",
                "erro_medio_rk4=$(last.mean_error) recalculos=$(last.recalculations)",
            )
        end
    end

    _write_benchmark_csv(outfile, rows)
    println("CSV salvo em $outfile")
    return rows
end
