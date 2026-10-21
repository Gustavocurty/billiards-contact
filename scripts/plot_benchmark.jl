# Figuras e tabela do README a partir de benchmark_results.csv.
# Uso, na raiz do projeto:
#   julia --project=. scripts/plot_benchmark.jl

const ROOT = dirname(@__DIR__)
const CSV = joinpath(ROOT, "benchmark_results.csv")
const IMG = joinpath(ROOT, "docs", "img")

function load_rows(path)
    lines = readlines(path)
    header = split(lines[1], ",")
    rows = NamedTuple[]
    for line in lines[2:end]
        isempty(strip(line)) && continue
        parts = split(line, ",")
        length(parts) == length(header) || error("coluna inesperada em: $line")
        data = Dict{String, String}(string(header[i]) => string(parts[i]) for i in eachindex(header))
        push!(rows, (
            n = parse(Int, data["n_balls"]),
            radius = parse(Float64, data["radius"]),
            k = parse(Int, data["recalculation_interval"]),
            algorithm = data["algorithm"],
            method = data["numerical_method"],
            frames = parse(Int, data["frames"]),
            repetitions = parse(Int, data["repetitions"]),
            mean = parse(Float64, data["mean_frame_time_s"]),
            median = parse(Float64, data["median_frame_time_s"]),
            p99 = parse(Float64, data["p99_frame_time_s"]),
            fps = parse(Float64, data["fps"]),
            mean_error = parse(Float64, data["mean_error"]),
            max_error = parse(Float64, data["max_error"]),
            wrong = parse(Float64, data["wrong_ball_rate"]),
            recalcs = parse(Int, data["recalculations"]),
        ))
    end
    return rows
end

function label_of(row)
    return row.algorithm == "brute_force" ? "força bruta" : row.method
end

function find_row(rows; n, k, algorithm, method = nothing)
    for row in rows
        row.n == n && row.k == k && row.algorithm == algorithm || continue
        method === nothing || row.method == method || continue
        return row
    end
    return nothing
end

function svg_begin(title)
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="760" height="460" viewBox="0 0 760 460">
    <rect width="760" height="460" fill="#f7f4ee"/>
    <text x="380" y="28" text-anchor="middle" font-family="sans-serif" font-size="16">$(title)</text>
    """
end

function map_range(v, vmin, vmax, a, b)
    vmax == vmin && return (a + b) / 2
    return a + (v - vmin) / (vmax - vmin) * (b - a)
end

function draw_log_series(io, series; xlabel, ylabel, colors)
    left, right, top, bottom = 78, 730, 48, 400
    xs = Float64[]
    ys = Float64[]
    for (_, pts) in series
        for (x, y) in pts
            push!(xs, log10(max(x, 1e-15)))
            push!(ys, log10(max(y, 1e-15)))
        end
    end
    minx, maxx = minimum(xs), maximum(xs)
    miny, maxy = minimum(ys), maximum(ys)
    maxx = maxx == minx ? minx + 1 : maxx
    maxy = maxy == miny ? miny + 1 : maxy
    println(io, """<line x1="$left" y1="$bottom" x2="$right" y2="$bottom" stroke="#333"/>""")
    println(io, """<line x1="$left" y1="$top" x2="$left" y2="$bottom" stroke="#333"/>""")
    println(io, """<text x="400" y="440" text-anchor="middle" font-family="sans-serif" font-size="13">$(xlabel)</text>""")
    println(io, """<text x="18" y="230" transform="rotate(-90 18 230)" text-anchor="middle" font-family="sans-serif" font-size="13">$(ylabel)</text>""")
    println(io, """<text x="$left" y="$(bottom + 16)" font-family="sans-serif" font-size="11">$(round(exp10(minx); sigdigits = 3))</text>""")
    println(io, """<text x="$right" y="$(bottom + 16)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(maxx); sigdigits = 3))</text>""")
    println(io, """<text x="$(left - 6)" y="$(bottom)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(miny); sigdigits = 3))</text>""")
    println(io, """<text x="$(left - 6)" y="$(top + 8)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(maxy); sigdigits = 3))</text>""")
    names = collect(keys(series))
    for (i, name) in enumerate(names)
        color = colors[name]
        pts = series[name]
        coords = String[]
        for (x, y) in pts
            px = map_range(log10(max(x, 1e-15)), minx, maxx, left, right)
            py = map_range(log10(max(y, 1e-15)), miny, maxy, bottom, top)
            push!(coords, "$(px),$(py)")
            println(io, """<circle cx="$(px)" cy="$(py)" r="4" fill="$(color)"/>""")
        end
        if length(coords) >= 2
            println(io, """<polyline points="$(join(coords, " "))" fill="none" stroke="$(color)" stroke-width="1.5"/>""")
        end
        lx = 90 + (i - 1) * 150
        println(io, """<rect x="$(lx)" y="36" width="12" height="12" fill="$(color)"/>""")
        println(io, """<text x="$(lx + 16)" y="46" font-family="sans-serif" font-size="12">$(name)</text>""")
    end
end

function write_time_figure(rows)
    series = Dict{String, Vector{Tuple{Float64, Float64}}}()
    for name in ("força bruta", "euler", "rk4")
        series[name] = Tuple{Float64, Float64}[]
    end
    ns = sort(unique(row.n for row in rows))
    for n in ns
        brute = find_row(rows; n = n, k = 30, algorithm = "brute_force")
        euler = find_row(rows; n = n, k = 30, algorithm = "tracking", method = "euler")
        rk4 = find_row(rows; n = n, k = 30, algorithm = "tracking", method = "rk4")
        push!(series["força bruta"], (Float64(n), brute.mean * 1e6))
        push!(series["euler"], (Float64(n), euler.mean * 1e6))
        push!(series["rk4"], (Float64(n), rk4.mean * 1e6))
    end
    open(joinpath(IMG, "tempo_por_frame.svg"), "w") do io
        print(io, svg_begin("Tempo médio por atualização × N, com K = 30"))
        draw_log_series(io, series; xlabel = "log10(N, bolas)", ylabel = "log10(tempo médio, µs)", colors = Dict("força bruta" => "#e5a93d", "euler" => "#e53935", "rk4" => "#1e88e5"))
        println(io, "</svg>")
    end
end

function write_pareto(rows)
    open(joinpath(IMG, "pareto.svg"), "w") do io
        print(io, svg_begin("Erro médio × tempo médio (cada ponto é um par N, K)"))
        left, right, top, bottom = 78, 730, 58, 400
        pts = [(row.mean * 1e6, max(row.mean_error, 1e-6), row.method) for row in rows if row.algorithm == "tracking"]
        xs = log10.([p[1] for p in pts])
        ys = log10.([p[2] for p in pts])
        minx, maxx = minimum(xs), maximum(xs)
        miny, maxy = minimum(ys), maximum(ys)
        println(io, """<line x1="$left" y1="$bottom" x2="$right" y2="$bottom" stroke="#333"/>""")
        println(io, """<line x1="$left" y1="$top" x2="$left" y2="$bottom" stroke="#333"/>""")
        println(io, """<text x="400" y="440" text-anchor="middle" font-family="sans-serif" font-size="13">log10(tempo médio, µs)</text>""")
        println(io, """<text x="18" y="230" transform="rotate(-90 18 230)" text-anchor="middle" font-family="sans-serif" font-size="13">log10(erro médio, unidade da mesa)</text>""")
        println(io, """<text x="$left" y="$(bottom + 16)" font-family="sans-serif" font-size="11">$(round(exp10(minx); sigdigits = 3))</text>""")
        println(io, """<text x="$right" y="$(bottom + 16)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(maxx); sigdigits = 3))</text>""")
        println(io, """<text x="$(left - 6)" y="$(bottom)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(miny); sigdigits = 3))</text>""")
        println(io, """<text x="$(left - 6)" y="$(top + 8)" text-anchor="end" font-family="sans-serif" font-size="11">$(round(exp10(maxy); sigdigits = 3))</text>""")
        for (x, y, method) in pts
            px = map_range(log10(x), minx, maxx, left, right)
            py = map_range(log10(y), miny, maxy, bottom, top)
            color = method == "rk4" ? "#1e88e5" : "#e53935"
            println(io, """<circle cx="$(px)" cy="$(py)" r="4" fill="$(color)" opacity="0.85"/>""")
        end
        println(io, """<circle cx="90" cy="44" r="4" fill="#e53935"/><text x="100" y="48" font-family="sans-serif" font-size="12">Euler</text>""")
        println(io, """<circle cx="180" cy="44" r="4" fill="#1e88e5"/><text x="190" y="48" font-family="sans-serif" font-size="12">RK4</text>""")
        println(io, "</svg>")
    end
end

function write_error_figures(rows)
    ks = sort(unique(row.k for row in rows))
    for n in sort(unique(row.n for row in rows))
        open(joinpath(IMG, "erro_k_n$(n).svg"), "w") do io
            print(io, svg_begin("N = $(n): erro médio e bola errada × K"))
            left, mid, right, top, bottom = 70, 390, 720, 58, 250
            function panel(x0, x1, y0, y1, values, ylabel, color)
                vmin, vmax = minimum(values), maximum(values)
                vmax = vmax == vmin ? vmin + 1 : vmax
                println(io, """<line x1="$x0" y1="$y1" x2="$x1" y2="$y1" stroke="#333"/>""")
                println(io, """<line x1="$x0" y1="$y0" x2="$x0" y2="$y1" stroke="#333"/>""")
                println(io, """<text x="$((x0 + x1) / 2)" y="430" text-anchor="middle" font-family="sans-serif" font-size="12">K (frames)</text>""")
                println(io, """<text x="$(x0 - 48)" y="$((y0 + y1) / 2)" transform="rotate(-90 $(x0 - 48) $((y0 + y1) / 2))" text-anchor="middle" font-family="sans-serif" font-size="12">$(ylabel)</text>""")
                for (name, series) in values
                    coords = String[]
                    for (i, k) in enumerate(ks)
                        px = map_range(log10(k), log10(minimum(ks)), log10(maximum(ks)), x0, x1)
                        py = map_range(series[i], vmin, vmax, y1, y0)
                        push!(coords, "$(px),$(py)")
                        println(io, """<circle cx="$(px)" cy="$(py)" r="3.5" fill="$(color[name])"/>""")
                    end
                    println(io, """<polyline points="$(join(coords, " "))" fill="none" stroke="$(color[name])" stroke-width="1.4"/>""")
                end
            end
            # Painel esquerdo: erro. Direito: bola errada. Séries separadas para não misturar o desenho.
            err = Dict("euler" => Float64[], "rk4" => Float64[])
            wrong = Dict("euler" => Float64[], "rk4" => Float64[])
            for k in ks
                push!(err["euler"], find_row(rows; n = n, k = k, algorithm = "tracking", method = "euler").mean_error)
                push!(err["rk4"], find_row(rows; n = n, k = k, algorithm = "tracking", method = "rk4").mean_error)
                push!(wrong["euler"], find_row(rows; n = n, k = k, algorithm = "tracking", method = "euler").wrong)
                push!(wrong["rk4"], find_row(rows; n = n, k = k, algorithm = "tracking", method = "rk4").wrong)
            end
            colors = Dict("euler" => "#e53935", "rk4" => "#1e88e5")
            # Dois gráficos empilhados ficam mais legíveis do que dois eixos.
            println(io, """<text x="70" y="52" font-family="sans-serif" font-size="13">Erro médio (unidade da mesa)</text>""")
            y0, y1 = 70, 220
            x0, x1 = 70, 720
            emin = min(minimum(err["euler"]), minimum(err["rk4"]))
            emax = max(maximum(err["euler"]), maximum(err["rk4"]))
            emax = emax == emin ? emin + 1 : emax
            println(io, """<line x1="$x0" y1="$y1" x2="$x1" y2="$y1" stroke="#333"/>""")
            println(io, """<line x1="$x0" y1="$y0" x2="$x0" y2="$y1" stroke="#333"/>""")
            for name in ("euler", "rk4")
                coords = String[]
                for (i, k) in enumerate(ks)
                    px = map_range(log10(k), log10(first(ks)), log10(last(ks)), x0, x1)
                    py = map_range(err[name][i], emin, emax, y1, y0)
                    push!(coords, "$(px),$(py)")
                    println(io, """<circle cx="$(px)" cy="$(py)" r="3.5" fill="$(colors[name])"/>""")
                end
                println(io, """<polyline points="$(join(coords, " "))" fill="none" stroke="$(colors[name])" stroke-width="1.4"/>""")
            end
            println(io, """<text x="70" y="268" font-family="sans-serif" font-size="13">Bola errada (%)</text>""")
            y0, y1 = 286, 400
            wmin = min(minimum(wrong["euler"]), minimum(wrong["rk4"]))
            wmax = max(maximum(wrong["euler"]), maximum(wrong["rk4"]))
            wmax = wmax == wmin ? wmin + 1 : wmax
            println(io, """<line x1="$x0" y1="$y1" x2="$x1" y2="$y1" stroke="#333"/>""")
            println(io, """<line x1="$x0" y1="$y0" x2="$x0" y2="$y1" stroke="#333"/>""")
            println(io, """<text x="390" y="450" text-anchor="middle" font-family="sans-serif" font-size="12">K em escala log10 (1, 5, 10, 30, 60, 120)</text>""")
            println(io, """<text x="$(x0 - 6)" y="224" text-anchor="end" font-family="sans-serif" font-size="11">$(round(emin; sigdigits = 3))</text>""")
            println(io, """<text x="$(x0 - 6)" y="78" text-anchor="end" font-family="sans-serif" font-size="11">$(round(emax; sigdigits = 3))</text>""")
            println(io, """<text x="$(x0 - 6)" y="404" text-anchor="end" font-family="sans-serif" font-size="11">$(round(wmin; sigdigits = 3))</text>""")
            println(io, """<text x="$(x0 - 6)" y="294" text-anchor="end" font-family="sans-serif" font-size="11">$(round(wmax; sigdigits = 3))</text>""")
            for name in ("euler", "rk4")
                coords = String[]
                for (i, k) in enumerate(ks)
                    px = map_range(log10(k), log10(first(ks)), log10(last(ks)), x0, x1)
                    py = map_range(wrong[name][i], wmin, wmax, y1, y0)
                    push!(coords, "$(px),$(py)")
                    println(io, """<circle cx="$(px)" cy="$(py)" r="3.5" fill="$(colors[name])"/>""")
                end
                println(io, """<polyline points="$(join(coords, " "))" fill="none" stroke="$(colors[name])" stroke-width="1.4"/>""")
            end
            println(io, """<circle cx="520" cy="40" r="4" fill="#e53935"/><text x="530" y="44" font-family="sans-serif" font-size="12">Euler</text>""")
            println(io, """<circle cx="600" cy="40" r="4" fill="#1e88e5"/><text x="610" y="44" font-family="sans-serif" font-size="12">RK4</text>""")
            println(io, "</svg>")
        end
    end
end

function fmt(x)
    return string(round(x; sigdigits = 4))
end

function write_table_and_notes(rows)
    lines = String[]
    push!(lines, "| N | K | método | média (µs) | mediana (µs) | p99 (µs) | ganho | erro médio | erro máximo | bola errada (%) | recálculos |")
    push!(lines, "|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for row in rows
        brute = find_row(rows; n = row.n, k = row.k, algorithm = "brute_force")
        gain = brute.mean > 0 ? brute.mean / row.mean : 0.0
        push!(lines, "| $(row.n) | $(row.k) | $(label_of(row)) | $(fmt(row.mean * 1e6)) | $(fmt(row.median * 1e6)) | $(fmt(row.p99 * 1e6)) | $(fmt(gain)) | $(fmt(row.mean_error)) | $(fmt(row.max_error)) | $(fmt(row.wrong)) | $(row.recalcs) |")
    end
    open(joinpath(ROOT, "docs", "tabela_resumo.md"), "w") do io
        println(io, join(lines, "\n"))
    end

    open(joinpath(ROOT, "docs", "numeros.txt"), "w") do io
        println(io, "linhas $(length(rows))")
        println(io, "frames $(rows[1].frames) reps $(rows[1].repetitions)")
        for key in ((10, 5, "euler"), (10, 5, "rk4"), (100, 30, "euler"), (100, 30, "rk4"), (100000, 30, "euler"), (100000, 30, "rk4"))
            n, k, method = key
            row = find_row(rows; n = n, k = k, algorithm = "tracking", method = method)
            brute = find_row(rows; n = n, k = k, algorithm = "brute_force")
            scheduled = row.repetitions * count(i -> i % k == 0, 1:row.frames)
            println(io, "N=$n K=$k $method mean_us=$(row.mean * 1e6) median_us=$(row.median * 1e6) p99_us=$(row.p99 * 1e6) brute_us=$(brute.mean * 1e6) gain=$(brute.mean / row.mean) brute_over_k_us=$(brute.mean / k * 1e6) err=$(row.mean_error) max=$(row.max_error) wrong=$(row.wrong) recalcs=$(row.recalcs) scheduled_frames=$(scheduled)")
        end
        println(io, "--- criterio erro_medio<=2 e bola_errada<=5, menor tempo ---")
        eligible = NamedTuple[]
        for row in rows
            if row.mean_error <= 2.0 && row.wrong <= 5.0
                push!(eligible, row)
            end
        end
        if isempty(eligible)
            println(io, "nenhuma")
        else
            best = eligible[argmin([row.mean for row in eligible])]
            println(io, "melhor N=$(best.n) K=$(best.k) $(label_of(best)) mean_us=$(best.mean * 1e6) err=$(best.mean_error) wrong=$(best.wrong)")
            println(io, "elegiveis $(length(eligible))")
        end
        println(io, "--- elegiveis com K>1 e N>=100 ---")
        for row in eligible
            if row.k > 1 && row.n >= 100
                println(io, "N=$(row.n) K=$(row.k) $(label_of(row)) mean_us=$(row.mean * 1e6) err=$(row.mean_error) wrong=$(row.wrong)")
            end
        end
        println(io, "--- N=10 todos os metodos, menor tempo ---")
        small = filter(row -> row.n == 10 && row.k == 30, rows)
        for row in small
            println(io, "$(label_of(row)) mean_us=$(row.mean * 1e6) err=$(row.mean_error) wrong=$(row.wrong)")
        end
        println(io, "--- raio ---")
        for n in sort(unique(row.n for row in rows))
            println(io, "N=$n radius=$(find_row(rows; n = n, k = 1, algorithm = "brute_force").radius)")
        end
    end
end

mkpath(IMG)
rows = load_rows(CSV)
write_time_figure(rows)
write_pareto(rows)
write_error_figures(rows)
write_table_and_notes(rows)
println("figuras em $IMG")
println(read(joinpath(ROOT, "docs", "numeros.txt"), String))
