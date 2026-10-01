const Vec2 = SVector{2, Float64}

struct Ball
    position::Vec2
    velocity::Vec2
    radius::Float64
end

struct Contact
    point::Vec2
    ball_index::Int
    distance::Float64
end

"""
Estado da simulação.

`recalculations` conta execuções da força bruta (busca inicial e correções).
`tracking_error` guarda o último erro medido contra a força bruta; `NaN` significa
que a validação não foi executada neste frame.
`last_kind` vale `:brute_force` ou `:tracking`, conforme a atualização do frame.
"""
mutable struct SimulationState
    balls::Vector{Ball}
    cue_index::Int
    contact::Union{Contact, Nothing}
    frame::Int
    time::Float64
    algorithm::Symbol
    brute_force_time::Float64
    tracking_time::Float64
    last_algorithm_time::Float64
    last_kind::Symbol
    recalculations::Int
    tracking_error::Float64
    aim_angle::Float64
    live_shot::Bool
end

function SimulationState(balls::Vector{Ball}; cue_index::Int = 1, algorithm::Symbol = :tracking, aim_angle::Float64 = 0.0, live_shot::Bool = false)
    return SimulationState(
        balls,
        cue_index,
        nothing,
        0,
        0.0,
        algorithm,
        0.0,
        0.0,
        0.0,
        :none,
        0,
        NaN,
        aim_angle,
        live_shot,
    )
end

struct SimulationConfig
    width::Float64
    height::Float64
    dt::Float64
    recalculation_interval::Int
    numerical_method::Symbol
end

function SimulationConfig(;
    width::Real = 1000,
    height::Real = 1000,
    dt::Real = 1 / 60,
    recalculation_interval::Integer = 30,
    numerical_method::Symbol = :euler,
)
    return SimulationConfig(
        Float64(width),
        Float64(height),
        Float64(dt),
        Int(recalculation_interval),
        numerical_method,
    )
end
