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
    return SimulationConfig(
        dt = 1 / 60,
        recalculation_interval = max(round(Int, model.recalc_interval[]), 1),
        numerical_method = :euler,
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
    state.aim_angle = deg2rad(Float64(model.aim_deg[]))
    cue = state.balls[state.cue_index]
    moving = hypot(cue.velocity[1], cue.velocity[2]) > 8.0
    if !moving || state.algorithm == :brute_force
        state.contact = locate_contact(state)
        state.last_kind = :brute_force
    end
    return state
end

function format_error(state::SimulationState, validate::Bool)::String
    if state.algorithm != :tracking
        return "0 (referência)"
    elseif !validate
        return "desligado"
    elseif isnan(state.tracking_error)
        return "—"
    else
        return string(round(state.tracking_error; digits = 4))
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
    if state.algorithm != :tracking
        state.tracking_error = 0.0
    elseif model.validate_error[]
        state.tracking_error = tracking_error(state)
    else
        state.tracking_error = NaN
    end
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
    model.exec_time[] = round(state.last_algorithm_time * 1000; digits = 4)
    model.recalculations[] = state.recalculations
    model.error_text[] = format_error(state, model.validate_error[])
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
    state.aim_angle = deg2rad(angle)
    model.aim_deg[] = round(Int, rad2deg(state.aim_angle))
    model.power[] = clamp(power, POWER_MIN, POWER_MAX)
    model.pull_gap[] = 0.0
    if as_bool(dict_get(request, "fire")) && strike!(state, Float64(model.power[]))
        model.running[] = true
        step!(state, selected_config(model))
        publish!(model)
        model.status[] = "Tacada."
        return
    end
    preview_contact!(model)
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
    @in validate_error = true
    @in start_click = false
    @in pause_click = false
    @in reset_click = false
    @in random_click = false
    @in shot_click = false
    @in bench_click = false
    @in shot_request = Dict{String, Any}("n" => 0, "angle" => 0.0, "power" => 420.0, "fire" => false)
    @out frame = 0
    @out sim_time = 0.0
    @out update_kind = "—"
    @out contact_text = "—"
    @out target_text = "—"
    @out exec_time = 0.0
    @out recalculations = 0
    @out error_text = "—"
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
        __model__.status[] = "Pronto."
        @async simulation_loop(__model__)
    end

    @onbutton start_click begin
        running = true
        cue = __model__.sim[].balls[__model__.sim[].cue_index]
        moving = hypot(cue.velocity[1], cue.velocity[2]) > 8.0
        status = moving ? "Movimento retomado." : "A bola branca está parada. Use Tacada."
    end

    @onbutton pause_click begin
        running = false
        status = "Pausado."
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

    @onchange validate_error begin
        __model__.isready[] || return
        publish!(__model__)
    end

    @onbutton bench_click begin
        running = false
        status = "Benchmark em execução. Aguarde o CSV."
        model = __model__
        @async begin
            try
                path = joinpath(pkgdir(BilliardsContact), "benchmark_results.csv")
                run_benchmark(outfile = path)
                model.status[] = "CSV salvo em $path"
            catch err
                model.status[] = "Benchmark falhou: $(sprint(showerror, err))"
            end
        end
    end
end

Stipple.debounce(CueApp, :shot_request, 0)
@mounted CueApp cue_pointer_script()

@page("/", ui)

println("Abra http://127.0.0.1:8000")
Server.isrunning() || up(8000, "127.0.0.1"; async = false, open_browser = true)
