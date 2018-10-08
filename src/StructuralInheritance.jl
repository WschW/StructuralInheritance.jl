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
returns an array with only the field definitions
"""
function filtertofields(_quote)
    filter(x->typeof(x)==Symbol || (typeof(x) == Expr && x.head == :(::)),_quote.args)
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
        val = module_.eval(x)
        if !(typeof(val) <: Type)
            throw("must inherit from a type")
        end
        if isabstracttype(val)
            x
        elseif haskey(shadowMap,val)
            :($(shadowMap[val]))
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

function isparametric(x)
    if typeof(x) <: Expr
       x.head == :curly || any(isparametric,x.args)
    else
        false
    end
end

function getparameters(x)
    if typeof(x) <: Expr && x.head == :<:
        (getparameters_(x),getparameters_(x))
    else
        (getparameters_(x),)
    end
end

function getparameters_(x)
    if typeof(x) <: Expr && x.head == :curly
        x.args[2:end]
    elseif typeof(x) <: Expr
        for subexpr = x.args
            parameters = getparameters_(subexpr)
            if parameters != []
                return parameters
            end
        end
    end
    []
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
function fulltypename(x,__module__)
    modulePath = fullname(__module__)
    annotationPath = push!(Any[modulePath...],x)
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

    function addpathif(x,__module__)
        if typeof(x) <: Symbol  || x in inhibit
            x
        else
            x.args[2] = fulltypename(x.args[2],__module__)
            x
        end
    end

    (x->addpathif(x,__module__)).(fields)
end

"""
update parameters from old fields
"""
function updateParameters(oldFields,parameters,parentType,__module__)
    newFields = deepcopy(oldFields) #TODO:
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
function register(module_,newStructName,prototypeName,fields)
    nSName =  deparametrize_lightName(newStructName)
    pName = deparametrize_lightName(prototypeName)

    concrete = module_.eval(nSName)
    proto = module_.eval(pName)
    StructuralInheritance.fieldBacking[proto] = fields
    StructuralInheritance.shadowMap[concrete] = proto
    StructuralInheritance.shadowMap[proto] = proto
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
        parameters = getparameters(newName)
        fields = extractfields(struct_)
        sanitizedFields = sanitize(__module__,fields,parameters)
        prototypeDefinition = abstracttype(name)
        structDefinition = rename(struct_,newName)

        if typeof(name) <: Symbol || name.head == :curly
            return esc(quote
                $prototypeDefinition
                $structDefinition
                StructuralInheritance.register($__module__,
                                               $(Meta.quot(newStructLightName)),
                                               $(Meta.quot(lightname)),
                                               $(Meta.quot(sanitizedFields)))
            end)

        else #inheritence case
            parentType = get(shadowMap,__module__.eval(name.args[2]),missing)
            oldFields = get(fieldBacking,parentType ,[])
            assertcollisionfree(fields,oldFields)
            parameters = getparameters(newName);
            fields = sanitize(__module__,fields,parameters[1])
            oldFields = updateParameters(oldFields,parameters,parentType,__module__)
            fields = vcat(oldFields,fields)
            structDefinition = replacefields(structDefinition,fields)
            return esc(quote
                $prototypeDefinition
                $structDefinition
                StructuralInheritance.register($__module__,
                                               $(Meta.quot(newStructLightName)),
                                               $(Meta.quot(lightname)),
                                               $(Meta.quot(fields)))

            end)
        end

    catch e
        return :(throw($e))
    end
end


end
