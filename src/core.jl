"""
@protostruct(struct_ [, prefix_])

creates a struct that can have structure inherited from it and can inherit
structure.

additionally it creates an abstract type with a name given by the struct
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
    protostruct(__module__,struct_,prefix_,mutablilityOverride)
end

function protostruct(__module__,struct_,prefix_,mutablilityOverride)
    try
        prefix = (prefix_ isa Union{String,Symbol}) ? string(prefix_) : string(__module__.eval(prefix_))

        if length(prefix) == 0
            throw("Prefix must have finite Length")
        end

        struct_ = macroexpand(__module__,struct_,recursive=true)::Expr

        mutability = struct_.args[1]::Bool
        newName,name,newStructLightName,lightname = newnames(struct_.args[2]::FieldType,__module__,prefix)

        newParameters,oldParameters = get2parameters(struct_.args[2]::FieldType)

        fields = extractfields(struct_)
        prototypeDefinition = abstracttype(name)
        structDefinition = rename(struct_,newName)
        SI = StructuralInheritance
        modulePath = Symbol[fullname(__module__)...]
        if !inherits(name)
            sanitize!(modulePath,fields,newParameters)
        else #inheritence case
            parentType = get(shadowMap,__module__.eval(deparametrize(name.args[2])),nothing)
            oldFields = get(fieldBacking,parentType ,FieldType[])
            oldMutability = get(mutabilityMap,parentType,nothing)

            if oldMutability != nothing && oldMutability != mutability
                if eval(mutablilityOverride) != true
                    throw("$(oldMutability ? "im" : "")mutable object"*
                    " inheriting from $(oldMutability ? "" : "im")mutable")
                end
            end

            assertcollisionfree(fields,oldFields)
            sanitize!(modulePath,fields,newParameters)
            oldFields = updateParameters(oldFields,
                                        get(parameterMap,parentType,FieldType[]),
                                         (newParameters,oldParameters),
                                         parentType,
                                         modulePath)
            fields = vcat(oldFields,fields)
            constructors = extractconstructors(struct_)
            structDefinition = replacefields(structDefinition,
                                             vcat(fields,constructors))
        end
        return esc(quote
            $prototypeDefinition
            $structDefinition
            function $SI.totuple(x::$(deparametrize(newStructLightName)))
                $(tupleexpander(:x,fields))
            end
            $SI.register($(deparametrize(newStructLightName)),
                         $(deparametrize(lightname)),
                         $(Meta.quot(fields)),
                         $(Meta.quot(newParameters)),
                         $mutability)
        end)

    catch e
        return :(throw($e))
    end
end
