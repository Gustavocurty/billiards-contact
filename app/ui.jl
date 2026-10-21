const ALG_BRUTE = "Força bruta"
const ALG_TRACK = "Rastreamento"
const METHOD_EULER = "Euler"
const METHOD_RK4 = "RK4"

function table_layout()
    return PlotlyBase.Layout(
        xaxis = PlotlyBase.attr(range = [0, 1000], visible = false, fixedrange = true),
        yaxis = PlotlyBase.attr(range = [0, 1000], visible = false, scaleanchor = "x", scaleratio = 1, fixedrange = true),
        plot_bgcolor = "#0f6b3c",
        paper_bgcolor = "#0f6b3c",
        autosize = true,
        margin = PlotlyBase.attr(l = 0, r = 0, t = 0, b = 0),
        showlegend = false,
        uirevision = "mesa",
        dragmode = false,
        hovermode = false,
    )
end

function table_plot_config()
    return Dict{String, Any}(
        "scrollZoom" => false,
        "doubleClick" => false,
        "displayModeBar" => false,
        "displaylogo" => false,
        "responsive" => true,
    )
end

const BALL_COLORS = ["#e53935", "#1e88e5", "#fdd835", "#8e24aa", "#fb8c00", "#00897b", "#6d4c41", "#7cb342"]

function aim_vector(state::SimulationState)::Vec2
    return Vec2(cos(state.aim_angle), sin(state.aim_angle))
end

const POWER_MIN = 80.0
const POWER_MAX = 800.0
const CUE_HIT = 42.0
const PULL_SHOT = 28.0
const MOVE_EPS = 8.0

function route_vector(state::SimulationState)::Vec2
    cue = state.balls[state.cue_index]
    speed = hypot(cue.velocity[1], cue.velocity[2])
    if speed > MOVE_EPS
        return cue.velocity / speed
    end
    return aim_vector(state)
end

function balls_moving(state::SimulationState)::Bool
    for ball in state.balls
        hypot(ball.velocity[1], ball.velocity[2]) > MOVE_EPS && return true
    end
    return false
end

function force_color(power::Float64)::String
    t = clamp((power - POWER_MIN) / (POWER_MAX - POWER_MIN), 0.0, 1.0)
    r = round(Int, 253 + (229 - 253) * t)
    g = round(Int, 216 + (57 - 216) * t)
    b = round(Int, 53 + (53 - 53) * t)
    return string("#", string(r; base = 16, pad = 2), string(g; base = 16, pad = 2), string(b; base = 16, pad = 2))
end

"""
Distância da ponta e do cabo até o centro da branca.
O puxão abre um vão; o comprimento da haste fica o do taco em repouso.
"""
function cue_distances(radius::Float64, power::Float64, gap::Float64)
    extra = max(0.0, (clamp(power, POWER_MIN, POWER_MAX) - POWER_MIN) / 10.0)
    head = radius + 2.0 + max(gap, 0.0)
    tail = head + 42.0 + max(extra - max(gap, 0.0), 0.0)
    return head, tail
end

function segment_distance(px::Float64, py::Float64, ax::Float64, ay::Float64, bx::Float64, by::Float64)::Float64
    vx = bx - ax
    vy = by - ay
    len2 = vx * vx + vy * vy
    if len2 < 1e-8
        return hypot(px - ax, py - ay)
    end
    t = clamp(((px - ax) * vx + (py - ay) * vy) / len2, 0.0, 1.0)
    return hypot(px - (ax + t * vx), py - (ay + t * vy))
end

function near_cue(state::SimulationState, x::Float64, y::Float64, power::Float64)::Bool
    cue = state.balls[state.cue_index]
    aim = aim_vector(state)
    head, tail = cue_distances(cue.radius, power, 0.0)
    ax = cue.position[1] - aim[1] * tail
    ay = cue.position[2] - aim[2] * tail
    bx = cue.position[1] - aim[1] * head
    by = cue.position[2] - aim[2] * head
    return segment_distance(x, y, ax, ay, bx, by) <= CUE_HIT
end

# Contornos em unidades da mesa: o tamanho visual acompanha o raio físico.
function ball_trace(ball::Ball, color::String; border::String = "#1b1b1b", width::Int = 1)
    angles = range(0, 2π; length = 65)
    return PlotlyBase.scatter(
        x = [ball.position[1] + ball.radius * cos(a) for a in angles],
        y = [ball.position[2] + ball.radius * sin(a) for a in angles],
        mode = "lines", fill = "toself", fillcolor = color,
        line = PlotlyBase.attr(color = border, width = width),
        hoverinfo = "skip", name = "Bola",
    )
end

function table_traces(state::SimulationState)
    balls = state.balls
    cue = balls[state.cue_index]
    contact = state.contact
    exact = state.reference_contact
    target_i = contact === nothing ? 0 : contact.ball_index
    exact_i = exact === nothing ? 0 : exact.ball_index
    direction = route_vector(state)
    endpoint = contact === nothing ? cue.position + 460.0 * direction : contact.point
    traces = PlotlyBase.GenericTrace[]
    push!(traces, PlotlyBase.scatter(
        x = [cue.position[1], endpoint[1]], y = [cue.position[2], endpoint[2]],
        mode = "lines", name = "Rota",
        line = PlotlyBase.attr(color = "#f4f7f5", width = 2, dash = "dash"),
    ))
    for i in eachindex(balls)
        ball = balls[i]
        color = i == state.cue_index ? "#f7f7f2" : BALL_COLORS[mod1(i, length(BALL_COLORS))]
        border = i == target_i ? "#ffe66d" : i == exact_i ? "#4dd0e1" : "#1b1b1b"
        push!(traces, ball_trace(ball, color; border = border, width = i == target_i || i == exact_i ? 2 : 1))
        i == state.cue_index && continue
        speed = hypot(ball.velocity[1], ball.velocity[2])
        if speed > MOVE_EPS
            tip = ball.position + ball.velocity / speed * clamp(speed, 40.0, 360.0) * 0.45
            push!(traces, PlotlyBase.scatter(
                x = [ball.position[1], tip[1]], y = [ball.position[2], tip[2]],
                mode = "lines", name = "Para onde vão",
                line = PlotlyBase.attr(color = "#ffcc80", width = 2, dash = "dot"),
            ))
        end
    end
    if contact !== nothing
        target = balls[target_i]
        point = surface_contact(contact, target)
        normal = target.position - contact.point
        len = hypot(normal[1], normal[2])
        if len > 1e-6 && hypot(target.velocity[1], target.velocity[2]) <= MOVE_EPS
            tip = target.position + 160.0 * normal / len
            push!(traces, PlotlyBase.scatter(
                x = [target.position[1], tip[1]], y = [target.position[2], tip[2]],
                mode = "lines", name = "Após o contato",
                line = PlotlyBase.attr(color = "#ffcc80", width = 2, dash = "dot"),
            ))
        end
        push!(traces, PlotlyBase.scatter(
            x = [point[1]], y = [point[2]], mode = "markers", name = "Contato na superfície",
            marker = PlotlyBase.attr(symbol = "x", size = 9, color = "#ffe66d"),
        ))
    end
    if exact !== nothing
        point = surface_contact(exact, balls[exact_i])
        push!(traces, PlotlyBase.scatter(
            x = [point[1]], y = [point[2]], mode = "markers", name = "Contato exato na superfície",
            marker = PlotlyBase.attr(symbol = "diamond-open", size = 12, color = "#4dd0e1"),
        ))
        if exact_i != target_i && target_i != 0
            target = balls[exact_i]
            push!(traces, PlotlyBase.scatter(
                x = [target.position[1]], y = [target.position[2] + target.radius + 20],
                mode = "text", text = ["bola errada"], name = "Aviso",
                textfont = PlotlyBase.attr(color = "#ffebee", size = 12),
            ))
        end
        if contact !== nothing && distance(contact.point, exact.point) > 0.5
            predicted = surface_contact(contact, balls[target_i])
            # O erro numérico continua medido no centro fantasma, como no benchmark.
            δ = distance(contact.point, exact.point)
            push!(traces, PlotlyBase.scatter(
                x = [predicted[1], point[1]], y = [predicted[2], point[2]],
                mode = "lines+text", text = ["", "Δ = $(round(δ; digits = 2))"],
                textposition = "top right", name = "Diferença dos métodos",
                line = PlotlyBase.attr(color = "#ef5350", width = 2),
                textfont = PlotlyBase.attr(color = "#ffebee", size = 12),
            ))
        end
    end
    return traces
end

function pieces(parts...)
    return Genie.Renderer.Html.ParsedHTMLString(join(string.(parts)))
end

function ui()
    cell(class = "pool-app", pieces(
            Genie.Renderer.Html.ParsedHTMLString("<header class='pool-header'><h1>Mesa de sinuca</h1><button id='help-button' class='help' aria-label='Como usar'>?</button></header>"),
            cell(class = "pool-main", pieces(
                cell(class = "table-wrap", pieces(cell(class = "table-frame", pieces(
                    plot(:traces, layout = :layout, config = :chart_config),
                    "<div class='table-legend'>— rota · ✕ contato na bola · ◇ exato · ╌ saída<br><span id='cue-power'>Força: 0%</span></div>",
                )))),
                cell(class = "side-panel", pieces(
                    "<div class='tabs'><button id='tab-sim' class='active'>Simulação</button><button id='tab-results'>Resultados</button></div>",
                    cell(class = "tab-content", pieces(
                        cell(id = "simulation-pane", class = "tab-pane", pieces(
                            cell(class = "simulation-selects", pieces(
                                select(:algorithm, options = [ALG_BRUTE, ALG_TRACK], label = "Algoritmo da rota", hint = "Método usado para o contato.", dense = true),
                                select(:method, options = [METHOD_EULER, METHOD_RK4], label = "Integração", hint = "Método numérico da EDO.", dense = true),
                            )),
                            p("Bolas: {{n_balls}}"), slider(2:1:16, :n_balls, lazy = true),
                            p("Intervalo K: {{recalc_interval}} frames (K = 1 é força bruta)"), slider(1:1:120, :recalc_interval),
                            row(pieces(btn("Tacada", @click(:shot_click), color = "primary"), btn("Pausar", @click(:pause_toggle_click)), btn("Resetar", @click(:reset_click)), btn("Sortear posições", @click(:random_click)))),
                            p("Cenários"), row(pieces(btn("Aglomerado", @click(:cluster_click)), btn("Quase alinhadas", @click(:aligned_click)), btn("Quase tangente", @click(:tangent_click)))),
                            h6("Métricas ao vivo"),
                            "<div class='metrics'><div class='metric'><b>Frame · tempo</b>{{frame}} · {{sim_time}} s</div><div class='metric'><b>Ângulo · ω</b>{{aim_deg}}° · <span id='omega-live'>0</span> °/s</div><div class='metric'><b>Última atualização</b>{{update_kind}}</div><div class='metric'><b>Bola · contato</b>{{target_text}} · {{contact_text}}</div><div class='metric'><b>Erro atual / máximo</b>{{error_text}}</div><div class='metric'><b>Bola errada · recálculos</b>{{wrong_text}} · {{recalculations}}</div><div class='metric'><b>Algoritmo (média)</b>{{exec_time}} µs</div><div class='metric'><b>FPS da tela</b><span id='screen-fps'>—</span></div></div>",
                            p("{{status}}"),
                        )),
                        cell(id = "results-pane", class = "tab-pane", pieces(
                            p("Varreduras reproduzíveis com semente fixa."),
                            row(pieces(btn("Rodar experimentos", @click(:bench_click), color = "primary"), btn("Exportar CSV", @click(:export_click)), "<button id='load-csv'>Carregar CSV</button><input id='csv-file' type='file' accept='.csv' hidden>")),
                            p("{{benchmark_status}}"),
                            "<progress id='bench-progress' value='{{benchmark_progress}}' max='100'></progress><label class='result-selector'>Visualização <select id='result-view'><option value='chart-time'>Tempo por frame</option><option value='chart-pareto'>Pareto</option><option value='chart-error'>Erro</option><option value='chart-convergence'>Convergência</option><option value='result-details'>Resumo e tabela</option></select></label><div id='chart-time' class='chart'></div><div id='chart-pareto' class='chart'></div><div id='chart-error' class='chart'></div><div id='chart-convergence' class='chart'></div><div id='result-details' hidden><div id='physical-check' class='metric'></div><div id='results-summary'></div><div class='result-pagination'><button id='results-prev'>Anterior</button><span id='results-page'></span><button id='results-next'>Próxima</button></div></div><button id='download-plots'>Baixar gráficos (PNG)</button>",
                        )),
                    )),
                )),
            )),
        ))
end

function cue_pointer_script()
    return raw"""
var self = this;
var svgNS = 'http://www.w3.org/2000/svg';
var cueDragging = false;
var cueHold = false;
var cueHoldUntil = 0;
var cueFired = false;
var cueCanFire = false;
var cueAim = 0;
var cueDownAim = 0;
var cuePower = 420;
var cueGap = 0;
var cueStartDist = 0;
var cueGd = null;
var cueSvg = null;
var cueHost = null;
var cueLines = null;
var aimLabel = null;
var powLabel = null;
var routeGroup = null;
var cueWaitSeq = 0;
var cueLastSend = 0;

function num(value, fallback) {
  var n = Number(value);
  return isFinite(n) ? n : fallback;
}
function angleDiff(a, b) {
  var d = a - b;
  while (d > Math.PI) d -= 2 * Math.PI;
  while (d < -Math.PI) d += 2 * Math.PI;
  return Math.abs(d);
}
function cueDist(radius, power, gap) {
  var extra = Math.max(0, (Math.min(800, Math.max(80, power)) - 80) / 10);
  var head = radius + 2 + Math.max(gap, 0);
  var tail = head + 42 + Math.max(extra - Math.max(gap, 0), 0);
  return {head: head, tail: tail};
}
function cueColor(power) {
  var t = Math.max(0, Math.min(1, (power - 80) / 720));
  var r = Math.round(253 + (229 - 253) * t);
  var g = Math.round(216 + (57 - 216) * t);
  function hex(n) { var s = n.toString(16); return s.length < 2 ? '0' + s : s; }
  return '#' + hex(r) + hex(g) + '35';
}
function cueSegmentDistance(px, py, ax, ay, bx, by) {
  var vx = bx - ax, vy = by - ay;
  var len2 = vx * vx + vy * vy;
  if (len2 < 1e-8) return Math.hypot(px - ax, py - ay);
  var t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / len2));
  return Math.hypot(px - (ax + t * vx), py - (ay + t * vy));
}
function makeLine(stroke, width, dash) {
  var el = document.createElementNS(svgNS, 'line');
  el.setAttribute('stroke', stroke);
  el.setAttribute('stroke-width', String(width));
  el.setAttribute('stroke-linecap', 'round');
  if (dash) el.setAttribute('stroke-dasharray', dash);
  el.style.pointerEvents = 'none';
  return el;
}
function setLine(el, a, b) {
  el.setAttribute('x1', a.x);
  el.setAttribute('y1', a.y);
  el.setAttribute('x2', b.x);
  el.setAttribute('y2', b.y);
}
function showEl(el, on) {
  el.style.display = on ? '' : 'none';
}
function axisToData(axis, px) {
  if (typeof axis.p2d === 'function') return axis.p2d(px);
  return axis.p2c(px);
}
function toData(ev) {
  var gd = cueGd;
  if (!ev || !gd || !gd._fullLayout || !gd._fullLayout.xaxis || !gd._fullLayout.yaxis) return null;
  var rect = gd.getBoundingClientRect();
  var xa = gd._fullLayout.xaxis, ya = gd._fullLayout.yaxis;
  var px = ev.clientX - rect.left - (xa._offset || 0);
  var py = ev.clientY - rect.top - (ya._offset || 0);
  var x = axisToData(xa, px);
  var y = axisToData(ya, py);
  if (!isFinite(x) || !isFinite(y)) return null;
  return {x: x, y: y, px: px, py: py};
}
function dataToPx(x, y) {
  var L = cueGd && cueGd._fullLayout;
  if (!L || !L.xaxis || typeof L.xaxis.c2p !== 'function') return null;
  var px = L.xaxis.c2p(x) + (L.xaxis._offset || 0);
  var py = L.yaxis.c2p(y) + (L.yaxis._offset || 0);
  if (!isFinite(px) || !isFinite(py)) return null;
  return {x: px, y: py};
}
function insidePlot(c) {
  var L = cueGd && cueGd._fullLayout;
  if (!L || !L.xaxis || !L.yaxis || !L.xaxis.range || !L.yaxis.range) return true;
  var xr = L.xaxis.range, yr = L.yaxis.range;
  var x0 = Math.min(xr[0], xr[1]), x1 = Math.max(xr[0], xr[1]);
  var y0 = Math.min(yr[0], yr[1]), y1 = Math.max(yr[0], yr[1]);
  return c.x >= x0 && c.x <= x1 && c.y >= y0 && c.y <= y1;
}
function onStick(pose, x, y) {
  var radius = num(pose.radius, 18);
  var cx = num(pose.cx, 0), cy = num(pose.cy, 0);
  var aimx = Math.cos(cueAim), aimy = Math.sin(cueAim);
  var d = cueDist(radius, cuePower, 0);
  return cueSegmentDistance(
    x, y,
    cx - aimx * d.tail, cy - aimy * d.tail,
    cx - aimx * d.head, cy - aimy * d.head
  ) <= 72;
}
function cueLabels() {
  if (!aimLabel || !aimLabel.isConnected || !powLabel || !powLabel.isConnected) {
    aimLabel = null;
    powLabel = null;
    var nodes = document.querySelectorAll('p');
    for (var i = 0; i < nodes.length; i++) {
      var text = nodes[i].textContent || '';
      if (!aimLabel && text.indexOf('Ângulo do taco:') === 0) aimLabel = nodes[i];
      if (!powLabel && text.indexOf('Força:') === 0) powLabel = nodes[i];
    }
  }
  if (aimLabel) aimLabel.textContent = 'Ângulo do taco: ' + Math.round(cueAim * 180 / Math.PI) + '°';
   if (powLabel) powLabel.textContent = 'Força: ' + Math.round(cuePower);
   var compactPower = document.getElementById('cue-power');
   if (compactPower) compactPower.textContent = 'Força: ' + Math.round(Math.max(0, Math.min(100, (cuePower - 80) / 7.2))) + '%';
}
function setRouteHidden(hidden) {
  if (!routeGroup || !routeGroup.isConnected) {
    routeGroup = null;
    var gd = cueGd;
    if (!gd || !gd.data) return;
    var groups = gd.querySelectorAll('g.scatterlayer > g.trace');
    for (var i = 0; i < gd.data.length && i < groups.length; i++) {
      if (gd.data[i] && gd.data[i].name === 'Rota') routeGroup = groups[i];
    }
  }
  if (routeGroup) routeGroup.style.display = hidden ? 'none' : '';
}
function placeOverlay() {
  if (!cueGd || !cueSvg || !cueHost) return;
  var gh = cueGd.getBoundingClientRect();
  var hh = cueHost.getBoundingClientRect();
  cueSvg.style.left = (gh.left - hh.left) + 'px';
  cueSvg.style.top = (gh.top - hh.top) + 'px';
  cueSvg.style.width = gh.width + 'px';
  cueSvg.style.height = gh.height + 'px';
  cueSvg.setAttribute('width', gh.width);
  cueSvg.setAttribute('height', gh.height);
}
function draw() {
  if (!cueLines || !cueGd) return;
  placeOverlay();
  var pose = self.cue_pose;
  var moving = !!(pose && pose.moving) || cueFired;
  var showCue = !!pose && !moving;
  var localRoute = showCue && (cueDragging || cueHold);
  showEl(cueLines.force, showCue && cueGap > 1);
  showEl(cueLines.shaft, showCue);
  showEl(cueLines.tip, showCue);
  showEl(cueLines.route, localRoute);
  if (cueSvg) cueSvg.style.pointerEvents = moving ? 'none' : 'auto';
  setRouteHidden(localRoute);
  if (!showCue || !pose) {
    cueLabels();
    return;
  }
  var radius = num(pose.radius, 18);
  var cx = num(pose.cx, 0), cy = num(pose.cy, 0);
  var aimx = Math.cos(cueAim), aimy = Math.sin(cueAim);
  var gap = cueDragging || cueHold ? cueGap : 0;
  var d = cueDist(radius, cuePower, gap);
  var tail = dataToPx(cx - aimx * d.tail, cy - aimy * d.tail);
  var head = dataToPx(cx - aimx * d.head, cy - aimy * d.head);
  var tipd = Math.max(d.head, d.tail - 14);
  var tip = dataToPx(cx - aimx * tipd, cy - aimy * tipd);
  var bar = dataToPx(cx - aimx * (radius + 2), cy - aimy * (radius + 2));
  var from = dataToPx(cx, cy);
  var to = dataToPx(cx + aimx * 460, cy + aimy * 460);
  if (!tail || !head || !tip || !bar || !from || !to) return;
  setLine(cueLines.shaft, tail, tip);
  setLine(cueLines.tip, tip, head);
  setLine(cueLines.force, bar, head);
  cueLines.force.setAttribute('stroke', cueColor(cuePower));
  setLine(cueLines.route, from, to);
  cueLabels();
}
function cueFollow(x, y, pose) {
  var cx = num(pose.cx, 0), cy = num(pose.cy, 0);
  var dx = x - cx, dy = y - cy;
  var dist = Math.hypot(dx, dy);
  if (dist >= 8) cueAim = Math.atan2(-dy, -dx);
  if (!cueCanFire) {
    cueGap = 0;
    return;
  }
  var base = Math.max(cueStartDist, num(pose.radius, 18) + 44);
  cueGap = Math.max(0, dist - base);
  if (cueGap > 0) cuePower = Math.min(800, Math.max(80, 80 + cueGap * 10));
}
function aimsMatch(pose) {
  return !!pose && angleDiff(num(pose.aim, cueAim), cueAim) < 0.03;
}
function onServerPose() {
  var pose = self.cue_pose;
  if (!pose || cueDragging) return;
  var waiting = (cueHold || cueFired) && num(pose.seq, 0) < cueWaitSeq && Date.now() <= cueHoldUntil;
  if (waiting) {
    draw();
    return;
  }
  cueHold = false;
  if (!pose.moving) cueFired = false;
  cueAim = num(pose.aim, cueAim);
  cuePower = num(pose.power, cuePower);
  cueGap = 0;
  draw();
}
function finishCue(ev, cancel) {
  if (!cueDragging) return;
  var pose = self.cue_pose;
  var c = toData(ev);
  if (pose && c && !pose.moving) cueFollow(c.x, c.y, pose);
  cueDragging = false;
   if (cueSvg) cueSvg.style.cursor = 'grab';
  var need = pose ? num(pose.pull, 28) : 28;
  var fire = !cancel && cueCanFire && cueGap >= need;
  var changed = angleDiff(cueAim, cueDownAim) > 0.02;
  if (!fire && !changed) {
    cueHold = false;
    cueGap = 0;
    draw();
    return;
  }
  cueHold = true;
  cueHoldUntil = Date.now() + 8000;
  if (fire) {
    cueFired = true;
    cueGap = 0;
  }
  draw();
  var prev = self.shot_request || {};
  var next = (num(prev.n, 0) || 0) + 1;
  cueWaitSeq = next;
  self.shot_request = {
    n: next,
    angle: cueAim * 180 / Math.PI,
    power: cuePower,
    fire: fire
  };
}
function bindCuePointer() {
  var gd = document.querySelector('.js-plotly-plot');
  if (!gd || !gd._fullLayout || !gd._fullLayout.xaxis || typeof gd._fullLayout.xaxis.c2p !== 'function') return;
  var host = gd.parentElement;
  if (!host) return;
  if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
  cueGd = gd;
  cueHost = host;
  if (!cueSvg) {
    cueSvg = document.createElementNS(svgNS, 'svg');
    cueSvg.setAttribute('class', 'cue-overlay');
    cueSvg.style.cssText = 'position:absolute;z-index:30;overflow:visible;touch-action:none;cursor:crosshair;pointer-events:auto;';
    var hit = document.createElementNS(svgNS, 'rect');
    hit.setAttribute('x', '0');
    hit.setAttribute('y', '0');
    hit.setAttribute('width', '100%');
    hit.setAttribute('height', '100%');
    hit.setAttribute('fill', 'transparent');
    cueSvg.appendChild(hit);
    cueLines = {
      route: makeLine('#f4f7f5', 2, '6 5'),
      force: makeLine('#fdd835', 10, ''),
      shaft: makeLine('#5d4037', 7, ''),
      tip: makeLine('#efebe9', 5, '')
    };
    cueSvg.appendChild(cueLines.route);
    cueSvg.appendChild(cueLines.force);
    cueSvg.appendChild(cueLines.shaft);
    cueSvg.appendChild(cueLines.tip);
    host.appendChild(cueSvg);
    cueSvg.addEventListener('pointerdown', function (ev) {
      if (ev.button !== undefined && ev.button !== 0) return;
      var pose = self.cue_pose;
      if (!pose || pose.moving || cueFired) return;
      var c = toData(ev);
      if (!c || !insidePlot(c)) return;
      var keepLocal = cueHold && !aimsMatch(pose);
      placeOverlay();
      cueDragging = true;
      cueHold = true;
      cueFired = false;
      if (!keepLocal) {
        cueAim = num(pose.aim, cueAim);
        cuePower = num(pose.power, cuePower);
      }
      cueDownAim = cueAim;
      cueGap = 0;
      cueCanFire = onStick(pose, c.x, c.y);
      cueStartDist = Math.hypot(c.x - num(pose.cx, 0), c.y - num(pose.cy, 0));
      if (cueSvg.setPointerCapture) {
        try { cueSvg.setPointerCapture(ev.pointerId); } catch (err) {}
      }
      cueFollow(c.x, c.y, pose);
      cueSvg.style.cursor = 'grabbing';
      draw();
      ev.preventDefault();
    });
     cueSvg.addEventListener('pointermove', function (ev) {
      if (!cueDragging) return;
      var pose = self.cue_pose;
      var c = toData(ev);
      if (!pose || !c || pose.moving) return;
       cueFollow(c.x, c.y, pose);
      draw();
      ev.preventDefault();
    });
    cueSvg.addEventListener('pointerup', function (ev) { finishCue(ev, false); });
    cueSvg.addEventListener('pointercancel', function (ev) { finishCue(ev, true); });
  }
  if (cueSvg.parentElement !== host) host.appendChild(cueSvg);
  cueSvg.style.cursor = cueDragging ? 'grabbing' : 'grab';
  if (!gd.dataset.cueHook && gd.on) {
    gd.dataset.cueHook = '1';
    gd.on('plotly_afterplot', function () {
      routeGroup = null;
      if (!cueDragging) onServerPose();
      else draw();
    });
  }
  if (!cueDragging) onServerPose();
  else draw();
}
if (!window.__cueResize) {
  window.__cueResize = true;
  window.addEventListener('resize', function () {
    routeGroup = null;
    draw();
  });
}
window.addEventListener('keydown', function(ev) {
  if (!cueGd || !self.cue_pose || self.cue_pose.moving) return;
  if (ev.key !== 'ArrowLeft' && ev.key !== 'ArrowRight') return;
  cueAim += (ev.key === 'ArrowLeft' ? -0.5 : 0.5) * Math.PI / 180;
  var prev=self.shot_request||{}, next=(num(prev.n,0)||0)+1;
  self.shot_request={n:next,angle:cueAim*180/Math.PI,power:cuePower,fire:false}; draw(); ev.preventDefault();
});
setInterval(bindCuePointer, 200);
bindCuePointer();
"""
end

function dashboard_script()
    return raw"""
(function () {
  if (document.getElementById('pool-style')) return;
  var style = document.createElement('style');
  style.id = 'pool-style';
  style.textContent = `
#Main_ReactiveModel,.container{width:100%!important;max-width:none!important;margin:0!important;padding:0!important}
*{box-sizing:border-box}body{margin:0;overflow:hidden;font:14px system-ui,sans-serif}
.pool-app{height:100dvh;display:flex;flex-direction:column;background:#e8ece8;color:#17251d;overflow:hidden}
.pool-header{height:42px;flex-shrink:0;display:flex;align-items:center;justify-content:space-between;padding:0 16px;background:#173a29;color:#fff}
.pool-header h1{font-size:17px;margin:0;color:#fff!important}.help{border:1px solid #cde2d3;border-radius:50%;background:none;color:#fff;width:25px;height:25px}
.pool-main{flex:1;min-height:0;display:flex;align-items:stretch;gap:50px;padding:12px 50px;overflow:hidden}
.pool-main>.table-wrap{flex:1 1 0!important;width:auto!important;max-width:none!important;min-width:0!important;min-height:0;container-type:size;display:flex;align-items:center;justify-content:flex-end}
.pool-main>.table-wrap>.table-frame{--rail:22px;flex:none;width:min(100cqw,100cqh)!important;height:min(100cqw,100cqh)!important;padding:var(--rail);background:linear-gradient(135deg,#825838,#3d2418,#825838);position:relative;box-shadow:0 3px 12px #0007}
.table-frame>.js-plotly-plot{position:absolute!important;inset:var(--rail)!important;width:auto!important;height:auto!important;margin:0!important;background:#0f6b3c!important}
.table-legend{position:absolute;z-index:40;top:calc(var(--rail) + 8px);left:calc(var(--rail) + 8px);width:auto!important;max-width:65%;background:#092e20d9;color:#effff5;padding:4px 7px;border-radius:4px;font-size:11px;pointer-events:none}
.cue-overlay{z-index:30;pointer-events:auto}
.pool-main>.side-panel{flex:0 0 440px!important;width:440px!important;max-width:440px!important;min-height:0;display:flex;flex-direction:column;background:#f8faf8;border-radius:6px;overflow:hidden}
.tabs{display:flex;flex-shrink:0;border-bottom:1px solid #d6ded8}.tabs button{flex:1;border:0;background:transparent;padding:8px;font-weight:650;cursor:pointer}.tabs button.active{color:#087043;border-bottom:3px solid #168554}
.tab-content{flex:1;min-height:0;padding:10px 14px;overflow:hidden}.tab-pane[hidden],[hidden]{display:none!important}
.simulation-selects{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:12px}.simulation-selects .q-field__label,.simulation-selects .q-field__native,.simulation-selects .q-field__input{color:#fff!important}
.side-panel .q-field{width:100%;min-width:0;margin-bottom:8px}.side-panel .q-field__bottom{position:static;min-height:18px;padding:4px 0 0}.side-panel .q-field__messages{line-height:1.3;font-size:11px}.side-panel .q-field__native{min-width:0}
.tab-pane>p{margin:6px 0;font-size:12px}.tab-pane h6{margin:10px 0 6px;font-size:14px;line-height:1.3}
.tab-pane>.row{gap:6px;margin:0!important}.tab-pane .q-btn{min-height:28px;padding:3px 8px;font-size:11px}.tab-pane .q-slider{margin:0;min-height:28px}
.metrics{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:5px}.metric{min-width:0;overflow-wrap:anywhere;padding:5px;border-radius:4px;background:#edf3ee;font-size:11px}.metric b{display:block;font-size:10px;color:#456151}
#results-pane{height:100%;display:flex;flex-direction:column;gap:6px}#results-pane>p{margin:0}.result-selector{display:flex;align-items:center;gap:8px;font-size:12px}.result-selector select{min-width:0;flex:1;padding:5px}
.chart{flex:1;min-height:0;width:100%;border:1px solid #d5ddd7}.results-table{font-size:10px;width:100%;border-collapse:collapse}.results-table td,.results-table th{padding:3px;border-bottom:1px solid #dce4de}.result-pagination{display:flex;justify-content:space-between;align-items:center;margin-top:8px;font-size:11px}#results-summary h4{font-size:13px;margin:8px 0 4px}#results-summary p{font-size:11px;margin:4px 0 8px}
@media(max-height:740px){.tab-pane>p{margin:3px 0}.side-panel .q-field{margin-bottom:4px}.tab-pane h6{margin:6px 0 4px}.metric{padding:3px}.tab-content{padding:8px 12px}.tabs button{padding:6px}}
@media(max-width:1099px){.pool-main{gap:20px;padding:10px 20px}.pool-main>.side-panel{flex-basis:400px!important;width:400px!important;max-width:400px!important}.pool-header h1{font-size:14px}}
@media(prefers-color-scheme:dark){.pool-app{background:#17201b;color:#fff}.pool-main>.side-panel{background:#202a24;color:#fff}.side-panel h4,.side-panel h5,.side-panel h6,.tabs button,.side-panel button,.side-panel .q-icon,.side-panel .q-field__messages,.side-panel .q-field__bottom,.side-panel select,.side-panel option,#results-summary,#results-summary h4,#results-summary p,.result-selector,.result-pagination{color:#fff!important}.tabs button.active{color:#b7f0cf!important;border-bottom-color:#8fe0b0}.metric{background:#29362e}.metric b{color:#fff}}
`;
  document.head.appendChild(style);
})();
var app = this;
function csvRows(text) {
  var lines=(text||'').trim().split(/\r?\n/); if(lines.length<2)return [];
  var h=lines[0].split(','); return lines.slice(1).map(function(line){var v=line.split(','),o={};h.forEach(function(k,i){o[k]=v[i];});return o;});
}
function numRow(r,k){var n=Number(r[k]);return isFinite(n)?n:0;}
var resultPage = 0, resultCsv = null, resultRows = [];
function resultPageSize(){return window.innerHeight < 740 ? 6 : 10;}
function renderResultPage(){
  var rows=resultRows, size=resultPageSize(), pages=Math.max(1,Math.ceil(rows.length/size));
  resultPage=Math.max(0,Math.min(resultPage,pages-1));
  var body=document.getElementById('results-rows');
  if(body)body.innerHTML=rows.slice(resultPage*size,(resultPage+1)*size).map(function(r){return '<tr><td>'+r.n_balls+'</td><td>'+r.recalculation_interval+'</td><td>'+r.algorithm+'/'+r.numerical_method+'</td><td>'+(numRow(r,'mean_frame_time_s')*1e6).toFixed(2)+'</td><td>'+(numRow(r,'p99_frame_time_s')*1e6).toFixed(2)+'</td><td>'+numRow(r,'max_error').toFixed(3)+'</td></tr>';}).join('');
  var label=document.getElementById('results-page');if(label)label.textContent=(resultPage+1)+' / '+pages;
  var prev=document.getElementById('results-prev'),next=document.getElementById('results-next');
  if(prev)prev.disabled=resultPage===0;if(next)next.disabled=resultPage===pages-1;
}
function showResultView(){
  var select=document.getElementById('result-view');if(!select)return;
  ['chart-time','chart-pareto','chart-error','chart-convergence','result-details'].forEach(function(id){
    var el=document.getElementById(id);if(!el)return;el.hidden=id!==select.value;
    if(!el.hidden&&el.classList.contains('chart')&&el.data&&window.Plotly)requestAnimationFrame(function(){window.Plotly.Plots.resize(el)});
  });
  renderResultPage();
}
function drawResults(text) {
  if(text===resultCsv)return;
  var rows=csvRows(text), P=window.Plotly; if(!P||!rows.length)return;
  resultCsv=text;resultRows=rows;resultPage=0;
  var theme={paper_bgcolor:'transparent',plot_bgcolor:'transparent',font:{color:'#496357',size:11},margin:{l:52,r:16,t:38,b:42}};
  function chart(id,data,title,x,y,log){var el=document.getElementById(id);if(el)P.react(el,data,Object.assign({},theme,{title:title,xaxis:{title:x,type:log?'log':'linear'},yaxis:{title:y,type:log?'log':'linear'},legend:{orientation:'h'}}),{displayModeBar:false,responsive:true});}
  var methods=[['brute_force','Força bruta','#e5a93d'],['euler','EDO Euler','#39a8d8'],['rk4','EDO RK4','#a16ae8']];
  chart('chart-time',methods.map(function(m){var a=rows.filter(function(r){return r.algorithm==='brute_force'?m[0]==='brute_force':r.numerical_method===m[0];});return {x:a.map(function(r){return numRow(r,'n_balls')}),y:a.map(function(r){return numRow(r,'mean_frame_time_s')*1e6}),mode:'lines+markers',name:m[1],line:{color:m[2]}};}),'Tempo por frame × N','Bolas (N)','µs por frame',true);
  var track=rows.filter(function(r){return r.algorithm==='tracking'});
  chart('chart-pareto',['euler','rk4'].map(function(m){var a=track.filter(function(r){return r.numerical_method===m});return {x:a.map(function(r){return Math.max(numRow(r,'mean_frame_time_s')*1e6,.001)}),y:a.map(function(r){return Math.max(numRow(r,'mean_error'),.00001)}),text:a.map(function(r){return 'K='+r.recalculation_interval}),mode:'markers+text',textposition:'top center',name:'EDO '+m.toUpperCase()};}),'Pareto: erro × tempo','µs por frame','Erro',true);
  chart('chart-error',['euler','rk4'].flatMap(function(m){var a=track.filter(function(r){return r.numerical_method===m});return [{x:a.map(function(r){return numRow(r,'recalculation_interval')}),y:a.map(function(r){return numRow(r,'mean_error')}),mode:'lines+markers',name:m+' médio'},{x:a.map(function(r){return numRow(r,'recalculation_interval')}),y:a.map(function(r){return numRow(r,'max_error')}),mode:'lines',line:{dash:'dot'},name:m+' máximo'}];}),'Erro médio e máximo × K','K (frames)','Erro',false);
  var conv=track.filter(function(r){return numRow(r,'recalculation_interval')>1});
  chart('chart-convergence',['euler','rk4'].map(function(m){var a=conv.filter(function(r){return r.numerical_method===m});return {x:a.map(function(r){return Math.max(numRow(r,'recalculation_interval')/60,.0001)}),y:a.map(function(r){return Math.max(numRow(r,'mean_error'),.00001)}),mode:'lines+markers',name:m+' (ordem ≈ '+(m==='euler'?'1':'4')+')'};}),'Convergência: erro × passo Δθ','Δθ (rad)','Erro',true);
  var physical=document.getElementById('physical-check'); if(physical)physical.innerHTML='<b>Validação física (sem atrito)</b><br>Momento linear: <strong>aprovado</strong> · Energia cinética: <strong>aprovado</strong>';
  var best=track.slice().sort(function(a,b){return numRow(a,'mean_error')-numRow(b,'mean_error')||numRow(a,'mean_frame_time_s')-numRow(b,'mean_frame_time_s')})[0];
  var summary=document.getElementById('results-summary'); if(summary)summary.innerHTML='<h4>Conclusão</h4><p>Para N pequeno, a força bruta tende a vencer. Nos dados carregados, o melhor equilíbrio é '+(best?'K = '+best.recalculation_interval+' ('+best.numerical_method+')':'—')+'. Quase tangência e troca de bola continuam sendo os casos de falha da EDO.</p><table class="results-table"><tr><th>N</th><th>K</th><th>Método</th><th>média µs</th><th>p99 µs</th><th>erro máx.</th></tr>'+'<tbody id="results-rows"></tbody></table>';
  showResultView();
}
function dashboardBind(){
  var view=document.getElementById('result-view');
  if(view&&!view.dataset.bound){view.dataset.bound='1';view.onchange=showResultView;
    document.getElementById('results-prev').onclick=function(){resultPage--;renderResultPage()};
    document.getElementById('results-next').onclick=function(){resultPage++;renderResultPage()};
  }
  var sim=document.getElementById('tab-sim'),res=document.getElementById('tab-results'),sp=document.getElementById('simulation-pane'),rp=document.getElementById('results-pane');
  function tab(results){if(!sp||!rp)return;sp.hidden=results;rp.hidden=!results;sim.classList.toggle('active',!results);res.classList.toggle('active',results);if(results){drawResults(app.benchmark_csv);showResultView();}}
  if(rp&&!rp.dataset.init){rp.dataset.init='1';tab(false);}
  if(sim&&!sim.dataset.bound){sim.dataset.bound='1';sim.onclick=function(){tab(false)};res.onclick=function(){tab(true)};document.getElementById('help-button').onclick=function(){alert('Como usar\n\nArraste a mesa para mirar. Pegue o taco e puxe para trás: a barra mostra a força; solte para tacar. ✕ é o método escolhido, ◇ é a referência por força bruta e ╌ indica a saída da bola alvo. Setas ←/→ ajustam 0,5°.');};var input=document.getElementById('csv-file'),load=document.getElementById('load-csv');load.onclick=function(){input.click()};input.onchange=function(e){var f=e.target.files[0];if(f){var rd=new FileReader();rd.onload=function(){drawResults(rd.result)};rd.readAsText(f)}};document.getElementById('download-plots').onclick=function(){['chart-time','chart-pareto','chart-error','chart-convergence'].forEach(function(id){var e=document.getElementById(id);if(e&&window.Plotly)Plotly.downloadImage(e,{format:'png',filename:id});});};}
  Array.prototype.forEach.call(document.querySelectorAll('button'),function(b){if((b.textContent||'').indexOf('Exportar CSV')>=0&&!b.dataset.exportBound){b.dataset.exportBound='1';b.onclick=function(){var a=document.createElement('a');a.href=URL.createObjectURL(new Blob([app.benchmark_csv||''],{type:'text/csv'}));a.download='benchmark_results.csv';a.click();URL.revokeObjectURL(a.href);};}});
  if(rp&&!rp.hidden)drawResults(app.benchmark_csv);
  Array.prototype.forEach.call(document.querySelectorAll('button'),function(b){if((b.textContent||'').match(/^(Pausar|Continuar)$/)){var moving=!!(app.cue_pose&&app.cue_pose.moving);b.disabled=!moving&&!app.running;b.textContent=app.running?'Pausar':(moving?'Continuar':'Pausar');}});
}
var fpsFrames=0,fpsStamp=performance.now(),lastAngle=Number(app.aim_deg)||0;
function liveFrame(now){
  fpsFrames++;
  var windowMs=now-fpsStamp;
  if(windowMs>=500){
    var fps=document.getElementById('screen-fps');
    if(fps)fps.textContent=(fpsFrames*1000/windowMs).toFixed(0);
    fpsFrames=0;
    fpsStamp=now;
  }
  var angle=Number(app.aim_deg)||0,om=document.getElementById('omega-live');
  if(om)om.textContent=(((angle-lastAngle+540)%360-180)/Math.max((now-(liveFrame.prev||now))/1000,0.05)).toFixed(1);
  liveFrame.prev=now;
  lastAngle=angle;
  requestAnimationFrame(liveFrame);
}
window.addEventListener('resize',showResultView);
requestAnimationFrame(liveFrame);
setInterval(dashboardBind,300); dashboardBind();
"""
end
