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

function table_traces(state::SimulationState)
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

    # O taco é desenhado no navegador, por cima da mesa, para o arrasto não
    # esperar o redesenho do Plotly. A rota continua aqui, até o contato.
    traces = PlotlyBase.GenericTrace[]
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
        p("Clique em qualquer ponto da mesa e arraste: o taco gira na hora. Segure o taco e puxe para trás para armar a força; solte para a tacada. Com a mesa em movimento o taco some."),
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
  if (!cueDragging) placeOverlay();
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
  if (cueSvg) cueSvg.style.cursor = 'crosshair';
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
  if (!cueSvg || !cueSvg.isConnected) {
    cueSvg = document.createElementNS(svgNS, 'svg');
    cueSvg.setAttribute('class', 'cue-overlay');
    cueSvg.style.cssText = 'position:absolute;z-index:30;overflow:visible;touch-action:none;cursor:crosshair;';
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
setInterval(bindCuePointer, 200);
bindCuePointer();
"""
end
