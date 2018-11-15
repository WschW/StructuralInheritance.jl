module StructuralInheritance

export @protostruct

#Stores prototype field definitions
const fieldBacking = Dict{Union{Type},Vector{Any}}()

#prototype -> self
#concrete -> prototype
const shadowMap = Dict{Type,Type}()

#store parametric type information
const parameterMap = Dict{Type,Vector{Any}}()


const mutabilityMap = Dict{Type,Bool}()


"""
Creates an abstract type with the given name
"""
abstracttype(name) = :(abstract type $name end)

"""
attaches parameters to a name
"""
function addparams(name,params)
    if length(params) == 0
        name
    else
        :($name{$(params...)})
    end
end


"""
returns an array with only the field definitions
"""
function filtertofields(unfiltered)
    filter(x->typeof(x)==Symbol || (typeof(x) == Expr && x.head == :(::)),unfiltered)
end

"""
flattens the scope of the fields
"""
flattenfields(x::LineNumberNode) = []
flattenfields(x) = [x]
function flattenfields(x::Expr)
    if x.head == :block
        vcat(flattenfields.(x.args)...)
    else
        [x]
    end
end

isfunctiondefinition(x) = false
isfunctiondefinition(x::Expr) = (x.head == :(=) || x.head == :function)

"""
returns array with only the field constructors
"""
function extractconstructors(_quote)
    filter(isfunctiondefinition,_quote.args[3].args)
end

"""
gets the name of a struct definition
"""
extractname(leaf) = leaf.args[2]

"""
extracts the fields from a struct definition
"""
extractfields(leaf) = filtertofields(flattenfields(leaf.args[3]))



function newnames(structDefinition,module_,prefix)
    """
    handle inheritence conversions
    """
    function rectify(x)
        val = module_.eval(deparametrize(x))
        if !(typeof(val) <: Type)
            throw("must inherit from a type")
        end
        if isabstracttype(val)
            x
        elseif haskey(shadowMap,val)
            addparams(:($(shadowMap[val])),getparameters(x))
        else
            throw("inheritence from concrete types is limited to those defined by @protostruct, $val not found")
        end
    end

    nameNode = structDefinition.args[2]

    if typeof(nameNode) <: Symbol
        protoName = Symbol(prefix,nameNode)
        return (:($nameNode <: $protoName),protoName,nameNode,protoName)
    end

    if nameNode.head == :<:
        inheritFrom = rectify(deepcopy(nameNode.args[2]))
        structHead = deepcopy(nameNode.args[1])

        if isparametric(nameNode.args[1])
            protoName = deepcopy(nameNode)
            protoName.args[1].args[1] = Symbol(prefix,nameNode.args[1].args[1])
            protoName.args[2] = inheritFrom
            return (:( $(nameNode.args[1]) <: $(detypevar(protoName.args[1]))),
                    protoName,
                    nameNode.args[1],
                    protoName.args[1])

        elseif typeof(nameNode.args[1]) <: Symbol
            protoName = deepcopy(nameNode)
            protoName.args[1] = Symbol(prefix,nameNode.args[1])
            protoName.args[2] = inheritFrom
            return (:( $(nameNode.args[1]) <: $(protoName.args[1])),
                    protoName,
                    nameNode.args[1],
                    protoName.args[1])
        end
    end


    if isparametric(nameNode)
        protoName = deepcopy(nameNode)
        protoName.args[1] = Symbol(prefix,nameNode.args[1])
        return (:( $(nameNode) <: $(detypevar(protoName))),
                protoName,
                nameNode,
                protoName)
    end

    throw("structure of strucure name not identified")
end

"""
from Foo{A<:B}
returns Foo{A}
"""
detypevar(x) = x
function detypevar(x::Expr)
    if x.head == :<:
        detypevar(x.args[1])
    else
        Expr(x.head,detypevar.(x.args)...)
    end
end

isparametric(x) = false
isparametric(x::Expr) = x.head == :curly || any(isparametric,x.args)


ispath(x) = false
ispath(x::Expr) = x.head == :.

iscontainerlike(x) = false
iscontainerlike(x::Expr) = (x.head in [:vect,:hcat,:row,
                                       :vcat, :call,
                                       :tuple,:curly,:macrocall])

function getpath(x)
    oldpath = Symbol[]
    while ispath(x)
        push!(oldpath,x.args[2].value)
        x = x.args[1]
    end
    oldpath = push!(oldpath,x)
    oldpath[end:-1:2], oldpath[1]
end

function get2parameters(x)
    if typeof(x) <: Expr && x.head == :<:
        (getparameters(x.args[1]),getparameters(x.args[2]))
    else
        (getparameters(x),[])
    end
end

getparameters(x) = isparametric(x) ? x.args[2:end] : []

function getfieldnames(x)
    f(x::Symbol) = x
    f(x::Expr) = x.args[1]
    f.(x)
end

"""
creates AST for expanding a struct into a tuple with the fields given
"""
function tupleexpander(x,fields)
    x = deparametrize(x)
    Expr(:tuple,((y)->:($x.$y)).(getfieldnames(fields))...)
end

"""
throws an error is the fields contain overlapping symbols
"""
function assertcollisionfree(x,y)
    if !isempty(intersect(Set(getfieldnames(x)),Set(getfieldnames(y))))
        throw("Field defined in multiple locations")
    end
end

"""
returns a copy with replacement fields
"""
function replacefields(struct_,fields)
    out = deepcopy(struct_)
    out.args[3].args = fields
    out
end

"""
adds source module information to the type name
"""
fulltypename(x,__module__,inhibit = []) = x #is a literal

function fulltypename(x::Union{Expr,Symbol},__module__,inhibit = [])
    if x in inhibit
        return x
    end
    if iscontainerlike(x)
        fullargs = [fulltypename(y,__module__,inhibit) for y in x.args]
        return Expr(x.head,fullargs...)
    end

    oldpath,x = getpath(x)

    modulePath = append!(Any[fullname(__module__)...],oldpath)
    annotationPath = push!(modulePath,x)
    reverse!(annotationPath)
    annotationPath[1:(end-1)] .= QuoteNode.(annotationPath[1:(end-1)])
    while length(annotationPath) > 1
        first = pop!(annotationPath)
        second = pop!(annotationPath)
        push!(annotationPath,Expr(:.,first,second))
    end
    annotationPath[1]
end

"""
annotates module information to unanotated typed fields
"""
function sanitize(__module__,fields,inhibit)
    fields = deepcopy(fields)

    addpathif(x::Symbol) = x
    function addpathif(x)
        x.args[2] = fulltypename(x.args[2],__module__,inhibit)
        x
    end

    (x->addpathif(x)).(fields)
end

"""
update parameters from old fields
"""
function updateParameters(oldFields,oldParams,parameters,parentType,__module__)
    function update(x)
        if x in oldParams
            loc = findfirst(y->(y==x),oldParams)
            newParam = parameters[2][loc]
            if newParam in parameters[1]
                return newParam
            else
                return fulltypename(newParam,__module__,parameters[1])
            end
        end
        x
    end
    function update(x::Expr)
        Expr(x.head,[update(z) for z in x.args]...)
    end
    update.(oldFields)
end

"""
Turns an object into a tuple of its fields.
"""
function totuple(x) #low efficiency version
    tuple([getfield(x,y) for y in fieldnames(typeof(x))]...)
end

"""
returns a renamed struct
"""
function rename(struct_,name)
    newStruct = deepcopy(struct_)
    newStruct.args[2] = name
    newStruct
end

"""
strips parameterization off of a name that does
not include inheritence information
"""
deparametrize(name) = name
deparametrize(name::Expr) = name.head == :curly ? name.args[1] : name

"""
registers a new struct and abstract type pair
"""
function register(module_,newStructName,prototypeName,fields,parameters,mutability)
    nSName =  deparametrize(newStructName)
    pName = deparametrize(prototypeName)

    concrete = module_.eval(nSName)
    proto = module_.eval(pName)

    fieldBacking[proto] = fields
    shadowMap[concrete] = proto
    parameterMap[proto] = parameters
    mutabilityMap[proto] = mutability
    shadowMap[proto] = proto
end

"""
@protostruct(struct_ [, prefix_])

Creates a struct that can have structure inherited from it and can inherit
structure.

Additionally it creates an abstract type with a name given by the struct
definitions name and a prefix. The concrete type inherits from the abstract
type and anything which inherits the concrete types structure also inherits
behavior from the abstract type.

```Julia
julia> using StructuralInheritance

julia> @protostruct struct A{T}
           fieldFromA::T
       end
ProtoA

julia> @protostruct struct B{D} <: A{Complex{D}}
          fieldFromB::D
       end "SomeOtherPrefix"
SomeOtherPrefixB

julia> @protostruct struct C <: B{Int}
         fieldFromC
       end
ProtoC
```
"""
macro protostruct(struct_,prefix_ = "Proto",mutablilityOverride = false)
  #dump(struct_)
    try
        prefix = string(__module__.eval(prefix_))
        if length(prefix) == 0
            throw("Prefix must have finite Length")
        end

        struct_ = macroexpand(__module__,struct_,recursive=true)

        mutability = struct_.args[1]
        newName,name,newStructLightName,lightname = newnames(struct_,__module__,prefix)
        parameters = get2parameters(struct_.args[2])
        parameters = (x->detypevar.(x)).(parameters)
        fields = extractfields(struct_)
        sanitizedFields = sanitize(__module__,fields,parameters[1])
        prototypeDefinition = abstracttype(name)
        structDefinition = rename(struct_,newName)
        SI = :StructuralInheritance
        if typeof(name) <: Symbol || name.head == :curly
            return esc(quote
                $prototypeDefinition
                $structDefinition
                function $SI.totuple(x::$(deparametrize(newStructLightName)))
                    $(tupleexpander(:x,sanitizedFields))
                end
                $SI.register($__module__,
                             $(Meta.quot(newStructLightName)),
                             $(Meta.quot(lightname)),
                             $(Meta.quot(sanitizedFields)),
                             $(Meta.quot(parameters[1])),
                             $mutability)
            end)

        else #inheritence case
            parentType = get(shadowMap,__module__.eval(deparametrize(name.args[2])),nothing)
            oldFields = get(fieldBacking,parentType ,[])
            oldMutability = get(mutabilityMap,parentType,nothing)

            if oldMutability != nothing && oldMutability != mutability
                if eval(mutablilityOverride) != true
                    throw("$(oldMutability ? "im" : "")mutable object"*
                    " inheriting from $(oldMutability ? "" : "im")mutable"*
                    "if this is desired pass true as a third argument "*
                    "to `@protostruct`")
                end
            end

            assertcollisionfree(fields,oldFields)
            fields = sanitize(__module__,fields,parameters[1])
            oldFields = updateParameters(oldFields,
                                        get(parameterMap,parentType,[]),
                                         parameters,
                                         parentType,
                                         __module__)
            fields = vcat(oldFields,fields)
            constructors = extractconstructors(struct_)
            structDefinition = replacefields(structDefinition,
                                             vcat(fields,constructors))
            return esc(quote
                $prototypeDefinition
                $structDefinition
                function $SI.totuple(x::$(deparametrize(newStructLightName)))
                    $(tupleexpander(:x,fields))
                end
                StructuralInheritance.register($__module__,
                                               $(Meta.quot(newStructLightName)),
                                               $(Meta.quot(lightname)),
                                               $(Meta.quot(fields)),
                                               $(Meta.quot(parameters[1])),
                                               $mutability)
            end)
        end

    catch e
        return :(throw($e))
    end
end


end
