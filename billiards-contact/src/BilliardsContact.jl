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
export cross2, distance, intersect_trajectories, ray_circle_hit
export find_contact_bruteforce, find_shot_contact, locate_contact
export contact_derivative, euler_step, euler, rk4, rk4_step
export advance_balls!, initialize!, step!, strike!, demo_balls, demo_state, random_balls, rack_balls, random_resting_balls
export tracking_error, run_benchmark

end
