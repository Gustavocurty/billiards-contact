"""
Erro do rastreamento contra a força bruta no estado atual.

A busca de referência não entra em `last_algorithm_time`.
Bola errada: o índice integrado difere do índice da força bruta.
"""
function tracking_error(state::SimulationState)::Float64
    reference = locate_contact(state)
    state.reference_contact = reference
    current = state.contact
    cue = state.balls[state.cue_index].position
    err = if reference === nothing && current === nothing
        0.0
    elseif reference === nothing
        distance(current.point, cue)
    elseif current === nothing
        reference.distance
    else
        distance(current.point, reference.point)
    end
    if state.error_frame != state.frame
        state.error_frame = state.frame
        state.comparisons += 1
        if reference !== nothing && current !== nothing && reference.ball_index != current.ball_index
            state.wrong_ball_count += 1
        end
        push_sample!(state.sample_errors, err)
    end
    return err
end

function wrong_ball_rate(state::SimulationState)::Float64
    state.comparisons == 0 && return 0.0
    return 100.0 * state.wrong_ball_count / state.comparisons
end

function _mean(total::Float64, count::Int)::Float64
    return count == 0 ? 0.0 : total / count
end

function _percentile(values::Vector{Float64}, fraction::Float64)::Float64
    isempty(values) && return 0.0
    ordered = sort(values)
    index = clamp(ceil(Int, fraction * length(ordered)), 1, length(ordered))
    return ordered[index]
end

function time_summary(times::Vector{Float64})
    n = length(times)
    mean_t = n == 0 ? 0.0 : sum(times) / n
    return (
        mean = mean_t,
        median = _percentile(times, 0.5),
        p99 = _percentile(times, 0.99),
        fps = mean_t > 0.0 ? 1.0 / mean_t : 0.0,
    )
end

function _measure_aim(initial_balls::Vector{Ball}, config::SimulationConfig, algorithm::Symbol, frames::Int; warmup::Int = 4, dtheta::Float64 = 0.01)
    state = SimulationState(copy(initial_balls); algorithm = algorithm, aim_angle = 0.0, live_shot = true)
    initialize!(state)
    for _ in 1:warmup
        aim_step!(state, config, dtheta)
    end
    empty!(state.sample_times)
    empty!(state.sample_errors)
    state.recalculations = 0
    state.wrong_ball_count = 0
    state.comparisons = 0
    state.error_frame = -1

    for _ in 1:frames
        aim_step!(state, config, dtheta)
        if algorithm == :tracking
            tracking_error(state)
        else
            push_sample!(state.sample_errors, 0.0)
        end
    end

    summary = time_summary(state.sample_times)
    errs = state.sample_errors
    method = algorithm == :tracking ? string(config.numerical_method) : "-"
    return (
        n_balls = length(initial_balls),
        radius = initial_balls[1].radius,
        recalculation_interval = max(config.recalculation_interval, 1),
        algorithm = string(algorithm),
        numerical_method = method,
        frames = frames,
        repetitions = 1,
        mean_frame_time_s = summary.mean,
        median_frame_time_s = summary.median,
        p99_frame_time_s = summary.p99,
        fps = summary.fps,
        mean_brute_force_time_s = state.last_kind == :brute_force ? summary.mean : 0.0,
        mean_tracking_time_s = state.last_kind == :tracking ? summary.mean : 0.0,
        mean_error = isempty(errs) ? 0.0 : sum(errs) / length(errs),
        max_error = isempty(errs) ? 0.0 : maximum(errs),
        wrong_ball_rate = wrong_ball_rate(state),
        recalculations = state.recalculations,
    )
end

const BENCHMARK_HEADER = (
    "n_balls",
    "radius",
    "recalculation_interval",
    "algorithm",
    "numerical_method",
    "frames",
    "repetitions",
    "mean_frame_time_s",
    "median_frame_time_s",
    "p99_frame_time_s",
    "fps",
    "mean_brute_force_time_s",
    "mean_tracking_time_s",
    "mean_error",
    "max_error",
    "wrong_ball_rate",
    "recalculations",
)

function _write_benchmark_csv(path::String, rows)
    open(path, "w") do io
        println(io, join(BENCHMARK_HEADER, ","))
        for row in rows
            values = (
                row.n_balls,
                row.radius,
                row.recalculation_interval,
                row.algorithm,
                row.numerical_method,
                row.frames,
                row.repetitions,
                row.mean_frame_time_s,
                row.median_frame_time_s,
                row.p99_frame_time_s,
                row.fps,
                row.mean_brute_force_time_s,
                row.mean_tracking_time_s,
                row.mean_error,
                row.max_error,
                row.wrong_ball_rate,
                row.recalculations,
            )
            println(io, join(values, ","))
        end
    end
    return path
end

function write_pareto_svg(path::String, rows)
    points = NamedTuple[]
    for row in rows
        row.algorithm == "tracking" || continue
        push!(points, (x = row.mean_frame_time_s, y = row.mean_error, method = row.numerical_method, n = row.n_balls, k = row.recalculation_interval))
    end
    xs = [max(p.x, 1e-12) for p in points]
    ys = [max(p.y, 1e-12) for p in points]
    open(path, "w") do io
        println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="760" height="480" viewBox="0 0 760 480">""")
        println(io, """<rect width="760" height="480" fill="#f7f4ee"/>""")
        println(io, """<text x="380" y="32" text-anchor="middle" font-family="sans-serif" font-size="18">Erro médio × tempo por frame</text>""")
        if isempty(points)
            println(io, """<text x="40" y="80" font-family="sans-serif">Sem pontos de rastreamento.</text></svg>""")
            return path
        end
        logx = log10.(xs)
        logy = log10.(ys)
        minx, maxx = minimum(logx), maximum(logx)
        miny, maxy = minimum(logy), maximum(logy)
        maxx = maxx == minx ? minx + 1 : maxx
        maxy = maxy == miny ? miny + 1 : maxy
        left, right, top, bottom = 70, 720, 50, 430
        function px(v)
            return left + (v - minx) / (maxx - minx) * (right - left)
        end
        function py(v)
            return bottom - (v - miny) / (maxy - miny) * (bottom - top)
        end
        println(io, """<line x1="$left" y1="$bottom" x2="$right" y2="$bottom" stroke="#333"/>""")
        println(io, """<line x1="$left" y1="$top" x2="$left" y2="$bottom" stroke="#333"/>""")
        println(io, """<text x="390" y="460" text-anchor="middle" font-family="sans-serif" font-size="13">log10(tempo médio por frame, s)</text>""")
        println(io, """<text x="22" y="250" transform="rotate(-90 22 250)" text-anchor="middle" font-family="sans-serif" font-size="13">log10(erro médio)</text>""")
        for (i, point) in enumerate(points)
            color = point.method == "rk4" ? "#1e88e5" : "#e53935"
            println(io, """<circle cx="$(px(logx[i]))" cy="$(py(logy[i]))" r="4" fill="$color" opacity="0.85"><title>N=$(point.n) K=$(point.k) $(point.method)</title></circle>""")
        end
        println(io, """<circle cx="90" cy="48" r="4" fill="#e53935"/><text x="100" y="52" font-family="sans-serif" font-size="12">Euler</text>""")
        println(io, """<circle cx="170" cy="48" r="4" fill="#1e88e5"/><text x="180" y="52" font-family="sans-serif" font-size="12">RK4</text>""")
        println(io, "</svg>")
    end
    return path
end

function benchmark_executable()
    root = pkgdir(BilliardsContact)
    name = Sys.iswindows() ? "billiards_bench.exe" : "billiards_bench"
    path = joinpath(root, "cpp", name)
    return isfile(path) ? path : ""
end

"""
Gira a mira sobre bolas paradas e compara força bruta com a EDO em θ.

O botão da interface prefere o executável C++ em `cpp/`, que mede com std::chrono
até N = 10⁵. Sem o executável, a medição roda em Julia nesta função.
"""
function run_benchmark(;
    ball_counts = [10, 100, 1000],
    intervals = [1, 5, 10, 30, 60, 120],
    frames::Int = 80,
    dt::Float64 = 1 / 60,
    seed::Int = 1,
    outfile::String = joinpath(pkgdir(BilliardsContact), "benchmark_results.csv"),
    prefer_cpp::Bool = false,
)
    if prefer_cpp
        exe = benchmark_executable()
        if !isempty(exe)
            svg = replace(outfile, ".csv" => "_pareto.svg")
            run(`$exe $outfile $svg`)
            println("CSV salvo em $outfile")
            return outfile
        end
        println("Executável C++ ausente. Medindo em Julia.")
    end

    rows = NamedTuple[]
    rng = MersenneTwister(seed)
    for n in ball_counts
        radius = benchmark_radius(Int(n))
        config0 = SimulationConfig(dt = dt, recalculation_interval = 1, numerical_method = :euler)
        balls = random_balls(Int(n), config0; radius = radius, speed = 0.0, rng = rng)
        for k in intervals
            for (algorithm, method) in ((:brute_force, :euler), (:tracking, :euler), (:tracking, :rk4))
                config = SimulationConfig(dt = dt, recalculation_interval = Int(k), numerical_method = method)
                push!(rows, _measure_aim(balls, config, algorithm, frames))
            end
            last = rows[end]
            println(
                "N=$(last.n_balls) K=$(last.recalculation_interval) ",
                "erro_medio_rk4=$(last.mean_error) bola_errada=$(last.wrong_ball_rate)%",
            )
        end
    end

    _write_benchmark_csv(outfile, rows)
    write_pareto_svg(replace(outfile, ".csv" => "_pareto.svg"), rows)
    println("CSV salvo em $outfile")
    return rows
end
