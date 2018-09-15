module StructuralInheritance

#Stores prototype field definitions
const fieldBacking = Dict{Type,Vector{Any}}()

#prototype -> self
#concrete -> prototype
const shadowMap = Dict{Type,Type}()


"""
Creates an abstract type with the given name
"""
function abstracttype(name)
  basicForm = :(abstract type Replace end)
  dump(basicForm)
  basicForm.args[1] = name
  basicForm
end


"""
returns an array with only the field definitions
"""
function filtertofields(_quote)
  filter(x->typeof(x)==Symbol || (typeof(x) == Expr && x.head == :(::)),_quote.args)
end

"""
gets the name of a struct definition
"""
function extractname(leaf)
  leaf.args[2]
end

"""
extracts the fields from a struct definition
"""
function extractfields(leaf)
  filtertofields(leaf.args[3])
end

#TODO: fix handling for parametrics
function newnames(structDefinition)
  newStructName = deepcopy(extractname(structDefinition))
  prototypeName = deepcopy(newStructName)
  lightWeightPrototypeName = prototypeName

  if typeof(prototypeName) <: Symbol
      prototypeName = Symbol("Proto",prototypeName)
      lightWeightPrototypeName = prototypeName
  else
      temp = prototypeName
      while (temp.head == :(<:) || temp.head == :.) && typeof(temp.args[2]) <: Expr
          temp = temp.args[2]
      end
      if temp.head == :curly
        newStructName = temp.args[1]
        temp.args[1] = Symbol("Proto",temp.args[1])
        lightWeightPrototypeName = temp.args[1]
      else
        newStructName = temp.args[2]
        temp.args[2] = Symbol("Proto",temp.args[2])
        lightWeightPrototypeName = temp.args[2]
      end
  end
  newStructLightName = newStructName
  while typeof(newStructLightName) <: Expr
      newStructLightName.args[1]
  end
  newStructName = :($newStructName <: $lightWeightPrototypeName)
  (newStructName,prototypeName,newStructLightName,lightWeightPrototypeName)
end


function fieldsymbols(fields)
    function symbol(x)
        if typeof(x) <: Symbol
            x
        else
            x.args[2]::Symbol
        end
    end
    symbol.(fields)
end

"""
throws an error is the fields contain overlapping symbols
"""
function assertcollisionfree(x,y)
    assert(isempty(intersect(Set(fieldsymbols(x)),Set(fieldsymbols(y)))))
end

"""
returns a copy with replacement fields
"""
function replacefields(struct_,fields)
    out = deepcopy(struct_)
    out.args[3] = fields
    out
end

"""
annotates module information to unanotated typed fields
"""
function sanitize(module_,fields)
    fields #TODO
end


"""
returns a renamed struct
"""
function rename(struct_,name)
    newStruct = deepcopy(struct_)
    newStruct.args[2] = name
    newStruct
end

macro proto(struct_)
  dump(struct_)
  newName,name,newStructLightName,lightname = newnames(struct_)
  fields = extractfields(struct_)
  D1_struct = gensym()
  D1_module = gensym()
  D1_fields = gensym()
  prototypeDefinition = abstracttype(name) #Can't be evaluated until all checks are passed and we are in the calling module
  structDefinition = rename(struct_,newName)
  if typeof(name) <: Symbol || name.head == :curly #original definition does not inherit
    esc(quote
      $prototypeDefinition
      $D1_module = parentmodule($lightname)
      $D1_fields = StructuralInheritance.sanitize($D1_module,$(Meta.quot(fields)))
      dump($(Meta.quot(structDefinition)))
      $structDefinition
      StructuralInheritance.fieldBacking[$lightname] = $D1_fields
      StructuralInheritance.shadowMap[$newStructLightName] = $lightname
      StructuralInheritance.shadowMap[$lightname] = $lightname
  end)

  else #inheritence case
    D1_oldFields = gensym()
    D1_struct = gensym()
    esc(quote
      $D1_oldFields = StructuralInheritance.fieldBacking[StructuralInheritance.shadowMap[$name.args[2]]]
      $D1_fields = $(Meta.quot(fields))
      StructuralInheritance.assertcollisionfree($D1_fields,$D1_oldFields)
      $prototypeDefinition
      $D1_module = parentmodule($lightname)
      $D1_fields = StructuralInheritance.sanitize($D1_module,$D1_fields)
      $D1_fields = vcat($D1_fields,$D1_oldFields)

      $D1_struct = rename($(Meta.quot(structDefinition)),$(Meta.quot(newName)))
      $D1_struct = replacefields($D1_struct,$D1_fields)

      eval($D1_struct)

      StructuralInheritance.fieldBacking[$lightname] = $D1_fields
      StructuralInheritance.shadowMap[$newStructLightName] = $lightname
      StructuralInheritance.shadowMap[$lightname] = $lightname

    end)
  end

end

"""
Calls the provided constructor of the supertype the strucure is inherited from.
and sets local fields based on that.
"""
macro super(constructor,self::Symbol = gensym())
  val = gensym()
  fields = gensym()
  field = gensym()
  esc(quote
    $val = constructor
    $fields = fieldnames(typeof($val))
    $self = new()
    for $field = $fields
        setfield!($self,$field,getfield($val,$field))
    end
  end)
end

end
