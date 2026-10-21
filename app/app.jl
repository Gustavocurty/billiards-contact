using BilliardsContact
using GenieFramework
using PlotlyBase
using Random

@genietools

include(joinpath(@__DIR__, "ui.jl"))

function selected_algorithm(model)::Symbol
    return model.algorithm[] == ALG_BRUTE ? :brute_force : :tracking
end

function selected_config(model)::SimulationConfig
    method = model.method[] == METHOD_RK4 ? :rk4 : :euler
    return SimulationConfig(
        dt = 1 / 60,
        recalculation_interval = max(round(Int, model.recalc_interval[]), 1),
        numerical_method = method,
    )
end

function put_scene!(model, balls::Vector{Ball})
    state = SimulationState(copy(balls); algorithm = selected_algorithm(model), live_shot = true)
    state.aim_angle = deg2rad(Float64(model.aim_deg[]))
    initialize!(state)
    model.pull_gap[] = 0.0
    model.template[] = balls
    model.sim[] = state
    return state
end

function reset_scene!(model)
    n = clamp(round(Int, model.n_balls[]), 2, 16)
    put_scene!(model, rack_balls(n))
    model.running[] = false
    return model.sim[]
end

function random_scene!(model)
    n = clamp(round(Int, model.n_balls[]), 2, 16)
    put_scene!(model, random_resting_balls(n; rng = MersenneTwister(rand(1:1_000_000_000))))
    model.running[] = false
    return model.sim[]
end

function preview_contact!(model)
    state = model.sim[]
    state.algorithm = selected_algorithm(model)
    BilliardsContact.apply_bruteforce!(state)
    return state
end

function format_error(state::SimulationState)::String
    if state.algorithm != :tracking
        return "0,0000 / 0,0000"
    elseif isnan(state.tracking_error)
        return "—"
    else
        maximum_error = isempty(state.sample_errors) ? state.tracking_error : maximum(state.sample_errors)
        return "$(round(state.tracking_error; digits = 4)) / $(round(maximum_error; digits = 4))"
    end
end

function format_contact(state::SimulationState)::String
    contact = state.contact
    contact === nothing && return "sem contato"
    x = round(contact.point[1]; digits = 1)
    y = round(contact.point[2]; digits = 1)
    return "($x, $y)"
end

function publish!(model)
    state = model.sim[]
    # A referência por força bruta é sempre calculada fora do cronômetro do método.
    state.tracking_error = tracking_error(state)
    contact = state.contact
    kind = if state.last_kind == :brute_force
        "força bruta"
    elseif state.last_kind == :tracking
        "EDO"
    else
        "—"
    end
    model.frame[] = state.frame
    model.sim_time[] = round(state.time; digits = 3)
    model.update_kind[] = kind
    model.contact_text[] = format_contact(state)
    model.target_text[] = contact === nothing ? "—" : string(contact.ball_index)
    times = time_summary(state.sample_times)
    model.exec_time[] = round(times.mean * 1_000_000; digits = 2)
    model.recalculations[] = state.recalculations
    model.error_text[] = format_error(state)
    model.time_text[] = "média $(round(times.mean * 1000; digits = 4)) ms, mediana $(round(times.median * 1000; digits = 4)) ms, p99 $(round(times.p99 * 1000; digits = 4)) ms"
    model.fps_text[] = string(round(times.fps; digits = 1))
    model.wrong_text[] = string(round(wrong_ball_rate(state); digits = 2), "%")
    errs = state.sample_errors
    if isempty(errs)
        model.error_stats_text[] = "—"
    else
        model.error_stats_text[] = "médio $(round(sum(errs) / length(errs); digits = 4)), máximo $(round(maximum(errs); digits = 4))"
    end
    model.traces[] = table_traces(state)
    model.cue_pose[] = current_cue_pose(state, Float64(model.power[]), Int(model.cue_seq[]))
    return model
end

function simulation_loop(model)
    while model.isready[]
        try
            if model.running[]
                state = model.sim[]
                state.algorithm = selected_algorithm(model)
                config = selected_config(model)
                step!(state, config)
                stopped = !balls_moving(state)
                publish!(model)
                if stopped
                    model.running[] = false
                    model.status[] = "Mesa parada."
                end
                sleep(max(config.dt, 1 / 30))
            else
                sleep(0.05)
            end
        catch err
            model.running[] = false
            model.status[] = "Erro na simulação: $(sprint(showerror, err))"
            sleep(0.2)
        end
    end
end

initial_traces = table_traces(demo_state())

function current_cue_pose(state::SimulationState, power::Float64, seq::Int)
    cue = state.balls[state.cue_index]
    return Dict{String, Any}(
        "cx" => cue.position[1],
        "cy" => cue.position[2],
        "radius" => cue.radius,
        "aim" => state.aim_angle,
        "power" => power,
        "moving" => balls_moving(state),
        "pull" => PULL_SHOT,
        "seq" => seq,
    )
end

function handle_shot_request!(model)
    model.isready[] || return
    request = model.shot_request[]
    number = dict_get(request, "n")
    number isa Real && number > 0 || return
    angle = as_float(dict_get(request, "angle"))
    power = as_float(dict_get(request, "power"))
    (angle === nothing || power === nothing) && return
    state = model.sim[]
    balls_moving(state) && return
    model.cue_seq[] = round(Int, number)
    state.algorithm = selected_algorithm(model)
    config = selected_config(model)
    new_angle = deg2rad(angle)
    delta = atan(sin(new_angle - state.aim_angle), cos(new_angle - state.aim_angle))
    if abs(delta) > 1e-8
        aim_step!(state, config, delta)
    else
        state.aim_angle = new_angle
        BilliardsContact.apply_bruteforce!(state)
    end
    model.aim_deg[] = round(Int, rad2deg(atan(sin(state.aim_angle), cos(state.aim_angle))))
    model.power[] = clamp(power, POWER_MIN, POWER_MAX)
    model.pull_gap[] = 0.0
    if as_bool(dict_get(request, "fire")) && strike!(state, Float64(model.power[]))
        model.running[] = true
        step!(state, selected_config(model))
        publish!(model)
        model.status[] = "Tacada."
        return
    end
    publish!(model)
    return
end

function dict_get(value, key::String)
    value isa AbstractDict || return nothing
    haskey(value, key) && return value[key]
    symbol = Symbol(key)
    haskey(value, symbol) && return value[symbol]
    return nothing
end

function as_float(value)::Union{Float64, Nothing}
    value isa Real || return nothing
    number = Float64(value)
    return isfinite(number) ? number : nothing
end

function as_bool(value)::Bool
    value isa Bool && return value
    value isa Number && return value != 0
    return false
end

const CueApp = @app begin
    @in running = false
    @in algorithm = ALG_TRACK
    @in n_balls = 6
    @in aim_deg = 0
    @in power = 420
    @in recalc_interval = 30
    @in method = METHOD_EULER
    @in pause_toggle_click = false
    @in shot_click = false
    @in reset_click = false
    @in random_click = false
    @in bench_click = false
    @in cluster_click = false
    @in aligned_click = false
    @in tangent_click = false
    @in export_click = false
    @in shot_request = Dict{String, Any}("n" => 0, "angle" => 0.0, "power" => 420.0, "fire" => false)
    @out frame = 0
    @out sim_time = 0.0
    @out update_kind = "—"
    @out contact_text = "—"
    @out target_text = "—"
    @out exec_time = 0.0
    @out recalculations = 0
    @out error_text = "—"
    @out error_stats_text = "—"
    @out wrong_text = "—"
    @out time_text = "—"
    @out fps_text = "—"
    @out capacity_text = "—"
    @out benchmark_status = "Use o CSV existente ou rode a varredura."
    @out benchmark_progress = 0
    @out benchmark_csv = ""
    @out status = "Pronto."
    @out layout = table_layout()
    @out chart_config = table_plot_config()
    @out traces = initial_traces
    @out cue_pose = Dict{String, Any}(
        "cx" => 220.0, "cy" => 500.0, "radius" => 18.0, "aim" => 0.0, "power" => 420.0, "moving" => false, "pull" => 28.0, "seq" => 0,
    )
    @private sim = demo_state()
    @private template = rack_balls(6)
    @private loop_on = false
    @private pull_gap = 0.0
    @private cue_seq = 0

    @onchange isready begin
        isready || return
        __model__.loop_on[] && return
        __model__.loop_on[] = true
        reset_scene!(__model__)
        publish!(__model__)
        path = joinpath(pkgdir(BilliardsContact), "benchmark_results.csv")
        isfile(path) && (__model__.benchmark_csv[] = read(path, String))
        __model__.status[] = "Pronto."
        @async simulation_loop(__model__)
    end

    @onbutton shot_click begin
        state = __model__.sim[]
        state.aim_angle = deg2rad(Float64(aim_deg))
        if strike!(state, Float64(power))
            running = true
            publish!(__model__)
            status = "Tacada."
        else
            status = "A bola branca ainda está em movimento."
        end
    end

    @onbutton pause_toggle_click begin
        moving = balls_moving(__model__.sim[])
        if moving || running
            running = !running
            status = running ? "Movimento retomado." : "Pausado."
        else
            status = "A pausa só fica disponível durante o movimento."
        end
    end

    @onchange shot_request begin
        handle_shot_request!(__model__)
    end

    @onchange algorithm begin
        __model__.isready[] || return
        preview_contact!(__model__)
        publish!(__model__)
    end

    @onchange n_balls begin
        __model__.isready[] || return
        n = clamp(round(Int, n_balls), 2, 16)
        length(__model__.sim[].balls) == n && return
        __model__.running[] = false
        put_scene!(__model__, rack_balls(n))
        publish!(__model__)
        status = "Mesa com $n bolas, todas paradas."
    end

    @onbutton reset_click begin
        reset_scene!(__model__)
        publish!(__model__)
        status = "Cena reiniciada."
    end

    @onbutton random_click begin
        random_scene!(__model__)
        publish!(__model__)
        status = "Novas posições aleatórias."
    end

    @onbutton cluster_click begin
        running = false; put_scene!(__model__, demo_scenario(:cluster, clamp(round(Int, n_balls), 2, 16))); publish!(__model__); status = "Cenário aglomerado."
    end
    @onbutton aligned_click begin
        running = false; put_scene!(__model__, demo_scenario(:aligned, clamp(round(Int, n_balls), 2, 16))); publish!(__model__); status = "Quase alinhadas: a bola alvo pode trocar."
    end
    @onbutton tangent_click begin
        running = false; put_scene!(__model__, demo_scenario(:tangent, clamp(round(Int, n_balls), 2, 16))); publish!(__model__); status = "Quase tangente: pior caso da EDO."
    end

    @onbutton bench_click begin
        running = false
        benchmark_status = "Experimentos em execução…"
        benchmark_progress = 10
        model = __model__
        @async begin
            try
                path = joinpath(pkgdir(BilliardsContact), "benchmark_results.csv")
                run_benchmark(outfile = path, prefer_cpp = true)
                model.benchmark_csv[] = read(path, String)
                model.benchmark_progress[] = 100
                model.benchmark_status[] = "Concluído: $path"
            catch err
                model.benchmark_status[] = "Benchmark falhou: $(sprint(showerror, err))"
            end
        end
    end
end

Stipple.debounce(CueApp, :shot_request, 0)
@mounted CueApp string(cue_pointer_script(), "\n", dashboard_script())

@page("/", ui)

println("Abra http://127.0.0.1:8000")
Server.isrunning() || up(8000, "127.0.0.1"; async = false, open_browser = true)
