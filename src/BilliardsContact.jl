"""
Núcleo numérico do ponto de contato entre a trajetória da bola de taco
e as demais bolas em uma mesa de bilhar 2D.
"""
module BilliardsContact

using Random
using StaticArrays

include("types.jl")
include("geometry.jl")
include("brute_force.jl")
include("tracking.jl")
include("simulation.jl")
include("metrics.jl")

export Vec2, Ball, Contact, SimulationState, SimulationConfig
export cross2, distance, ray_circle_hit, direction_from, s_derivative, circle_residual
export find_contact_bruteforce, find_shot_contact, locate_contact
export euler_theta, rk4_theta, integrate_s
export advance_balls!, advance_events!, initialize!, step!, aim_step!, strike!
export demo_balls, demo_state, random_balls, rack_balls, random_resting_balls, demo_scenario, benchmark_radius
export tracking_error, wrong_ball_rate, time_summary, run_benchmark

end
