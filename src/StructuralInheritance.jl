module StructuralInheritance

export @protostruct

#Stores prototype field definitions
const fieldBacking = Dict{Union{Type,Missing},Vector{Any}}()

#prototype -> self
#concrete -> prototype
const shadowMap = Dict{Type,Type}()

#store parametric type information
const parameterMap = Dict{Type,Vector{Any}}()


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
function filtertofields(_quote)
    filter(x->typeof(x)==Symbol || (typeof(x) == Expr && x.head == :(::)),_quote.args)
end

isfunctiondefinition(x) = (x isa Expr) && (x.head == :(=) || x.head == :function)

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
extractfields(leaf) = filtertofields(leaf.args[3])



function newnames(structDefinition,module_,prefix)
    """
    handle inheritence conversions
    """
    function rectify(x)
        val = module_.eval(deparametrize_lightName(x))
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

        if isparametric(nameNode)
            protoName = deepcopy(nameNode)
            protoName.args[1].args[1] = Symbol(prefix,nameNode.args[1].args[1])
            protoName.args[2] = inheritFrom
            return (:( $(nameNode.args[1]) <: $(protoName.args[1])),
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
        return (:( $(nameNode) <: $(protoName)),
                protoName,
                nameNode,
                protoName)
    end

    throw("structure of strucure name not identified")
end

isparametric(x) = false
isparametric(x::Expr) = x.head == :curly || any(isparametric,x.args)

isfunction(x) = false
isfunction(x::Expr) = x.head == :call

ispath(x) = false
ispath(x::Expr) = x.head == :.

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

function tupleexpander(x,fields)
    x = deparametrize_lightName(x)
    Expr(:tuple,((y)->:($x.$y)).(getfieldnames(fields))...)
end


function fieldsymbols(fields)
    function symbol(x)
        if typeof(x) <: Symbol
            x
        else
            x.args[1]::Symbol
        end
    end
    symbol.(fields)
end

"""
throws an error is the fields contain overlapping symbols
"""
function assertcollisionfree(x,y)
    if !isempty(intersect(Set(fieldsymbols(x)),Set(fieldsymbols(y))))
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
function fulltypename(x,__module__,inhibit = [])
    if x in inhibit
        return x
    end
    if isparametric(x)  || isfunction(x)
        fullargs = [fulltypename(y,__module__,inhibit) for y in x.args]
        return Expr(x.head,fullargs...)
    end

    if typeof(x) <: Expr && (x.head in [:vect,:hcat,:row,:vcat])
        return Expr(x.head,[fulltypename(y,__module__,inhibit) for y in x.args]...)
    end

    if !(typeof(x) <: Expr) && !(typeof(x) <: Symbol)
        return x #must be a primitive
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
    newFields = deepcopy(oldFields)
    update(x::Symbol) = x
    function update(x)
        y = deepcopy(x)
        if y.args[2] in oldParams
            loc = findfirst(y->(y==x.args[2]),oldParams)
            newParam = parameters[2][loc]
            if newParam in parameters[1]
                y.args[2] = newParam
            else
                y.args[2] = fulltypename(y.args[2],__module__,parameters[1])
            end
        end
        y
    end
    update.(newFields)
end

"""
turns an object into a tuple of its fields
"""
function totuple(x) #low efficiency version structs not defined here
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
function deparametrize_lightName(name)
    if typeof(name) <: Expr && name.head == :curly
        name.args[1]
    else
        name
    end
end

"""
registers a new struct and abstract type pair
"""
function register(module_,newStructName,prototypeName,fields,parameters)
    nSName =  deparametrize_lightName(newStructName)
    pName = deparametrize_lightName(prototypeName)

    concrete = module_.eval(nSName)
    proto = module_.eval(pName)

    fieldBacking[proto] = fields
    shadowMap[concrete] = proto
    parameterMap[proto] = parameters
    shadowMap[proto] = proto
end

"""
@protostruct(struct_ [, prefix_])

creates a struct that can have structure inherited from it if also defined by
@protostruct, creates an abstract type with a name given by the struct
definitions name and a prefix. The concrete type inherits from the abstract
type and anything which inherits the concrrete types structure also inherits
from the abstract type.

"""
macro protostruct(struct_,prefix_ = "Proto")
  #dump(struct_)
    try
        prefix = string(__module__.eval(prefix_))
        if length(prefix) == 0
            throw("Prefix must have finite Length")
        end

        newName,name,newStructLightName,lightname = newnames(struct_,__module__,prefix)
        parameters = get2parameters(struct_.args[2])
        fields = extractfields(struct_)
        sanitizedFields = sanitize(__module__,fields,parameters[1])
        prototypeDefinition = abstracttype(name)
        structDefinition = rename(struct_,newName)
        SI = :StructuralInheritance
        if typeof(name) <: Symbol || name.head == :curly
            return esc(quote
                $prototypeDefinition
                $structDefinition
                function $SI.totuple(x::$(deparametrize_lightName(newStructLightName)))
                    $(tupleexpander(:x,sanitizedFields))
                end
                $SI.register($__module__,
                             $(Meta.quot(newStructLightName)),
                             $(Meta.quot(lightname)),
                             $(Meta.quot(sanitizedFields)),
                             $(Meta.quot(parameters[1])))
            end)

        else #inheritence case
            parentType = get(shadowMap,__module__.eval(deparametrize_lightName(name.args[2])),missing)
            oldFields = get(fieldBacking,parentType ,[])
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
                function $SI.totuple(x::$(deparametrize_lightName(newStructLightName)))
                    $(tupleexpander(:x,fields))
                end
                StructuralInheritance.register($__module__,
                                               $(Meta.quot(newStructLightName)),
                                               $(Meta.quot(lightname)),
                                               $(Meta.quot(fields)),
                                               $(Meta.quot(parameters[1])))
            end)
        end

    catch e
        return :(throw($e))
    end
end


end
