const ALG_BRUTE = "Força bruta"
const ALG_TRACK = "Rastreamento"

function table_layout()
    return PlotlyBase.Layout(
        title = "Mesa — vista superior",
        xaxis = PlotlyBase.attr(title = "x", range = [-40, 1040], zeroline = false, constrain = "domain", fixedrange = true),
        yaxis = PlotlyBase.attr(title = "y", range = [-40, 1040], zeroline = false, scaleanchor = "x", scaleratio = 1, fixedrange = true),
        plot_bgcolor = "#0f6b3c",
        paper_bgcolor = "#f7f4ee",
        height = 700,
        margin = PlotlyBase.attr(l = 48, r = 16, t = 48, b = 72),
        legend = PlotlyBase.attr(orientation = "h", y = -0.2),
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
    )
end

const BALL_COLORS = ["#e53935", "#1e88e5", "#fdd835", "#8e24aa", "#fb8c00", "#00897b", "#6d4c41", "#7cb342"]

function aim_vector(state::SimulationState)::Vec2
    return Vec2(cos(state.aim_angle), sin(state.aim_angle))
end

const POWER_MIN = 80.0
const POWER_MAX = 800.0
const CUE_HIT = 42.0
const PULL_SHOT = 15.0
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

function table_traces(state::SimulationState; power::Float64 = 420.0, gap::Float64 = 0.0)
    balls = state.balls
    cue_i = state.cue_index
    target_i = state.contact === nothing ? 0 : state.contact.ball_index
    others_x = Float64[]
    others_y = Float64[]
    others_color = String[]
    for i in eachindex(balls)
        (i == cue_i || i == target_i) && continue
        push!(others_x, balls[i].position[1])
        push!(others_y, balls[i].position[2])
        push!(others_color, BALL_COLORS[mod1(i, length(BALL_COLORS))])
    end

    cue = balls[cue_i]
    x1 = cue.position[1]
    y1 = cue.position[2]
    direction = route_vector(state)
    aim = aim_vector(state)
    contact_point = state.contact === nothing ? nothing : state.contact.point
    if contact_point === nothing
        x2 = x1 + direction[1] * 460.0
        y2 = y1 + direction[2] * 460.0
    else
        ahead = (contact_point[1] - x1) * direction[1] + (contact_point[2] - y1) * direction[2]
        if ahead > cue.radius
            x2 = contact_point[1]
            y2 = contact_point[2]
        else
            x2 = x1 + direction[1] * 460.0
            y2 = y1 + direction[2] * 460.0
        end
    end

    show_cue = !balls_moving(state)
    head_d, tail_d = cue_distances(cue.radius, power, show_cue ? gap : 0.0)
    tail_x = x1 - aim[1] * tail_d
    tail_y = y1 - aim[2] * tail_d
    head_x = x1 - aim[1] * head_d
    head_y = y1 - aim[2] * head_d
    tip_d = max(head_d, tail_d - 14.0)
    tip_x = x1 - aim[1] * tip_d
    tip_y = y1 - aim[2] * tip_d

    traces = PlotlyBase.GenericTrace[]
    if show_cue
        if gap >= 0.0
            bar_x = x1 - aim[1] * (cue.radius + 2.0)
            bar_y = y1 - aim[2] * (cue.radius + 2.0)
            push!(traces, PlotlyBase.scatter(
                x = [bar_x, head_x], y = [bar_y, head_y], mode = "lines", name = "Força",
                hoverinfo = "skip",
                line = PlotlyBase.attr(color = force_color(power), width = 10),
            ))
        end
        push!(traces, PlotlyBase.scatter(
            x = [tail_x, tip_x], y = [tail_y, tip_y], mode = "lines", name = "Taco",
            hoverinfo = "skip",
            line = PlotlyBase.attr(color = "#5d4037", width = 7),
        ))
        push!(traces, PlotlyBase.scatter(
            x = [tip_x, head_x], y = [tip_y, head_y], mode = "lines", name = "Ponta",
            hoverinfo = "skip",
            line = PlotlyBase.attr(color = "#efebe9", width = 5),
        ))
    end
    push!(traces, PlotlyBase.scatter(
        x = [x1, x2], y = [y1, y2], mode = "lines", name = "Rota",
        line = PlotlyBase.attr(color = "#f4f7f5", width = 2, dash = "dash"),
    ))
    push!(traces, PlotlyBase.scatter(
        x = others_x, y = others_y, mode = "markers", name = "Bolas",
        marker = PlotlyBase.attr(size = 18, color = others_color, line = PlotlyBase.attr(color = "#1b1b1b", width = 1)),
    ))
    move_x = Float64[]
    move_y = Float64[]
    for i in eachindex(balls)
        i == cue_i && continue
        b = balls[i]
        speed = hypot(b.velocity[1], b.velocity[2])
        speed > 8.0 || continue
        scale = clamp(speed, 40.0, 360.0) * 0.45
        push!(move_x, b.position[1], b.position[1] + b.velocity[1] / speed * scale, NaN)
        push!(move_y, b.position[2], b.position[2] + b.velocity[2] / speed * scale, NaN)
    end
    if !isempty(move_x)
        push!(traces, PlotlyBase.scatter(
            x = move_x, y = move_y, mode = "lines", name = "Para onde vão",
            line = PlotlyBase.attr(color = "#ffcc80", width = 2, dash = "dot"),
        ))
    end
    if target_i != 0 && contact_point !== nothing
        target = balls[target_i]
        tx = target.position[1]
        ty = target.position[2]
        nx = tx - contact_point[1]
        ny = ty - contact_point[2]
        nlen = hypot(nx, ny)
        target_speed = hypot(target.velocity[1], target.velocity[2])
        if nlen > 1e-6 && target_speed <= 8.0
            push!(traces, PlotlyBase.scatter(
                x = [tx, tx + 160.0 * nx / nlen], y = [ty, ty + 160.0 * ny / nlen],
                mode = "lines", name = "Após o contato",
                line = PlotlyBase.attr(color = "#ffcc80", width = 2, dash = "dot"),
            ))
        end
        push!(traces, PlotlyBase.scatter(
            x = [tx], y = [ty], mode = "markers", name = "Alvo",
            marker = PlotlyBase.attr(size = 20, color = "#ff5a5f", line = PlotlyBase.attr(color = "#1b1b1b", width = 1)),
        ))
        push!(traces, PlotlyBase.scatter(
            x = [contact_point[1]], y = [contact_point[2]], mode = "markers", name = "Contato",
            marker = PlotlyBase.attr(symbol = "x", size = 14, color = "#ffe66d", line = PlotlyBase.attr(color = "#1b1b1b", width = 2)),
        ))
    end
    push!(traces, PlotlyBase.scatter(
        x = [x1], y = [y1], mode = "markers", name = "Branca",
        marker = PlotlyBase.attr(size = 20, color = "#f7f7f2", line = PlotlyBase.attr(color = "#1b1b1b", width = 1)),
    ))
    return traces
end

function ui()
    [
        h4("Mesa de sinuca"),
        p("Segure o taco para mirar. Puxe para trás da bola: a barra mostra a força. Solte para a tacada. Com a mesa em movimento o taco some."),
        row([
            cell(class = "st-col col-12 col-md-8", [
                plot(:traces, layout = :layout, config = :chart_config),
            ]),
            cell(class = "st-col col-12 col-md-4 q-pa-md", [
                p("Ângulo do taco: {{aim_deg}}°"),
                p("Força: {{power}}"),
                select(:algorithm, options = [ALG_BRUTE, ALG_TRACK], label = "Algoritmo da rota"),
                p("Bolas: {{n_balls}}"),
                slider(2:1:16, :n_balls, lazy = true),
                p("Correção a cada K = {{recalc_interval}} frames, só no rastreamento."),
                slider(1:1:120, :recalc_interval),
                toggle("Calcular erro", :validate_error),
                row([
                    btn("Tacada", @click(:shot_click), color = "primary"),
                    btn("Continuar", @click(:start_click)),
                    btn("Pausar", @click(:pause_click), color = "warning"),
                ]),
                row([
                    btn("Reset", @click(:reset_click)),
                    btn("Aleatório", @click(:random_click)),
                    btn("Benchmark CSV", @click(:bench_click), color = "secondary"),
                ]),
                h6("Métricas"),
                p("Frame: {{frame}}"),
                p("Tempo: {{sim_time}} s"),
                p("Algoritmo: {{algorithm}}"),
                p("Última atualização: {{update_kind}}"),
                p("Contato: {{contact_text}}"),
                p("Bola alvo: {{target_text}}"),
                p("Tempo do algoritmo: {{exec_time}} ms"),
                p("Recálculos: {{recalculations}}"),
                p("Erro: {{error_text}}"),
                p("{{status}}"),
            ]),
        ]),
    ]
end

function cue_pointer_script()
    return raw"""
var self = this;
var cueDragging = false;
var cueAim = 0;
var cuePower = 420;
var cueGap = 0;
var cueStartDist = 0;
var cueFrame = false;
var cuePending = null;
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
function cueIndex(gd, name) {
  for (var i = 0; i < gd.data.length; i++) if (gd.data[i].name === name) return i;
  return -1;
}
function cueSegmentDistance(px, py, ax, ay, bx, by) {
  var vx = bx - ax, vy = by - ay;
  var len2 = vx * vx + vy * vy;
  if (len2 < 1e-8) return Math.hypot(px - ax, py - ay);
  var t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / len2));
  return Math.hypot(px - (ax + t * vx), py - (ay + t * vy));
}
function cueNear(pose, x, y) {
  var aimx = Math.cos(pose.aim), aimy = Math.sin(pose.aim);
  var d = cueDist(pose.radius, pose.power, 0);
  return cueSegmentDistance(
    x, y,
    pose.cx - aimx * d.tail, pose.cy - aimy * d.tail,
    pose.cx - aimx * d.head, pose.cy - aimy * d.head
  ) <= 42;
}
function cueLabels() {
  var nodes = document.querySelectorAll('p');
  var deg = Math.round(cueAim * 180 / Math.PI);
  var pow = Math.round(cuePower);
  for (var i = 0; i < nodes.length; i++) {
    var text = nodes[i].textContent || '';
    if (text.indexOf('Ângulo do taco:') === 0) nodes[i].textContent = 'Ângulo do taco: ' + deg + '°';
    if (text.indexOf('Força:') === 0) nodes[i].textContent = 'Força: ' + pow;
  }
}
function cueDraw(gd, pose) {
  var aimx = Math.cos(cueAim), aimy = Math.sin(cueAim);
  var d = cueDist(pose.radius, cuePower, cueGap);
  var tailx = pose.cx - aimx * d.tail, taily = pose.cy - aimy * d.tail;
  var headx = pose.cx - aimx * d.head, heady = pose.cy - aimy * d.head;
  var tipd = Math.max(d.head, d.tail - 14);
  var tipx = pose.cx - aimx * tipd, tipy = pose.cy - aimy * tipd;
  var barx = pose.cx - aimx * (pose.radius + 2), bary = pose.cy - aimy * (pose.radius + 2);
  var iForca = cueIndex(gd, 'Força');
  var iTaco = cueIndex(gd, 'Taco');
  var iPonta = cueIndex(gd, 'Ponta');
  var iRota = cueIndex(gd, 'Rota');
  if (iTaco < 0 || iPonta < 0 || iRota < 0) return;
  Plotly.restyle(gd, {
    x: [[tailx, tipx], [tipx, headx], [pose.cx, pose.cx + aimx * 460]],
    y: [[taily, tipy], [tipy, heady], [pose.cy, pose.cy + aimy * 460]]
  }, [iTaco, iPonta, iRota]);
  if (iForca >= 0) {
    Plotly.restyle(gd, {
      x: [[barx, headx]],
      y: [[bary, heady]],
      'line.color': cueColor(cuePower)
    }, [iForca]);
  }
  cueLabels();
}
function cueFollow(x, y, pose) {
  var dx = x - pose.cx, dy = y - pose.cy;
  var aimx = Math.cos(cueAim), aimy = Math.sin(cueAim);
  var behind = -(dx * aimx + dy * aimy);
  if (behind <= pose.radius) {
    cueGap = 0;
    return;
  }
  var dist = Math.hypot(dx, dy);
  if (dist <= 1) return;
  cueAim = Math.atan2(pose.cy - y, pose.cx - x);
  cueGap = Math.max(0, dist - (pose.radius + 44));
  if (cueGap > 0) cuePower = Math.min(800, Math.max(80, 80 + cueGap * 10));
}
function bindCuePointer() {
  var gd = document.querySelector('.js-plotly-plot');
  if (!gd || gd.dataset.cueBound || !gd._fullLayout || !gd._fullLayout.xaxis) return;
  gd.dataset.cueBound = '1';
  gd.style.cursor = 'crosshair';
  gd.style.touchAction = 'none';
  function coords(ev) {
    var L = gd._fullLayout;
    if (!L || !L.xaxis || !L.yaxis) return null;
    var rect = gd.getBoundingClientRect();
    return {
      x: L.xaxis.p2c(ev.clientX - rect.left - L.margin.l),
      y: L.yaxis.p2c(ev.clientY - rect.top - L.margin.t)
    };
  }
  gd.addEventListener('pointerdown', function (ev) {
    if (ev.button !== undefined && ev.button !== 0) return;
    var pose = self.cue_pose;
    if (!pose || pose.moving) return;
    var c = coords(ev);
    if (!c || !cueNear(pose, c.x, c.y)) return;
    cueDragging = true;
    cueAim = pose.aim;
    cuePower = pose.power;
    cueGap = 0;
    cueStartDist = Math.hypot(c.x - pose.cx, c.y - pose.cy);
    if (gd.setPointerCapture) gd.setPointerCapture(ev.pointerId);
    cueFollow(c.x, c.y, pose);
    cueDraw(gd, pose);
    ev.preventDefault();
  });
  gd.addEventListener('pointermove', function (ev) {
    if (!cueDragging) return;
    cuePending = ev;
    if (cueFrame) return;
    cueFrame = true;
    requestAnimationFrame(function () {
      cueFrame = false;
      if (!cueDragging || !cuePending) return;
      var pose = self.cue_pose;
      var c = coords(cuePending);
      cuePending = null;
      if (!pose || !c) return;
      cueFollow(c.x, c.y, pose);
      cueDraw(gd, pose);
    });
  });
  function endCue(ev) {
    if (!cueDragging) return;
    cueDragging = false;
    var pose = self.cue_pose;
    var c = coords(ev);
    if (pose && c) cueFollow(c.x, c.y, pose);
    var hide = [];
    var iForca = cueIndex(gd, 'Força');
    var iTaco = cueIndex(gd, 'Taco');
    var iPonta = cueIndex(gd, 'Ponta');
    if (iForca >= 0) hide.push(iForca);
    if (iTaco >= 0) hide.push(iTaco);
    if (iPonta >= 0) hide.push(iPonta);
    if (hide.length) Plotly.restyle(gd, {opacity: 0}, hide);
    var prev = self.shot_request || {};
    self.shot_request = {
      n: (prev.n || 0) + 1,
      angle: cueAim * 180 / Math.PI,
      power: cuePower,
      fire: true
    };
  }
  gd.addEventListener('pointerup', endCue);
  gd.addEventListener('pointercancel', endCue);
}
setInterval(bindCuePointer, 400);
"""
end
