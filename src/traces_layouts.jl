abstract type AbstractTrace end
abstract type AbstractLayout end

mutable struct GenericTrace{T <: AbstractDict{Symbol,Any}} <: AbstractTrace
    fields::T
end

function GenericTrace(kind::Union{AbstractString,Symbol},
                      fields=Dict{Symbol,Any}(); kwargs...)
    # use setindex! methods below to handle `_` substitution
    fields[:type] = kind
    gt = GenericTrace(fields)
    foreach(x -> setindex!(gt, x[2], x[1]), kwargs)
    if Symbol(kind) in [:contour, :contourcarpet, :heatmap, :heatmapgl]
        if !haskey(gt, :transpose)
            gt.transpose = true
        end
    end
    gt
end

function _layout_defaults()
    return Dict{Symbol,Any}(
        :margin => Dict{Symbol,Any}(:l => 50, :r => 50, :t => 60, :b => 50),
        :template => templates[templates.default],
    )
end

mutable struct Layout{T <: AbstractDict{Symbol,Any}} <: AbstractLayout
    fields::T
    subplots::Subplots

    function Layout{T}(fields::T; kwargs...) where T
        l = new{T}(merge(_layout_defaults(), fields), Subplots())
        foreach(x -> setindex!(l, x[2], x[1]), kwargs)
        l
    end
end

Layout(fields::T=Dict{Symbol,Any}(); kwargs...) where {T <: AbstractDict{Symbol,Any}} =
    Layout{T}(fields; kwargs...)

kind(gt::GenericTrace) = get(gt, :type, "scatter")
kind(l::Layout) = "layout"

# -------------------------------------------- #
# Specific types of trace or layout attributes #
# -------------------------------------------- #

function attr(fields::AbstractDict=Dict{Symbol,Any}(); kwargs...)
    # use setindex! methods below to handle `_` substitution
    s = PlotlyAttribute(fields)
    for (k, v) in kwargs
        s[k] = v
    end
    s
end
attr(x::PlotlyAttribute; kw...) = attr(;x..., kw...)

mutable struct PlotlyFrame{T <: AbstractDict{Symbol,Any}} <: AbstractPlotlyAttribute
    fields::T
    function PlotlyFrame{T}(fields::T) where T
        !(Symbol("name") in keys(fields)) && @warn("Frame should have a :name field for expected behavior")
        new{T}(fields)
    end
end

function frame(fields=Dict{Symbol,Any}(); kwargs...)
    for (k, v) in kwargs
        fields[k] = v
    end
    PlotlyFrame{Dict{Symbol,Any}}(fields)
end

abstract type AbstractLayoutAttribute <: AbstractPlotlyAttribute end
abstract type AbstractShape <: AbstractLayoutAttribute end

kind(::AbstractPlotlyAttribute) = "PlotlyAttribute"

# TODO: maybe loosen some day
const _Scalar = Union{DateTime,Date,Number,AbstractString,Symbol}

# ------ #
# Shapes #
# ------ #

mutable struct Shape <: AbstractLayoutAttribute
    fields::AbstractDict{Symbol}
end

function Shape(kind::AbstractString, fields=Dict{Symbol,Any}(); kwargs...)
    # use setindex! methods below to handle `_` substitution
    fields[:type] = kind
    s = Shape(fields)
    foreach(x -> setindex!(s, x[2], x[1]), kwargs)
    s
end

# helper method needed below
_rep(x, n) = take(cycle(x), n)

# line, circle, and rect share same x0, x1, y0, y1 args. Define methods for
# them here
for t in [:line, :circle, :rect]
    str_t = string(t)
    @eval $t(d::AbstractDict=Dict{Symbol,Any}(), ;kwargs...) =
        Shape($str_t, d; kwargs...)
    eval(Expr(:export, t))

    @eval function $(t)(x0::_Scalar, x1::_Scalar, y0::_Scalar, y1::_Scalar,
                        fields::AbstractDict=Dict{Symbol,Any}(); kwargs...)
        $(t)(fields; x0=x0, x1=x1, y0=y0, y1=y1, kwargs...)
    end

    @eval function $(t)(x0::Union{AbstractVector,_Scalar},
                        x1::Union{AbstractVector,_Scalar},
                        y0::Union{AbstractVector,_Scalar},
                        y1::Union{AbstractVector,_Scalar},
                        fields::AbstractDict=Dict{Symbol,Any}(); kwargs...)
        n = reduce(max, map(length, (x0, x1, y0, y1)))
        f(_x0, _x1, _y0, _y1) = $(t)(_x0, _x1, _y0, _y1, copy(fields); kwargs...)
        map(f, _rep(x0, n), _rep(x1, n), _rep(y0, n), _rep(y1, n))
    end
end

@doc "Draw a line through the points (x0, y0) and (x1, y2)" line

@doc """
Draw a circle from ((`x0`+`x1`)/2, (`y0`+`y1`)/2)) with radius
 (|(`x0`+`x1`)/2 - `x0`|, |(`y0`+`y1`)/2 -`y0`)|) """ circle

@doc """
Draw a rectangle linking (`x0`,`y0`), (`x1`,`y0`),
(`x1`,`y1`), (`x0`,`y1`), (`x0`,`y0`)""" rect


"Draw an arbitrary svg path"
path(p::AbstractString; kwargs...) = Shape("path"; path=p, kwargs...)

export path

# derived shapes

vline(x, ymin, ymax, fields::AbstractDict=Dict{Symbol,Any}(); kwargs...) =
    line(x, x, ymin, ymax, fields; kwargs...)

"""
`vline(x, fields::AbstractDict=Dict{Symbol,Any}(); kwargs...)`

Draw vertical lines at each point in `x` that span the height of the plot
"""
vline(x, fields::AbstractDict=Dict{Symbol,Any}(); kwargs...) =
    vline(x, 0, 1, fields; xref="x", yref="paper", kwargs...)

hline(y, xmin, xmax, fields::AbstractDict=Dict{Symbol,Any}(); kwargs...) =
    line(xmin, xmax, y, y, fields; kwargs...)

"""
`hline(y, fields::AbstractDict=Dict{Symbol,Any}(); kwargs...)`

Draw horizontal lines at each point in `y` that span the width of the plot
"""
hline(y, fields::AbstractDict=Dict{Symbol,Any}(); kwargs...) =
    hline(y, 0, 1, fields; xref="paper", yref="y", kwargs...)

# ---------------------------------------- #
# Implementation of getindex and setindex! #
# ---------------------------------------- #

const HasFields = Union{GenericTrace,Layout,Shape,PlotlyAttribute,PlotlyFrame}
const _LikeAssociative = Union{PlotlyAttribute,AbstractDict}

_symbol_dict(hf::HasFields) = _symbol_dict(hf.fields)

#= NOTE: Generate this list with the following code
using JSON, PlotlyJS, PlotlyBase
d = JSON.parsefile(Pkg.dir("PlotlyJS", "deps", "plotschema.json"))
d = PlotlyBase._symbol_dict(d)

nms = Set{Symbol}()
function add_to_names!(d::AbstractDict)
    map(add_to_names!, collect(keys(d)))
    map(add_to_names!, collect(values(d)))
    nothing
end
add_to_names!(s::Symbol) = push!(nms, s)
add_to_names!(x) = nothing

add_to_names!(d[:schema][:layout][:layoutAttributes])
for (_, v) in d[:schema][:traces]
    add_to_names!(v)
end

_UNDERSCORE_ATTRS = collect(
    filter(
        x-> contains(string(x), "_") && !startswith(string(x), "_"),
        nms
    )
) =#
const _UNDERSCORE_ATTRS = [:error_x, :copy_ystyle, :error_z, :plot_bgcolor,
                           :paper_bgcolor, :copy_zstyle, :error_y, :hr_name]

_isempty(x) = isempty(x)
_isempty(::Union{Nothing,Missing}) = true
_isempty(x::Bool) = x
_isempty(x::Union{Symbol,String}) = false

function Base.merge(hf::HasFields, d::Dict)
    out = deepcopy(hf)
    for (k, v) in d
        out[k] = d
    end
    out
end

function Base.merge!(hf1::HasFields, hf2::HasFields)
    for (k, v) in hf2.fields
        hf1[k] = v
    end
    hf1
end

Base.merge(d::Dict{Symbol}, hf2::HasFields) = merge(d, hf2.fields)
Base.merge!(d::Dict{Symbol}, hf2::HasFields) = merge!(d, hf2.fields)
Base.pairs(hf::HasFields) = pairs(hf.fields)
Base.keys(hf::HasFields) = keys(hf.fields)
Base.values(hf::HasFields) = values(hf.fields)

function setifempty!(hf::HasFields, key::Symbol, value)
    if _isempty(hf[key])
        hf[key] = value
    end
end

Base.haskey(hf::HasFields, k::Symbol) = haskey(hf.fields, k)

Base.merge(hf1::T, hf2::T) where {T <: HasFields} =
    merge!(deepcopy(hf1), hf2)

Base.isempty(hf::HasFields) = isempty(hf.fields)

function Base.get(hf::HasFields, k::Symbol, default)
    out = getindex(hf, k)
    (out == Dict()) ? default : out
end

Base.iterate(hf::HasFields) = iterate(hf.fields)
Base.iterate(hf::HasFields, x) = iterate(hf.fields, x)

==(hf1::T, hf2::T) where {T <: HasFields} = hf1.fields == hf2.fields

# NOTE: there is another method in dataframes_api.jl
_obtain_setindex_val(container::Any, val::Any, key::_Maybe{Symbol}=missing) = val
_obtain_setindex_val(container::Dict, val::Any, key::_Maybe{Symbol}=missing) = haskey(container, val) ? container[val] : val
_obtain_setindex_val(container::Any, func::Function, key::_Maybe{Symbol}=missing) = func(container)
_obtain_setindex_val(container::Missing, func::Function, key::_Maybe{Symbol}=missing) = func

# no container
Base.setindex!(gt::HasFields, val, key::String...) = setindex!(gt, val, missing, key...)

# methods that allow you to do `obj["first.second.third"] = val`
function Base.setindex!(gt::HasFields, val, container, key::String)
    if in(Symbol(key), _UNDERSCORE_ATTRS)
        return gt.fields[Symbol(key)] = _obtain_setindex_val(container, val)
    else
        return setindex!(gt, val, container, map(Symbol, split(key, ['.', '_']))...)
    end
end

Base.setindex!(gt::HasFields, val, container, keys::String...) =
    setindex!(gt, val, container, map(Symbol, keys)...)

# Now for deep setindex. The deepest the json schema ever goes is 4 levels deep
# so we will simply write out the setindex calls for 4 levels by hand. If the
# schema gets deeper in the future we can @generate them with @nexpr

# no container
Base.setindex!(gt::HasFields, val, key::Symbol...) = setindex!(gt, val, missing, key...)

function Base.setindex!(gt::HasFields, val, container, key::Symbol)
    # check if single key has underscores, if so split as str and call above
    # unless it is one of the special attribute names with an underscore
    if occursin("_", string(key))
        # check for title
        if key in [:xaxis_title, :yaxis_title, :zaxis_title, :title] && (typeof(val) in [String, Symbol])
            key = Symbol(key, :_text)
        end
        if !in(key, _UNDERSCORE_ATTRS)
            return setindex!(gt, val, container, string(key))
        end
    end
    gt.fields[key] = _obtain_setindex_val(container, val, key)
end

function Base.setindex!(gt::HasFields, val, container, k1::Symbol, k2::Symbol)
    d1 = get(gt.fields, k1, Dict())
    si_val = _obtain_setindex_val(container, val)
    d1[k2] = si_val
    gt.fields[k1] = d1
    si_val
end

function Base.setindex!(gt::HasFields, val, container, k1::Symbol, k2::Symbol, k3::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    si_val = _obtain_setindex_val(container, val)
    d2[k3] = si_val
    d1[k2] = d2
    gt.fields[k1] = d1
    si_val
end

function Base.setindex!(gt::HasFields, val, container, k1::Symbol, k2::Symbol,
                        k3::Symbol, k4::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    si_val = _obtain_setindex_val(container, val)
    d3[k4] = si_val
    d2[k3] = d3
    d1[k2] = d2
    gt.fields[k1] = d1
    si_val
end

function Base.setindex!(gt::HasFields, val, container, k1::Symbol, k2::Symbol,
    k3::Symbol, k4::Symbol, k5::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    d4 = get(d3, k4, Dict())
    si_val = _obtain_setindex_val(container, val)
    d4[k5] = si_val
    d3[k4] = d4
    d2[k3] = d3
    d1[k2] = d2
    gt.fields[k1] = d1
    si_val
end

#= NOTE: I need to special case instances when `val` is Associatve like so that
         I can partially update something that already exists.

Example:

hf = Layout(font_size=10)
val = Layout(font_family="Helvetica") =#

Base.setindex!(gt::HasFields, val::_LikeAssociative, key::Symbol...) = setindex!(gt, val, missing, key...)

function Base.setindex!(gt::HasFields, val::_LikeAssociative, container, key::Symbol)
    if occursin("_", string(key))

        if !in(key, _UNDERSCORE_ATTRS)
            return setindex!(gt, val, string(key))
        end
    end

    if key === :geojson
        gt.fields[key] = val
        return
    end

    for (k, v) in val
        setindex!(gt, v, container, key, k)
    end
end

function Base.setindex!(gt::HasFields, val::_LikeAssociative, container, k1::Symbol,
                        k2::Symbol)
    for (k, v) in val
        setindex!(gt, v, container, k1, k2, k)
    end
end

function Base.setindex!(gt::HasFields, val::_LikeAssociative, container, k1::Symbol,
                        k2::Symbol, k3::Symbol)
    for (k, v) in val
        setindex!(gt, v, container, k1, k2, k3, k)
    end
end

function Base.setproperty!(hf::HF, p::Symbol, val) where HF <: HasFields
    if hasfield(HF, p)
        return setfield!(hf, p, val)
    end
    setindex!(hf, val, p)
end


# now on to the simpler getindex methods. They will try to get the desired
# key, but if it doesn't exist an empty dict is returned
function Base.getindex(gt::HasFields, key::String)
    if in(Symbol(key), _UNDERSCORE_ATTRS)
        gt.fields[Symbol(key)]
    else
        getindex(gt, map(Symbol, split(key, ['.', '_']))...)
    end
end

Base.getindex(gt::HasFields, keys::String...) =
    getindex(gt, map(Symbol, keys)...)

function Base.getindex(gt::HasFields, key::Symbol)
    if occursin("_", string(key))
        if !in(key, _UNDERSCORE_ATTRS)
            return getindex(gt, string(key))
        end
    end
    get(gt.fields, key, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol)
    d1 = get(gt.fields, k1, Dict())
    get(d1, k2, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol, k3::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    get(d2, k3, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol,
                       k3::Symbol, k4::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    get(d3, k4, Dict())
end

function Base.getindex(gt::HasFields, k1::Symbol, k2::Symbol,
    k3::Symbol, k4::Symbol, k5::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    d4 = get(d3, k4, Dict())
    get(d4, k5, Dict())
end

function Base.getproperty(gt::HF, p::Symbol) where HF <: HasFields
    if hasfield(HF, p)
        return getfield(gt, p)
    end
    getindex(gt, p)
end

# Now to the pop! methods
function Base.pop!(gt::HasFields, key::String)
    if in(Symbol(key), _UNDERSCORE_ATTRS)
        pop!(gt.fields, Symbol(key))
    else
        pop!(gt, map(Symbol, split(key, ['.', '_']))...)
    end
end

Base.pop!(gt::HasFields, keys::String...) =
    pop!(gt, map(Symbol, keys)...)

function Base.pop!(gt::HasFields, key::Symbol)
    if occursin("_", string(key))
        if !in(key, _UNDERSCORE_ATTRS)
            return pop!(gt, string(key))
        end
    end
    pop!(gt.fields, key, Dict())
end

function Base.pop!(gt::HasFields, k1::Symbol, k2::Symbol)
    d1 = get(gt.fields, k1, Dict())
    pop!(d1, k2, Dict())
end

function Base.pop!(gt::HasFields, k1::Symbol, k2::Symbol, k3::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    pop!(d2, k3, Dict())
end

function Base.pop!(gt::HasFields, k1::Symbol, k2::Symbol,
                       k3::Symbol, k4::Symbol)
    d1 = get(gt.fields, k1, Dict())
    d2 = get(d1, k2, Dict())
    d3 = get(d2, k3, Dict())
    pop!(d3, k4, Dict())
end

# Function used to have meaningful display of traces and layouts
function _describe(x::HasFields)
    fields = sort(map(String, collect(keys(x.fields))))
    n_fields = length(fields)
    if n_fields == 0
        return "$(kind(x)) with no fields"
    elseif n_fields == 1
        return "$(kind(x)) with field $(fields[1])"
    elseif n_fields == 2
        return "$(kind(x)) with fields $(fields[1]) and $(fields[2])"
    else
        return "$(kind(x)) with fields $(join(fields, ", ", ", and "))"
    end
end

Base.show(io::IO, ::MIME"text/plain", g::HasFields) =
    println(io, _describe(g))
