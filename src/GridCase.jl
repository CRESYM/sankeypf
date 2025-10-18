"""
A `GridCase` is an object which a DCPF can be computed on.
"""
abstract type GridCase end

"""
A `ElementaryCase` is the simpliest GridCase represented as a Graph
"""
struct ElementaryCase <: GridCase
    g::MetaGraph
end

Base.copy(ec::ElementaryCase) = ElementaryCase(copy(ec.g))

"""
A `RichCase` is a `GridCase` with additional information for drawing.
`bus_orig` represents a bus that will define the part of the grid that remains energized in case of grid split.
`trippings`: is a list of trippings for which the order is important.
"""
struct RichCase{T<:GridCase}
    gc::T
    bus_orig::String
    drawparams::Dict{Symbol,Any}
    trippings::Union{Nothing,Vector{ELabel}}
end

RichCase(gc::T, bus_orig::String, drawparams::Dict{Symbol,Any}=Dict{Symbol,Any}()) where T<:GridCase =
    RichCase(gc, bus_orig, drawparams, nothing)

