# Mesma cena de test/tracking_test.jl: head_on_error.
# Bolas em (0, 0) e (220, 24), raio 18, giro total 0,04 rad,
# K = 10^9 para não haver recálculo no intervalo medido.
# Uso: julia --project=. scripts/convergence.jl

using BilliardsContact

const TOTAL = 0.04
const STEPS = (8e-3, 4e-3, 2e-3, 1e-3, 5e-4)

function integrate_error(method::Symbol, h::Float64)
    radius = 18.0
    balls = [
        Ball(Vec2(0.0, 0.0), Vec2(0.0, 0.0), radius),
        Ball(Vec2(220.0, 24.0), Vec2(0.0, 0.0), radius),
    ]
    config = SimulationConfig(recalculation_interval = 1_000_000_000, numerical_method = method)
    state = SimulationState(balls; algorithm = :tracking, aim_angle = 0.0, live_shot = true)
    initialize!(state)
    n = max(round(Int, TOTAL / h), 1)
    fallback = 0
    for _ in 1:n
        aim_step!(state, config, h)
        state.last_kind == :tracking || (fallback += 1)
    end
    reference = locate_contact(state)
    err = distance(state.contact.point, reference.point)
    return err, fallback, n
end

function order_between(errors, steps, i)
    return log(errors[i] / errors[i + 1]) / log(steps[i] / steps[i + 1])
end

open(joinpath(dirname(@__DIR__), "docs", "convergencia.txt"), "w") do io
    for method in (:euler, :rk4)
        println(io, method)
        errors = Float64[]
        for h in STEPS
            err, fallback, n = integrate_error(method, h)
            push!(errors, err)
            println(io, "h=$h n=$n erro=$err fallbacks=$fallback")
        end
        for i in 1:(length(STEPS) - 1)
            println(io, "ordem $(STEPS[i]) -> $(STEPS[i + 1]) = $(order_between(errors, STEPS, i))")
        end
    end
end

function write_convergence_svg(path)
    text = read(joinpath(dirname(@__DIR__), "docs", "convergencia.txt"), String)
    series = Dict("euler" => Tuple{Float64, Float64}[], "rk4" => Tuple{Float64, Float64}[])
    method = ""
    for line in split(text, "\n")
        line in ("euler", "rk4") && (method = line; continue)
        startswith(line, "h=") || continue
        h = parse(Float64, match(r"h=([0-9eE.+-]+)", line).captures[1])
        err = parse(Float64, match(r"erro=([0-9eE.+-]+)", line).captures[1])
        push!(series[method], (h, err))
    end
    open(path, "w") do io
        println(io, """<svg xmlns="http://www.w3.org/2000/svg" width="760" height="460" viewBox="0 0 760 460">""")
        println(io, """<rect width="760" height="460" fill="#f7f4ee"/>""")
        println(io, """<text x="380" y="28" text-anchor="middle" font-family="sans-serif" font-size="16">Erro do contato × Δθ, uma bola, sem recálculo</text>""")
        left, right, top, bottom = 90, 730, 58, 400
        xs = [log10(p[1]) for pts in values(series) for p in pts]
        ys = [log10(p[2]) for pts in values(series) for p in pts]
        minx, maxx = minimum(xs), maximum(xs)
        miny, maxy = minimum(ys), maximum(ys)
        println(io, """<line x1="$left" y1="$bottom" x2="$right" y2="$bottom" stroke="#333"/>""")
        println(io, """<line x1="$left" y1="$top" x2="$left" y2="$bottom" stroke="#333"/>""")
        println(io, """<text x="400" y="440" text-anchor="middle" font-family="sans-serif" font-size="13">log10(Δθ, rad)</text>""")
        println(io, """<text x="18" y="230" transform="rotate(-90 18 230)" text-anchor="middle" font-family="sans-serif" font-size="13">log10(erro, unidade da mesa)</text>""")
        println(io, """<text x="$left" y="$(bottom + 16)" font-family="sans-serif" font-size="11">$(round(exp10(minx); sigdigits = 3))</text>""")
        println(io, """<text x="$right" y="$(bottom + 16)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(maxx); sigdigits = 3))</text>""")
        println(io, """<text x="$(left - 8)" y="$(bottom)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(miny); sigdigits = 3))</text>""")
        println(io, """<text x="$(left - 8)" y="$(top + 8)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(maxy); sigdigits = 3))</text>""")
        colors = Dict("euler" => "#e53935", "rk4" => "#1e88e5")
        for (i, name) in enumerate(("euler", "rk4"))
            coords = String[]
            for (h, err) in series[name]
                px = left + (log10(h) - minx) / (maxx - minx) * (right - left)
                py = bottom + (log10(err) - miny) / (maxy - miny) * (top - bottom)
                push!(coords, "$(px),$(py)")
                println(io, """<circle cx="$(px)" cy="$(py)" r="4" fill="$(colors[name])"/>""")
            end
            println(io, """<polyline points="$(join(coords, " "))" fill="none" stroke="$(colors[name])" stroke-width="1.5"/>""")
            println(io, """<rect x="$(520 + (i - 1) * 90)" y="36" width="12" height="12" fill="$(colors[name])"/>""")
            println(io, """<text x="$(536 + (i - 1) * 90)" y="46" font-family="sans-serif" font-size="12">$(name)</text>""")
        end
        println(io, "</svg>")
    end
end

write_convergence_svg(joinpath(dirname(@__DIR__), "docs", "img", "convergencia.svg"))
println(read(joinpath(dirname(@__DIR__), "docs", "convergencia.txt"), String))
