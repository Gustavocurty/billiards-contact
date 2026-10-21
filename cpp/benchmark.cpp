// Núcleo do contato com raio e benchmark com std::chrono.
// Contato: |c0 + s d − ci| = ri + r0, s = −b − sqrt(b² − c).
// EDO: ds/dθ = −s (w·d′) / (w·d), w = c0 + s d − ci.
//
// Compilação (a partir da raiz do projeto):
//   g++ -O3 -std=c++17 -o cpp/billiards_bench cpp/benchmark.cpp
//   cpp\billiards_bench.exe benchmark_results.csv benchmark_pareto.svg

#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr double kTangentEps = 1e-3;
constexpr double kResidualLimit = 2.0;
constexpr double kPi = 3.14159265358979323846;

struct Ball {
    double x, y, r;
};

struct Hit {
    bool valid = false;
    double s = 0;
    double px = 0;
    double py = 0;
    int index = -1;
};

double wrap_unit(double theta) {
    return std::atan2(std::sin(theta), std::cos(theta));
}

Hit ray_hit(double ox, double oy, double dx, double dy, double cx, double cy, double radius) {
    Hit hit;
    double len = std::hypot(dx, dy);
    if (len <= 1e-12 || radius < 0) return hit;
    dx /= len;
    dy /= len;
    double wx = ox - cx;
    double wy = oy - cy;
    double b = wx * dx + wy * dy;
    double c = wx * wx + wy * wy - radius * radius;
    double disc = b * b - c;
    if (disc < 0) return hit;
    double s = -b - std::sqrt(disc);
    if (s < -1e-9) return hit;
    if (s < 0) s = 0;
    hit.valid = true;
    hit.s = s;
    hit.px = ox + s * dx;
    hit.py = oy + s * dy;
    return hit;
}

Hit brute(const std::vector<Ball>& balls, double theta) {
    Hit best;
    best.s = 1e300;
    double dx = std::cos(theta);
    double dy = std::sin(theta);
    for (int i = 1; i < static_cast<int>(balls.size()); ++i) {
        Hit hit = ray_hit(balls[0].x, balls[0].y, dx, dy, balls[i].x, balls[i].y, balls[0].r + balls[i].r);
        if (hit.valid && hit.s < best.s) {
            best = hit;
            best.index = i;
        }
    }
    if (best.index < 0) best.valid = false;
    return best;
}

double s_dot(double theta, double s, const Ball& cue, const Ball& target) {
    double dx = std::cos(theta);
    double dy = std::sin(theta);
    double dpx = -std::sin(theta);
    double dpy = std::cos(theta);
    double wx = cue.x + s * dx - target.x;
    double wy = cue.y + s * dy - target.y;
    double denom = wx * dx + wy * dy;
    if (std::abs(denom) < kTangentEps) return nan("");
    return -s * (wx * dpx + wy * dpy) / denom;
}

double integrate(bool rk4, double theta, double s, double dtheta, const Ball& cue, const Ball& target) {
    if (!rk4) {
        double k1 = s_dot(theta, s, cue, target);
        if (!std::isfinite(k1)) return nan("");
        return s + dtheta * k1;
    }
    double k1 = s_dot(theta, s, cue, target);
    if (!std::isfinite(k1)) return nan("");
    double k2 = s_dot(theta + dtheta / 2, s + dtheta / 2 * k1, cue, target);
    if (!std::isfinite(k2)) return nan("");
    double k3 = s_dot(theta + dtheta / 2, s + dtheta / 2 * k2, cue, target);
    if (!std::isfinite(k3)) return nan("");
    double k4 = s_dot(theta + dtheta, s + dtheta * k3, cue, target);
    if (!std::isfinite(k4)) return nan("");
    return s + dtheta / 6 * (k1 + 2 * k2 + 2 * k3 + k4);
}

struct Sample {
    double time = 0;
    double error = 0;
    bool wrong = false;
    bool tracked = false;
    int recalcs = 0;
};

struct Run {
    int n = 0;
    double radius = 0;
    int k = 1;
    std::string algorithm;
    std::string method;
    int frames = 0;
    int repetitions = 0;
    double mean = 0, median = 0, p99 = 0, fps = 0;
    double mean_error = 0, max_error = 0, wrong_rate = 0;
    int recalcs = 0;
};

double percentile(std::vector<double> values, double fraction) {
    if (values.empty()) return 0;
    std::sort(values.begin(), values.end());
    size_t index = static_cast<size_t>(std::ceil(fraction * values.size()));
    if (index < 1) index = 1;
    if (index > values.size()) index = values.size();
    return values[index - 1];
}

std::vector<Ball> make_balls(int n, double width, std::mt19937_64& rng) {
    double radius = 18.0 * std::sqrt(10.0 / std::max(n, 1));
    std::uniform_real_distribution<double> unit(0.0, 1.0);
    std::vector<Ball> balls(n);
    balls[0] = {width * 0.22, width * 0.5, radius};
    int cols = std::max(1, static_cast<int>(std::ceil(std::sqrt(std::max(n - 1, 1)))));
    for (int i = 1; i < n; ++i) {
        int col = (i - 1) % cols;
        int row = (i - 1) / cols;
        double x = width * 0.35 + col * (width * 0.6 / cols);
        double y = radius + row * (width * 0.9 / std::max(cols, 1));
        x = std::min(width - radius, std::max(radius, x + (unit(rng) - 0.5) * radius));
        y = std::min(width - radius, std::max(radius, std::fmod(y, width - 2 * radius) + radius));
        balls[i] = {x, y, radius};
    }
    return balls;
}

Run measure(const std::vector<Ball>& balls, int k, const std::string& algorithm, bool rk4, int frames, int warmup, int repetitions, double dtheta) {
    std::vector<double> times;
    std::vector<double> errors;
    int wrong = 0;
    int comparisons = 0;
    int recalcs = 0;
    times.reserve(static_cast<size_t>(frames) * repetitions);
    for (int rep = 0; rep < repetitions; ++rep) {
        double theta = 0;
        Hit tracked = brute(balls, theta);
        int since = 0;
        recalcs += tracked.valid ? 1 : 0;
        auto step = [&](bool count) {
            theta = wrap_unit(theta + dtheta);
            since += 1;
            bool use_ode = algorithm == "tracking" && (since % std::max(k, 1) != 0) && tracked.valid;
            auto started = std::chrono::steady_clock::now();
            Hit shown = tracked;
            bool did_track = false;
            if (!use_ode) {
                shown = brute(balls, theta);
                tracked = shown;
                if (count) recalcs += 1;
            } else {
                double s = integrate(rk4, theta - dtheta, tracked.s, dtheta, balls[0], balls[tracked.index]);
                double dx = std::cos(theta);
                double dy = std::sin(theta);
                double wx = balls[0].x + s * dx - balls[tracked.index].x;
                double wy = balls[0].y + s * dy - balls[tracked.index].y;
                double residual = std::abs(std::hypot(wx, wy) - (balls[0].r + balls[tracked.index].r));
                double end_dot = s_dot(theta, s, balls[0], balls[tracked.index]);
                if (!std::isfinite(s) || s < -1e-9 || residual > kResidualLimit || !std::isfinite(end_dot)) {
                    shown = brute(balls, theta);
                    tracked = shown;
                    if (count) recalcs += 1;
                } else {
                    shown = tracked;
                    shown.s = s;
                    shown.px = balls[0].x + s * dx;
                    shown.py = balls[0].y + s * dy;
                    shown.valid = true;
                    tracked = shown;
                    did_track = true;
                }
            }
            auto elapsed = std::chrono::steady_clock::now() - started;
            if (!count) return;
            times.push_back(std::chrono::duration<double>(elapsed).count());
            Hit truth = brute(balls, theta);
            double err = 0;
            if (shown.valid && truth.valid) {
                err = std::hypot(shown.px - truth.px, shown.py - truth.py);
                if (shown.index != truth.index) wrong += 1;
            } else if (shown.valid != truth.valid) {
                err = shown.valid ? shown.s : truth.s;
                wrong += 1;
            }
            comparisons += 1;
            errors.push_back(err);
            (void)did_track;
        };
        for (int i = 0; i < warmup; ++i) step(false);
        for (int i = 0; i < frames; ++i) step(true);
    }
    Run run;
    run.n = static_cast<int>(balls.size());
    run.radius = balls.empty() ? 0 : balls[0].r;
    run.k = k;
    run.algorithm = algorithm;
    run.method = algorithm == "tracking" ? (rk4 ? "rk4" : "euler") : "-";
    run.frames = frames;
    run.repetitions = repetitions;
    double sum_t = 0, sum_e = 0, max_e = 0;
    for (double t : times) sum_t += t;
    for (double e : errors) {
        sum_e += e;
        max_e = std::max(max_e, e);
    }
    run.mean = times.empty() ? 0 : sum_t / times.size();
    run.median = percentile(times, 0.50);
    run.p99 = percentile(times, 0.99);
    run.fps = run.mean > 0 ? 1.0 / run.mean : 0;
    run.mean_error = errors.empty() ? 0 : sum_e / errors.size();
    run.max_error = max_e;
    run.wrong_rate = comparisons == 0 ? 0 : 100.0 * wrong / comparisons;
    run.recalcs = recalcs;
    return run;
}

void write_csv(const std::string& path, const std::vector<Run>& rows) {
    std::ofstream out(path);
    out << "n_balls,radius,recalculation_interval,algorithm,numerical_method,frames,repetitions,"
           "mean_frame_time_s,median_frame_time_s,p99_frame_time_s,fps,"
           "mean_brute_force_time_s,mean_tracking_time_s,mean_error,max_error,wrong_ball_rate,recalculations\n";
    out.setf(std::ios::scientific);
    out.precision(8);
    for (const Run& row : rows) {
        double brute_t = row.algorithm == "brute_force" ? row.mean : 0;
        double track_t = row.algorithm == "tracking" ? row.mean : 0;
        out << row.n << "," << row.radius << "," << row.k << "," << row.algorithm << "," << row.method << ","
            << row.frames << "," << row.repetitions << "," << row.mean << "," << row.median << "," << row.p99 << ","
            << row.fps << "," << brute_t << "," << track_t << "," << row.mean_error << "," << row.max_error << ","
            << row.wrong_rate << "," << row.recalcs << "\n";
    }
}

void write_svg(const std::string& path, const std::vector<Run>& rows) {
    struct Point { double x, y; bool rk4; int n, k; };
    std::vector<Point> points;
    for (const Run& row : rows) {
        if (row.algorithm != "tracking") continue;
        points.push_back({std::max(row.mean, 1e-12), std::max(row.mean_error, 1e-12), row.method == "rk4", row.n, row.k});
    }
    std::ofstream out(path);
    out << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"760\" height=\"480\" viewBox=\"0 0 760 480\">\n";
    out << "<rect width=\"760\" height=\"480\" fill=\"#f7f4ee\"/>\n";
    out << "<text x=\"380\" y=\"32\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"18\">Erro medio x tempo por frame</text>\n";
    if (points.empty()) {
        out << "</svg>\n";
        return;
    }
    double minx = 1e300, maxx = -1e300, miny = 1e300, maxy = -1e300;
    for (const Point& p : points) {
        minx = std::min(minx, std::log10(p.x));
        maxx = std::max(maxx, std::log10(p.x));
        miny = std::min(miny, std::log10(p.y));
        maxy = std::max(maxy, std::log10(p.y));
    }
    if (maxx == minx) maxx = minx + 1;
    if (maxy == miny) maxy = miny + 1;
    const double left = 70, right = 720, top = 50, bottom = 430;
    auto px = [&](double v) { return left + (v - minx) / (maxx - minx) * (right - left); };
    auto py = [&](double v) { return bottom - (v - miny) / (maxy - miny) * (bottom - top); };
    out << "<line x1=\"" << left << "\" y1=\"" << bottom << "\" x2=\"" << right << "\" y2=\"" << bottom << "\" stroke=\"#333\"/>\n";
    out << "<line x1=\"" << left << "\" y1=\"" << top << "\" x2=\"" << left << "\" y2=\"" << bottom << "\" stroke=\"#333\"/>\n";
    out << "<text x=\"390\" y=\"460\" text-anchor=\"middle\" font-family=\"sans-serif\" font-size=\"13\">log10(tempo medio por frame, s)</text>\n";
    for (const Point& p : points) {
        const char* color = p.rk4 ? "#1e88e5" : "#e53935";
        out << "<circle cx=\"" << px(std::log10(p.x)) << "\" cy=\"" << py(std::log10(p.y))
            << "\" r=\"4\" fill=\"" << color << "\"/>\n";
    }
    out << "<circle cx=\"90\" cy=\"48\" r=\"4\" fill=\"#e53935\"/><text x=\"100\" y=\"52\" font-family=\"sans-serif\" font-size=\"12\">Euler</text>\n";
    out << "<circle cx=\"170\" cy=\"48\" r=\"4\" fill=\"#1e88e5\"/><text x=\"180\" y=\"52\" font-family=\"sans-serif\" font-size=\"12\">RK4</text>\n";
    out << "</svg>\n";
}

}  // namespace

int main(int argc, char** argv) {
    std::string csv = argc > 1 ? argv[1] : "benchmark_results.csv";
    std::string svg = argc > 2 ? argv[2] : "benchmark_pareto.svg";
    const int counts[] = {10, 100, 1000, 10000, 100000};
    const int intervals[] = {1, 5, 10, 30, 60, 120};
    const int frames = 40;
    const int warmup = 8;
    const int repetitions = 5;
    std::mt19937_64 rng(1);
    std::vector<Run> rows;
    for (int n : counts) {
        std::vector<Ball> balls = make_balls(n, 1000.0, rng);
        for (int k : intervals) {
            rows.push_back(measure(balls, k, "brute_force", false, frames, warmup, repetitions, 0.01));
            rows.push_back(measure(balls, k, "tracking", false, frames, warmup, repetitions, 0.01));
            rows.push_back(measure(balls, k, "tracking", true, frames, warmup, repetitions, 0.01));
            const Run& last = rows.back();
            std::cout << "N=" << last.n << " K=" << last.k
                      << " erro_medio_rk4=" << last.mean_error
                      << " bola_errada=" << last.wrong_rate << "%\n";
        }
    }
    write_csv(csv, rows);
    write_svg(svg, rows);
    std::cout << "CSV salvo em " << csv << "\n";
    return 0;
}
