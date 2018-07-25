#pragma ExtendedLineups
#pragma noTypeChecks
dialect "none"
import "standardGrace" as sg

import "ast" as ast
import "xmodule" as xmodule
import "io" as io
import "ScopeModule" as sc
import "SharedTypes" as share

inherit sg.methods

type ObjectType = share.ObjectType
type MethodType = share.MethodType
type ObjectTypeFactory = share.ObjectTypeFactory
type MethodTypeFactory = share.MethodTypeFactory
type AstNode = share.AstNode
type Parameter = share.Parameter


def scope: share.Scope = sc.scope

// Scoping error declaration
def ScopingError: outer.ExceptionKind = TypeError.refine("ScopingError")

var methodtypes := [ ]
// visitor to convert a type expression to a string
def typeVisitor: ast.AstVisitor = object {
    inherit ast.baseVisitor
    var literalCount := 1
    method visitTypeLiteral(lit) {
//        io.error.write"\n 25 visiting Type Literal"
        for (lit.methods) do { meth →
            var mtstr := "{literalCount} "
            for (meth.signature) do { part →
                mtstr := mtstr ++ part.name
                if (part.params.size > 0) then {
                    mtstr := mtstr ++ "("
                    for (part.params.indices) do { pnr →
                        var p := part.params.at(pnr)
                        if (p.dtype != false) then {
                            mtstr := mtstr ++ p.toGrace(1)
                        } else {
                            // if parameter type not listed, give it type Unknown
                            if(p.wildcard) then {
                                mtstr := mtstr ++ "_"
                            } else {
                                mtstr := mtstr ++ p.value
                            }
                            mtstr := mtstr ++ ":" ++ ast.unknownType.value
                            if (false != p.generics) then {
                                mtstr := mtstr ++ "⟦"
                                for (1..(p.generics.size - 1)) do {ix →
                                    mtstr := mtstr ++ p.generics.at(ix).toGrace(1) ++ ", "
                                }
                                mtstr := mtstr ++ p.generics.last.toGrace(1) ++ "⟧"
                            }
                        }
                        if (pnr < part.params.size) then {
                            mtstr := mtstr ++ ", "
                        }
                    }
                    mtstr := mtstr ++ ")"
                }
            }
            if (meth.rtype != false) then {
                mtstr := mtstr ++ " → " ++ meth.rtype.toGrace(1)
            }
            methodtypes.push(mtstr)
        }
        io.error.write "methodtypes of {lit} is {methodtypes}"
        return false
    }
    method visitOp(op) {
        if ((op.value=="&") || (op.value=="|")) then {
            def leftkind = op.left.kind
            def rightkind = op.right.kind
            if ((leftkind=="identifier") || (leftkind=="member")) then {
                var typeIdent := op.left.toGrace(0)
                methodtypes.push("{op.value} {typeIdent}")
            } elseif { leftkind=="typeliteral" } then {
                literalCount := literalCount + 1
                methodtypes.push("{op.value} {literalCount}")
                visitTypeLiteral(op.left)
            } elseif { leftkind=="op" } then {
                visitOp(op.left)
            }
            if ((rightkind=="identifier") || (rightkind=="member")) then {
                var typeIdent := op.right.toGrace(0)
                methodtypes.push("{op.value} {typeIdent}")
            } elseif { rightkind=="typeliteral" } then {
                literalCount := literalCount + 1
                methodtypes.push("{op.value} {literalCount}")
                visitTypeLiteral(op.right)
            } elseif { rightkind=="op" } then {
                visitOp(op.right)
            }
        }
        return false
    }
}

// convert type expression to string for debugging
method dtypeToString(dtype) {
    if (false == dtype) then {
        "Unknown"
    } elseif {dtype.kind == "typeliteral"} then {
        methodtypes := []
        dtype.accept(typeVisitor)
        methodtypes.at(1)
    } else {
        dtype.value
    }
}


// -------------------------------------------------------------------
// Type declarations for type representations to use for type checking
// -------------------------------------------------------------------

//This type is used for checking subtyping
type TypePair = share.TypePair

class typePair(first':ObjectType, second':ObjectType) → TypePair is confidential{
    method first → ObjectType {first'}

    method second → ObjectType {second'}

    method == (other:Object) → Boolean {
        (first == other.first) && (second == other.second)
    }

    method asString {"<{first'} , {second'}>"}
}

//This type is used for checking subtyping
type Answer = {
    ans → Boolean
    trials → List⟦TypePair⟧
    asString → String
}

class answerConstructor(ans':Boolean, trials':List⟦TypePair⟧) → Answer {
    method ans → Boolean {ans'}

    method trials → List⟦TypePair⟧ {trials'}

    method asString → String{"Answer is {ans'}\n Trials is {trials}"}
}


// type of a parameter
type Param = {
    name → String
    typeAnnotation → ObjectType
}

type ParamFactory = {
    withName (name' : String) ofType (type' : ObjectType) → Param
    ofType (type' : ObjectType) → Param
}

// Create parameter with given name' and type'
// if no name then use wildcard "_"
def aParam: ParamFactory is readable = object {
    method withName(name': String) ofType(type' : ObjectType) → Param {
        object {
            def name : String is public = name'
            def typeAnnotation : ObjectType is public = type'

            def asString : String is public, override =
                "{name} : {typeAnnotation}"
        }
    }

    method ofType (type': ObjectType) → Param {
        withName("_") ofType(type')
    }
}

// MixPart is a "segment" of a method:
// Ex. for (param1) do (param2), for(param1) and do(param2) are separate "MixParts."
type MixPart = {
    name → String
    parameters → List⟦Param⟧
}

// create a mixpart with given name' and parameters'
class aMixPartWithName(name' : String)
        parameters(parameters' : List⟦Param⟧) → MixPart {
    def name : String is public = name'
    def parameters : List⟦Param⟧ is public = parameters'
}

// factory for creating method types from various inputs
def aMethodType: MethodTypeFactory is public = object {
    // create method type from list of mixparts and return type
    method signature (signature' : List⟦MixPart⟧)
            returnType (rType : ObjectType) → MethodType {
        object {
            def signature : List⟦MixPart⟧ is public = signature'
            def returnType : ObjectType is public = rType

            var name : String is readable := ""
            var nameString : String is readable := ""
            var show : String := ""

            def fst: MixPart = signature.first

            if (fst.parameters.isEmpty) then {
                name := fst.name
                nameString := fst.name
                show := name
            } else {
                for (signature) do { part →
                    name := "{name}{part.name}()"
                    nameString := "{nameString}{part.name}({part.parameters.size})"
                    show := "{show}{part.name}("
                    var once: Boolean := false
                    for (part.parameters) do { param →
                        if (once) then {
                            show := "{show}, "
                        }
                        show := "{show}{param}"
                        once := true
                    }
                    show := "{show})"
                }

                name := name.substringFrom (1) to (name.size - 2)
            }

            show := "{show} → {returnType}"

            method hash → Number is override {name.hash}

            method == (other: MethodType) → Boolean {
                nameString == other.nameString
            }

            // Mask unknown fields in corresponding methods
            // Assume that the methods share a signature.
            method restriction (other : MethodType) → MethodType {
                def restrictParts: List⟦MixPart⟧ = list[]
                if (other.signature.size != signature.size) then {
                    return self
                }
                for (signature) and (other.signature)
                                        do {part: MixPart, part': MixPart →
                    if (part.name == part'.name) then {
                        def restrictParams: List⟦Param⟧ = list[]
                        if (part.parameters.size != part'.parameters.size) then {
                              io.error.write ("Programmer error: part {part.name} has {part.parameters.size}" ++
                                    " while part {part'.name} has {part'.parameters.size}")}
                        for (part.parameters) and (part'.parameters)
                                                do { p: Param, p': Param →
                            def pt': ObjectType = p'.typeAnnotation

                            // Contravariant in parameter types.
                            if (pt'.isDynamic) then {
                                restrictParams.push (
                                    aParam.withName (p.name) ofType (anObjectType.dynamic))
                            } else {
                                restrictParams.push (p)
                            }
                        }
                        restrictParts.push (
                            aMixPartWithName (part.name) parameters (restrictParams))
                    } else {
                        restrictParts.push (part)
                    }
                }
                return aMethodType.signature (restrictParts) returnType (returnType)
            }

            // Determines if this method is a specialisation of the given one.
            method isSpecialisationOf (trials : List⟦TypePair⟧, other : MethodType) → Answer {

                if (self.isMe (other)) then {
                    return answerConstructor(true, trials)
                }

                if (name != other.name) then {
                    return answerConstructor(false, trials)
                }

                if (other.signature.size != signature.size) then {
                    return answerConstructor(false, trials)
                }

                for (signature) and (other.signature)
                                            do { part: MixPart, part': MixPart →
                    if (part.name != part'.name) then {
                        return answerConstructor(false, trials)
                    }

                    if (part.parameters.size != part'.parameters.size) then {
                        return answerConstructor(false, trials)
                    }

                    for (part.parameters) and (part'.parameters)
                                                    do { p: Param, p': Param →
                        def pt: ObjectType = p.typeAnnotation
                        def pt': ObjectType = p'.typeAnnotation

                        // Contravariant in parameter types.
                        def paramSubtyping : Answer = pt'.isSubtypeHelper(trials, pt)

                        if (paramSubtyping.ans.not) then {
                            return paramSubtyping
                        }
                    }
                }
                return returnType.isSubtypeHelper (trials, other.returnType)
            }

            def asString : String is public, override = show
        }
    }

    // Create method type with no parameters, but returning rType
    method member (name : String) ofType (rType : ObjectType) → MethodType {
        signature(list[aMixPartWithName (name) parameters (list[])]) returnType (rType)
    }

    // Parses a methodtype line from a gct file into a MethodType object.
    // Lines will always be formatted like this:
    //  1 methname(param : ParamType)part(param : ParamType) → ReturnType
    // The number at the beginning is ignored here, since it is handled
    // down in the Imports rule.
    method fromGctLine (line : String, importName : String) → MethodType {
        //TODO: Generics are currently skipped over and ignored entirely.
        // string specifying method being imported
        var mstr: String
        var fst: Number
        var lst: Number
        def parts: List⟦MixPart⟧ = list[]
        var ret: String

        //Declare an identifier node that will be used when saving the type
        //of method parameter and method return, so we only retrieve the actual
        //type defintion of the param or ret type when we need to type check.
        var ident : share.Identifier

        //Check if line starts with a number. ie: 2 methName -> ReturnType
        mstr := if (line.at(1).startsWithLetter) then {
            line
        } else {
            line.substringFrom (line.indexOf (" ") + 1) to (line.size)
        }

        //Retrieves the parts of the method
        fst := 1
        var par: Number := mstr.indexOf ("(") startingAt (fst)
        lst := par - 1

        //Collect the part definition if our method is not a member
        if (par > 0) then {
            //Iterates through each part
            while {par > 0} do {
                //Collect the signature part name
                var partName: String := mstr.substringFrom (fst) to (lst)
                // io.error.write "partName: {partName}"

                var partParams: List⟦Param⟧ := list[]
                fst := lst + 2
                lst := fst
                var multiple: Boolean := true

                //Iterates through all the parameters in this part
                while {multiple} do {
                    while {mstr.at (lst) != ":"} do {
                        lst := lst + 1
                    }

                    //Collect parameter name
                    var paramName: String := mstr.substringFrom(fst)to(lst - 1)
                    io.error.write "paramName: {paramName}"
                    fst := lst + 1
                    while {(mstr.at (lst) != ")") && (mstr.at (lst) != ",") && (mstr.at(lst) != "⟦")} do {
                        lst := lst + 1
                    }

                    //Collect parameter declared type.
                    var paramType: String := mstr.substringFrom(fst)to(lst - 1)

                    //Since any imported type that is not a prelude type will be
                    //saved as 'importName.typeName' in the types scope, we need
                    //to prepend 'importName' to places in a method signature
                    //that reference these types
                    if(anObjectType.preludeTypes.contains(paramType).not) then {
                        paramType := "{importName}.{paramType}"
                    }

                    //Checke if there are additional method parts
                    io.error.write "paramType = {paramType}"
                    if (mstr.at (lst) == ",") then {
                        fst := lst + 2
                        lst := fst
                    } else {
                        multiple := false
                    }

                    //Add this parameter to the parameter list, dtype of ident
                    //can be set to false because it is never used
                    ident := ast.identifierNode.new("{paramType}", false)
                    partParams.push(aParam.withName(paramName)
                                      ofType(anObjectType.definedByNode(ident)))
                }
                //Return from while-loop with the full part definition
                par := mstr.indexOf ("(") startingAt (lst)
                fst := lst + 1
                lst := par - 1
                parts.add (aMixPartWithName (partName) parameters (partParams))
            }
        } else { //This method is a member, the partName is the method's name
            var partName : String := mstr.substringFrom (fst)
                                                    to (mstr.indexOf(" →") - 1)
            // io.error.write "partName = {partName}"
            parts.add (aMixPartWithName (partName) parameters (list[]))
        }

        fst := mstr.indexOf ("→ ") startingAt (1) + 2
        if (fst < 1) then {
            io.error.write "no arrow in method type {mstr}"
        }

        //Collect the declared type that this method returns
        ret := mstr.substringFrom (fst) to (mstr.size)

        //Since any imported type that is not a prelude type will be saved as
        //'importName.typeName' in the types scope, we need to prepend
        //'importName'to places in a method signature that reference these types
        if(anObjectType.preludeTypes.contains(ret).not) then {
            ret := "{importName}.{ret}"
        }
        // io.error.write "ret = {ret}"

        //Construct the ObjectType of the return type, dtype of ident can be
        //set to false because it is never used
        ident := ast.identifierNode.new (ret, false)
        io.error.write "\n443: finding rType"
        def rType: ObjectType = anObjectType.definedByNode(ident)
        io.error.write "\n444: rType = {rType}"
        aMethodType.signature (parts) returnType (rType)
    }
    // if node is a method, class, method signature,
    // def, or var, create appropriate method type
    method fromNode (node: AstNode) → MethodType {
        match (node) case { meth : share.Method | share.Class | share.MethodSignature →
            io.error.write "\n573: node matched as method: {meth}"

            def signature: List⟦MixPart⟧ = list[]

            for (meth.signature) do { part:AstNode →
                def params: List⟦Param⟧ = list[]

                for (part.params) do { param: AstNode → // not of type Param??
                    params.push (aParam.withName (param.value)
                        ofType (anObjectType.definedByNode (param.dtype)))
                }

                signature.push (aMixPartWithName (part.name) parameters (params))
            }

            io.error.write "\n443: finding rType"
            def rType: AstNode = match (meth)
                case { m : share.Method | share.Class → m.dtype}
                case { m : share.MethodSignature → meth.rtype}
            io.error.write "found rType {rType} on {meth}"
            return signature (signature)
                returnType (anObjectType.definedByNode (rType))
        } case { defd : share.Def | share.Var →
            io.error.write "\n574: defd: {defd}"
            io.error.write "\n575: defd.dtype {defd.dtype}"
            def signature: List⟦MixPart⟧ =
                    list[aMixPartWithName (defd.name.value) parameters (list[])]
            def dtype: ObjectType = if (defd.dtype == false) then {
                anObjectType.dynamic
            } else {
                anObjectType.definedByNode (defd.dtype)
            }
            return signature (signature) returnType (dtype)
        } case { _ →
            Exception.raise "unrecognised method node" with(node)
        }
    }
}


// Object type information.

def noSuchMethod: outer.Pattern is readable = object {
    inherit BasicPattern.new

    method match(obj : Object) {
        if(self.isMe(obj)) then {
            SuccessfulMatch.new(self, list[])
        } else {
            FailedMatch.new(obj)
        }
    }
}

def noSuchType: outer.Pattern = object {
    inherit BasicPattern.new

    method match(obj : Object) {
        if(self.isMe(obj)) then {
            SuccessfulMatch.new(self, list[])
        } else {
            FailedMatch.new(obj)
        }
    }
}




def anObjectType: ObjectTypeFactory is public = object {

    //Version of ObjectType that allows for lazy-implementation of type checking
    //Holds the AstNode that can be resolved to the real ObjectType
    class definedByNode (node: AstNode) -> ObjectType{
        io.error.write ("In definedByNode with {node} representing type" ++
            self.asString)
        method methods -> Set⟦MethodType⟧ { resolve.methods }

        method getMethod (name : String) → MethodType | noSuchMethod {
            resolve.getMethod(name)
        }

        //Process the AstNode to get its ObjectType
        method resolve -> ObjectType { fromDType(node) }

        //an ObjectType is unexpanded if it still holds an AstNode
        def isResolved : Boolean is public = false

        def isDynamic : Boolean is public = false

        method == (other:ObjectType) → Boolean { resolve == other.resolve}

        method isSubtypeOf (other : ObjectType) -> Boolean {
            resolve.isSubtypeOf(other.resolve)
        }

        method isSubtypeHelper(trials:List⟦TypePair⟧, other:ObjectType) → Answer {
            resolve.isSubtypeHelper(trials, other.resolve)
        }

        method restriction (other : ObjectType) → ObjectType {
            resolve.restriction(other.resolve)
        }

        method isConsistentSubtypeOf (other : ObjectType) → Boolean{
            resolve.isConsistentSubtypeOf(other.resolve)
        }

        method getVariantTypes → List⟦ObjectType⟧ { resolve.getVariantTypes }

        method setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done {
            resolve.setVariantTypes(newVariantTypes)
        }

        method | (other : ObjectType) → ObjectType { resolve | (other.resolve) }

        method & (other : ObjectType) → ObjectType { resolve & (other.resolve) }

        method asString → String is override {
            match(node) case { (false) →
                "Unknown"
            } case { typeLiteral : share.TypeLiteral →
                "UnresolvedTypeLiteral"
            } case { op : share.Operator →
                "{definedByNode(op.left)}{op.value}{definedByNode(op.right)}"
            } case { ident : share.Identifier →
                "{ident.value}"
            } case { generic : share.Generic →
                "{generic.value.value}"
            } case { member : share.Member →
                "{member.receiver.nameString}.{member.value}"
            } case { _ →
                ProgrammingError.raise ("No case in method 'asString' of the" ++
                    "class definedByNode for node of kind {node.kind}") with(node)
            }
        }
    }


    method fromMethods (methods' : Set⟦MethodType⟧) → ObjectType {
        object {
            // List of variant types (A | B | ... )
            var variantTypes: List⟦ObjectType⟧ := list[]

            def methods : Set⟦MethodType⟧ is public = (if (base == dynamic)
                then { emptySet } else { emptySet.addAll(base.methods) }).addAll(methods')

            method getMethod(name : String) → MethodType | noSuchMethod {
                for(methods) do { meth →
                    if(meth.nameString == name) then {
                        return meth
                    }
                }
                return noSuchMethod
            }

            method resolve -> ObjectType { self }

            def isResolved : Boolean is public = true

            def isDynamic : Boolean is public = false

            //TODO: not sure we trust this. May have to refine == in the future
            method == (other:ObjectType) → Boolean { self.isMe(other) }

            //Check if 'self', which is the ObjectType calling this method, is
            //a subtype of 'other'
            method isSubtypeOf(other : ObjectType) → Boolean {
                def helperResult : Answer = self.isSubtypeHelper(emptyList, other.resolve)
                //io.error.write("\n751 The trials from subtyping were: {helperResult.trials}")

                helperResult.ans
            }

            //Make confidential
            //helper method for subtyping a pair of non-variant types
            method isNonvariantSubtypeOf(trials': List⟦TypePair⟧,
                                                  other:ObjectType) → Answer {
                def selfOtherPair : TypePair = typePair(self, other)

                //if trials already contains selfOtherPair, we can assume self <: other
                if(trials'.contains(selfOtherPair) || self.isMe(other)) then{
                    return answerConstructor(true, trials')
                } else{
                    var trials : List⟦TypePair⟧ := trials'
                    trials.add(selfOtherPair)

                    //for each method in other, check that there is a corresponding
                    //method in self
                    for (other.methods) doWithContinue { otherMeth, continue→
                        for (self.methods) do { selfMeth→
                            def isSpec: Answer =
                                  selfMeth.isSpecialisationOf(trials, otherMeth)
                            trials := isSpec.trials

                            if (isSpec.ans) then { continue.apply }
                        }
                        //io.error.write "\n885: didn't find {otherMeth} in {self}"
                        io.error.write "\n other methods: {other.methods}"
                        io.error.write "\n self methods: {self.methods}"

                        //fails to find corresponding method
                        return answerConstructor(false, trials)
                    }
                    return answerConstructor(true, trials)
                }
            }

            //helper method for subtyping a pair of ObjectTypes
            //
            //Param trials - Holds pairs of previously subtype-checked ObjectTypes
            //          Prevents infinite subtype checking of self-referential types
            //Param other - The ObjectType that self is checked against
            method isSubtypeHelper(trials:List⟦TypePair⟧, other':ObjectType) → Answer {
                def other : ObjectType = other'.resolve
                if(self.isMe(other)) then {
                    return answerConstructor(true, trials)
                }

                if(other.isDynamic) then {
                    return answerConstructor(true,trials)
                }

                if(other == anObjectType.doneType) then {
                    return answerConstructor(true, trials)
                } elseif{self == anObjectType.doneType} then {
                    return answerConstructor(false, trials)
                }

                var helperResult : Answer := answerConstructor(false, trials)

                // Divides subtyping into 4 cases
                if(self.getVariantTypes.size == 0) then {
                    if (other.getVariantTypes.size == 0) then {
                        //Neither self nor other are variant types
                        return self.isNonvariantSubtypeOf(trials, other)
                    } else {
                        //self is not a variant type; other is
                        for (other.getVariantTypes) do {t:ObjectType →
                            helperResult := self.isNonvariantSubtypeOf(trials, t)
                            if (helperResult.ans) then{
                                return helperResult
                            }
                        }
                        return helperResult
                    }
                } else {
                    if (other.getVariantTypes.size == 0) then {
                        //self is a variant type; other is not
                        for (self.getVariantTypes) do {t:ObjectType →
                            helperResult := t.isNonvariantSubtypeOf(trials, other)
                            if (helperResult.ans.not) then {
                                return helperResult
                            }
                        }
                        return helperResult
                    } else {
                        //Both self and other are variant types
                        for (self.getVariantTypes) do {t:ObjectType →
                            helperResult := t.isSubtypeHelper(helperResult.trials, other)
                            if (helperResult.ans.not) then {
                                return helperResult
                            }
                        }
                        return helperResult
                    }
                }
            }

            method restriction(other : ObjectType) → ObjectType {
                if (other.isDynamic) then { return dynamic}
                def restrictTypes:Set⟦ObjectType⟧ = emptySet
                // Restrict matching methods
                for(methods) doWithContinue { meth, continue →
                  // Forget restricting if it is a type
                  if (asString.substringFrom (1) to (7) != "Pattern") then {
                    for(other.methods) do { meth' →
                      if(meth.name == meth'.name) then {
                        restrictTypes.add(meth.restriction(meth'))
                        continue.apply
                      }
                    }
                  }
                  restrictTypes.add(meth)
                }
                return object {
                  //Joe - not sure how to handle restrict; probably wants to keep the types
                  //Maybe check if they share same type name and keep those?
                  inherit anObjectType.fromMethods(restrictTypes)

                  method asString → String is override {
                    "{outer}|{other}"
                  }
                }
            }

            // Consistent-subtyping:
            // If self restrict other is a subtype of other restrict self.
            method isConsistentSubtypeOf(other : ObjectType) → Boolean {
                return self.isSubtypeOf(other.resolve)

                //TODO: Fix restriction() so that it handles variant types
                //def selfRestType = self.restriction(other)
                //def otherRestType = other.restriction(self)
                //io.error.write "self's restricted type is {selfRestType}"
                //io.error.write "other's restricted type is {otherRestType}"

                //return selfRestType.isSubtypeOf(otherRestType)  //  FIX!!!
                //true
            }

            method getVariantTypes → List⟦ObjectType⟧ { variantTypes }

            method setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done {
                variantTypes := newVariantTypes
            }

            // Variant
            // Construct a variant type from two object types.
            // Note: variant types can only be created by this constructor.
            method |(other' : ObjectType) → ObjectType {
                def other : ObjectType = other'.resolve
                if(self == other) then { return self }
                if(other.isDynamic) then { return dynamic }

                def combine: Set⟦MethodType⟧ = emptySet

                // Variant types of the new object.
                var newVariantTypes := list[]

                // If self is a variant type, add its variant types
                // to the new object type's variant types.
                // If self is not a variant type, add itself to the
                // new object type's variant types.
                if (self.getVariantTypes.size != 0) then {
                  newVariantTypes := newVariantTypes ++ self.getVariantTypes
                } else {
                  newVariantTypes.push(self)
                }

                // If other is a variant type, add its variant types
                // to the new object type's variant types.
                // If other is not a variant type, add itself to the
                // new object types's variant types.
                if (other.getVariantTypes.size != 0) then {
                  newVariantTypes := newVariantTypes ++ other.getVariantTypes
                } else {
                  newVariantTypes.push(other)
                }

                return object {
                    //Joe - save types in common | ignore
                    inherit anObjectType.fromMethods(combine)

                    // Set the new object type's variant types to equal
                    // the new variant types.
                    self.setVariantTypes(newVariantTypes)

                    method asString → String is override {
                        "{outer} | {other}"
                    }

                }
            }

            method &(other' : ObjectType) → ObjectType {
                def other : ObjectType = other'.resolve

                if(self == other) then { return self }
                if(other.isDynamic) then {
                    return dynamic
                }

                //components from performing &-operator on variant types
                def components:List⟦ObjectType⟧ = emptyList

                if(self.getVariantTypes.size == 0) then {
                    if (other.getVariantTypes.size == 0) then {
                        //Neither self nor other are variant types
                        return self.andHelper(other)
                    } else {
                        //self is not a variant type; other is
                        for (other.getVariantTypes) do {t:ObjectType →
                            components.add(self.andHelper(t))
                        }
                    }
                } else {
                    if (other.getVariantTypes.size == 0) then {
                        //self is a variant type; other is not
                        for (self.getVariantTypes) do {t:ObjectType →
                            components.add(other.andHelper(t))
                        }
                    } else {
                        //Both self and other are variant types
                        for (self.getVariantTypes) do {t:ObjectType →
                            components.add(t&(other))
                        }
                    }
                }
                //Helper method does not work with Done
                fromObjectTypeList(components)
            }

            //Make confidential
            method andHelper(other: ObjectType) → ObjectType {
                def combine: Set⟦ObjectType⟧ = emptySet
                def twice = emptySet

                // Produce union between two object types.
                for(methods) doWithContinue { meth, continue →
                    for(other.methods) do { meth':MethodType →
                        if(meth.nameString == meth'.nameString) then {
                            if(meth.isSpecialisationOf(emptyList,meth').ans) then {
                                combine.add(meth)
                            } elseif{meth'.isSpecialisationOf(emptyList,meth).ans} then {
                                combine.add(meth')
                            } else {
                                // TODO: Perhaps generate lub of two types?
                                TypeError.raise("cannot produce union of " ++
                                    "incompatible types '{self}' and '{other}' because of {meth'}")
                            }

                            twice.add(meth.name)

                            continue.apply
                        }
                    }
                    combine.add(meth)
                }

                for(other.methods) do { meth →
                    if(twice.contains(meth.name).not) then {
                        combine.add(meth)
                    }
                }

                def selfToPrint: ObjectType = self

                object {
                    //Joe - comeback and write checking for types of same name using subtyping
                    inherit anObjectType.fromMethods(combine)

                    //method asString → String is override {
                    //    "\{{self.methods}\} & {other}"
                    //}

                    method asString → String is override {
                        "{selfToPrint} & {other}"
                    }
                }
            }

            method asString → String is override {
                if(methods.size == base.methods.size) then { return "Object" }

                var out: String := "\{ "

                for(methods) do { mtype: MethodType →
                    if(base.methods.contains(mtype).not) then {
                        out := "{out}\n    {mtype}; "
                    }
                }

                return "{out}\n  \}"
            }
        }
    }

    method fromMethods(methods' : Set⟦MethodType⟧)
                                          withName(name : String) → ObjectType {
        object {
            inherit fromMethods(methods')

            method asString → String is override {
                if(methods.size == base.methods.size) then { return "Object" }

                var out: String := name

                for(methods') do { mtype: MethodType →
                    out := "{out}\{ "
                    if(base.methods.contains(mtype).not) then {
                        out := "{out}\n    {mtype}; "
                    }
                    out := "{out}\n  \}"
                }

                return "{out}"
            }

        }
    }

    //takes an AstNode and returns its corresponding ObjectType
    method fromDType(dtype: AstNode) → ObjectType {
        match(dtype) case { (false) →
            dynamic
        } case { typeDec : share.TypeDeclaration →
            ProgrammingError.raise "Types cannot be declared inside other types or objects"
        } case { typeLiteral : share.TypeLiteral →
            def meths : Set⟦MethodType⟧ = emptySet
            io.error.write "\n952: processing {typeLiteral}"
            //collect MethodTypes
            for(typeLiteral.methods) do { mType : AstNode →
                meths.add(aMethodType.fromNode(mType))
            }

            anObjectType.fromMethods(meths)

        } case { op: share.Operator →
            // Operator takes care of type expressions: Ex. A & B, A | C
            // What type of operator (& or |)?
            var opValue: String := op.value

            // Left side of operator
            var left: AstNode := op.left
            var leftType: ObjectType := fromDType(left)

            // Right side of operator
            var right: AstNode := op.right
            var rightType: ObjectType := fromDType(right)

            match(opValue) case { "&" →
              leftType & rightType
            } case { "|" →
              leftType | rightType
            } case { _ →
              ProgrammingError.raise("Expected '&' or '|', got {opValue}") with(op)
            }

        } case { ident : share.Identifier →
            def oType : ObjectType = scope.types.findAtTop(ident.value)
                butIfMissing{ScopingError.raise("Failed to find {ident.value}")}
            io.error.write "\n984: processing {ident}"

            //If the type we are referencing is unexpanded, then expand it and
            //update its entry in the type scope
            if(oType.isResolved) then{
                return oType
            } else {
                def resolvedOType : ObjectType = oType.resolve
                scope.types.addToTopAt(ident.value) put (resolvedOType)
                return resolvedOType
            }

        } case { generic : share.Generic →
            //should we raise an error or return dynamic if not found in scope?
            scope.types.findAtTop(generic.value.value)
                butIfMissing{ScopingError.raise("Failed to find {generic.value.value}")}

        } case { member : share.Member →
            def receiverName : String = member.receiver.nameString
            def memberCall : String = "{receiverName}.{member.value}"
            //all members processed here are references to types, so we can ignore
            //these receivers since types are always at the top level of the scope
            if((receiverName == "self") || (receiverName == "module()object")) then {
                scope.types.findAtTop (member.value) butIfMissing {
                    ScopingError.raise("Failed to find {memberCall}")
                }
            } else {
                scope.types.findAtTop(memberCall) butIfMissing {
                    ScopingError.raise("Failed to find {memberCall}")
                }
            }

        } case { str : share.StringLiteral →
            anObjectType.string

        } case { num : share.NumberLiteral →
            anObjectType.number

        } case { _ →
            ProgrammingError.raise "No case for node of kind {dtype.kind}" with(dtype)
        }
    }

    //Find ObjectType corresponding to the identifier in the scope
    method fromIdentifier(ident : share.Identifier) → ObjectType {
        io.error.write "\n1249 looking for {ident.value} inside {scope.types}"
        scope.types.find(ident.value) butIfMissing { dynamic }
    }


    method dynamic → ObjectType {
        object {
            def methods: Set⟦MethodType⟧ is public = sg.emptySet

            method getMethod(_ : String) → noSuchMethod { noSuchMethod }

            method resolve -> ObjectType { self }

            def isResolved : Boolean is public = true

            def isDynamic : Boolean is public = true

            method ==(other:ObjectType) → Boolean{self.isMe(other)}

            method isSubtypeOf(_ : ObjectType) → Boolean { true }

            method isSubtypeHelper (_ : List⟦TypePair⟧, _ : ObjectType) → Answer {
                answerConstructor(true , emptyList)
            }

            method restriction(_ : ObjectType) → dynamic { dynamic }

            method isConsistentSubtypeOf(_ : ObjectType) → Boolean { true }

            method getVariantTypes → List⟦ObjectType⟧ { emptyList }

            method setVariantTypes(newVariantTypes:List⟦ObjectType⟧) → Done { }

            method |(_ : ObjectType) → dynamic { dynamic }

            method &(_ : ObjectType) → dynamic { dynamic }

            def asString : String is public, override = "Unknown"

        }
    }

    method bottom → ObjectType {
        object {
            inherit dynamic
            def isDynamic : Boolean is public, override = false
            def asString : String is public, override = "Bottom"
        }
    }

    method blockTaking(params : List⟦Parameter⟧)
            returning(rType : ObjectType) → ObjectType {
        def signature = list[aMixPartWithName("apply") parameters(params)]
        def meths: Set⟦MethodType⟧ = emptySet
        meths.add(aMethodType.signature(signature) returnType(rType))

        //Joe - Is there anytime where we want to save the internal types?
        //when a block has name??
        //when the last statement is an object or a typeDec?
        //In here we don't get the astNode; look at returnType?
        fromMethods(meths) withName("Block")
    }

    method blockReturning(rType : ObjectType) → ObjectType {
        blockTaking(list[]) returning(rType)
    }

    // add method to oType.  Only use this variant if method is parameterless
    method addTo (oType : ObjectType) name (name' : String)
            returns (rType : ObjectType) → Done is confidential {
        def signature = list[aMixPartWithName(name') parameters(list[])]
        oType.methods.add (aMethodType.signature(signature) returnType(rType))
    }

    // add method to oType.  Only use this variant if one part with one or more
    // parameters
    method addTo (oType : ObjectType) name (name' : String)
            params (ptypes : List⟦ObjectType⟧) returns (rType : ObjectType)
            → Done is confidential {
        def parameters = list[]
        for(ptypes) do { ptype →
            parameters.push(aParam.ofType(ptype))
        }

        def signature = list[aMixPartWithName(name') parameters (parameters)]

        oType.methods.add (aMethodType.signature(signature) returnType (rType))
    }

    // add method to oType.  Only use this variant for method with one part
    // and exactly one parameter
    method addTo (oType : ObjectType) name (name' : String)
            param(ptype : ObjectType) returns (rType : ObjectType)
            → Done is confidential {
        def parameters = list[aParam.ofType(ptype)]

        def signature = list[aMixPartWithName(name') parameters(parameters)]

        oType.methods.add (aMethodType.signature(signature) returnType(rType))
    }

    // add method to oType.  Only use if more than one part.
    method addTo (oType: ObjectType) names (name: List⟦String⟧)
         parts(p: List⟦List⟦ObjectType⟧ ⟧) returns (rType: ObjectType) → Done
                                    is confidential{
         def parts: List⟦List⟦Param⟧⟧ = list[]
         var nameString: String := ""
         for (p) do { part: List⟦ObjectType⟧ →
             def parameters: List⟦Param⟧ = list[]
             for (part) do {ptype: ObjectType →
                 parameters.push(aParam.ofType(ptype))
             }
             parts.push(parameters)
         }

         def signature: List⟦MixPart⟧ = list[]
         for (1 .. name.size) do {i →
             signature.push(aMixPartWithName (name.at(i)) parameters (parts.at(i)))
         }
         oType.methods.add (aMethodType.signature (signature) returnType (rType))
    }


    method extend(this : ObjectType) with(that : ObjectType)
            → Done is confidential {
        this.methods.addAll(that.methods)
    }

    // TODO: Make sure get everything from standardGrace and
    // StandardPrelude
    var base : ObjectType is readable := dynamic
    def doneType : ObjectType is public = fromMethods(sg.emptySet) withName("Done")
    base := fromMethods(sg.emptySet) withName("Object")

    //Used for type-checking imports; please update when additional types are added
    def preludeTypes: Set⟦String⟧ is public = ["Pattern", "Iterator", "Boolean", "Number",
                                    "String", "List", "Set", "Sequence",
                                    "Dictionary", "Point", "Binding",
                                    "Collection", "Enumerable", "Range"]

    def pattern : ObjectType is public = fromMethods(sg.emptySet) withName("Pattern")
    def iterator : ObjectType is public = fromMethods(sg.emptySet) withName("Iterator")
    def boolean : ObjectType is public = fromMethods(sg.emptySet) withName("Boolean")
    def number : ObjectType is public = fromMethods(sg.emptySet) withName("Number")
    def string : ObjectType is public = fromMethods(sg.emptySet) withName("String")
    def listTp : ObjectType is public = fromMethods(sg.emptySet) withName("List")
    def set : ObjectType is public = fromMethods(sg.emptySet) withName("Set")
    def sequence : ObjectType is public = fromMethods(sg.emptySet) withName("Sequence")
    def dictionary : ObjectType is public = fromMethods(sg.emptySet) withName("Dictionary")
    def point : ObjectType is public = fromMethods(sg.emptySet) withName("Point")
    def binding : ObjectType is public = fromMethods(sg.emptySet) withName("Binding")
    def collection : ObjectType is public = fromMethods(sg.emptySet) withName("Collection")
    def enumerable : ObjectType is public = fromMethods(sg.emptySet) withName("Enumerable")
    def rangeTp : ObjectType is public = fromMethods(sg.emptySet) withName("Range")
    def prelude: ObjectType is public = fromMethods(sg.emptySet) withName("Prelude")
    def boolBlock: ObjectType is public = fromMethods(sg.emptySet) withName("BoolBlock")
    def doneBlock: ObjectType is public = fromMethods(sg.emptySet) withName("DoneBlock")
    def dynamicDoneBlock: ObjectType is public = fromMethods(sg.emptySet) withName("DynamicDoneBlock")

//    addTo (base) name ("==") param(base) returns(boolean)
    addTo (base) name ("≠") param(base) returns(boolean)
    addTo (base) name ("hash") returns(number)
//    addTo (base) name ("match") returns(dynamic)
    addTo (base) name ("asString") returns(string)
    addTo (base) name ("basicAsString") returns(string)
    addTo (base) name ("asDebugString") returns(string)
//    addTo (base) name ("debugValue") returns(string)
//    addTo (base) name ("debugIterator") returns(iterator)
    addTo (base) name ("::") returns(binding)
    addTo (base) name ("list") param(collection) returns(listTp)

    extend (pattern) with (base)
    addTo (pattern) name ("match") param (base) returns (dynamic)
    addTo (pattern) name ("|") param (pattern) returns (pattern)
    addTo (pattern) name("&") param (pattern) returns (pattern)

    extend (iterator) with (base)
    addTo (iterator) name ("hasNext") returns (boolean)
    addTo (iterator) name ("next") returns (dynamic)

    def shortCircuit: ObjectType =
        blockTaking (list[aParam.ofType(blockReturning(dynamic))]) returning (base)
    extend (boolean) with(base)
    addTo (boolean) name("&&") param(boolean) returns (boolean)
    addTo (boolean) name("||") param(boolean) returns (boolean)
    addTo (boolean) name("prefix!") returns (boolean)
    addTo (boolean) name("not") returns (boolean)
    addTo (boolean) name("andAlso") param(shortCircuit) returns (dynamic)
    addTo (boolean) name("orElse") param(shortCircuit) returns (dynamic)
    addTo (boolean) name ("==") param (base) returns (boolean)

    extend (number) with(base)
    addTo (number) name("+") param(number) returns(number)
    addTo (number) name("*") param(number) returns(number)
    addTo (number) name("-") param(number) returns(number)
    addTo (number) name("/") param(number) returns(number)
    addTo (number) name("^") param(number) returns(number)
    addTo (number) name("%") param(number) returns(number)
    addTo (number) name("@") param(number) returns(point)
    addTo (number) name("hashcode") returns(string)
    addTo (number) name("++") param(base) returns(string)
    addTo (number) name("<") param(number) returns(boolean)
    addTo (number) name(">") param(number) returns(boolean)
    addTo (number) name ("==") param(base) returns(boolean)
    addTo (number) name("<=") param(number) returns(boolean)
    addTo (number) name("≤") param(number) returns(boolean)
    addTo (number) name(">=") param(number) returns(boolean)
    addTo (number) name("≥") param(number) returns(boolean)
    addTo (number) name("..") param(number) returns(listTp)
    addTo (number) name("asInteger32") returns(number)
    addTo (number) name("prefix-") returns(number)
    addTo (number) name("inBase") param(number) returns(number)
    addTo (number) name("truncated") returns(number)
    addTo (number) name("rounded") returns(number)
    addTo (number) name("prefix<") returns(pattern)
    addTo (number) name("prefix>") returns(pattern)
    addTo (number) name("abs") returns(number)

    def ifAbsentBlock: ObjectType = blockTaking (list[]) returning (dynamic)
    def stringDoBlock: ObjectType = blockTaking (list[aParam.ofType(string)])
            returning(doneType)
    def stringKeysValuesDoBlock: ObjectType =
        blockTaking (list[aParam.ofType(number), aParam.ofType(string)])
           returning (doneType)
    extend (string) with(base)
    addTo (string) name("*") param(number) returns(string)
    addTo (string) name("&") param(pattern) returns(pattern)
    addTo (string) name("++") param(base) returns(string)
    addTo (string) name ("==") param(string) returns(boolean)
    addTo (string) name(">") param(string) returns(boolean)
    addTo (string) name(">=") param(string) returns(boolean)
    addTo (string) name("<") param(string) returns(boolean)
    addTo (string) name("<=") param(string) returns(boolean)
    addTo (string) name("≤") param(string) returns(boolean)
    addTo (string) name("≥") param(string) returns(boolean)
    addTo (string) name("at") param(number) returns(string)
    addTo (string) name("asLower") returns(string)
    addTo (string) name("asNumber") returns(number)
    addTo (string) name("asUpper") returns(string)
    addTo (string) name("capitalized") returns(string)
    addTo (string) name("compare") param(string) returns(boolean)
    addTo (string) name("contains") param(string) returns(boolean)
    addTo (string) name("encode") returns(string)
    addTo (string) name("endsWith") param(string) returns(boolean)
    addTo (string) name ("indexOf") param(string) returns (number)
    addTo(string) names (list["indexOf","startingAt"])
           parts(list [ list[string], list[number] ]) returns (number)
//    addTo(string) names(["indexOf","startingAt","ifAbsent"])
//           parts([ [string], [number],[ifAbsentBlock] ]) returns(number | dynamic)
//    addTo(string) names(["indexOf","startingAt","ifAbsent"])
//           parts([ [string], [number],[ifAbsentBlock] ]) returns(number | dynamic)
    addTo (string) name ("lastIndexOf") param(string) returns(number)
    addTo (string) names (list["lastIndexOf","startingAt"])
           parts(list[ list[string], list[number] ]) returns (number)
//    addTo(string) names(["lastIndexOf","ifAbsent"]) parts([ [string], [ifAbsentBlock] ]) returns(number | dynamic)
//    addTo(string) names(["lastIndexOf","startingAt","ifAbsent"]) parts([ [string], [number],[ifAbsentBlock] ]) returns(number | dynamic)
    addTo(string) name ("indices") returns(listTp)
    addTo(string) name("isEmpty") returns(boolean)
    addTo(string) name("iterator") returns(base)
    addTo(string) name("lastIndexOf") param(string) returns(number)
//    addTo(string) name("lastIndexOf()ifAbsent") params(string, ifAbsentBlock) returns(number | dynamic)
//    addTo(string) name("lastIndexOf()startingAt()ifAbsent") params(string, ifAbsentBlock) returns(number | dynamic)
    addTo(string) name("ord") returns(number)
    addTo(string) names(list["replace","with"]) parts(list[ list[string], list[string] ]) returns(string)
    addTo(string) name("size") returns(number)
    addTo(string) name("startsWith") param(string) returns(boolean)
    addTo(string) name("startsWithDigit") returns(boolean)
    addTo(string) name("startsWithLetter") returns(boolean)
    addTo(string) name("startsWithPeriod") returns(boolean)
    addTo(string) name("startsWithSpace") returns(boolean)
    addTo(string) names(list["substringFrom","size"])
        parts(list[ list[number], list[number] ]) returns(string)
    addTo(string) names(list["substringFrom","to"])
        parts(list[ list[number], list[number] ]) returns(string)
    addTo(string) name("_escape") returns(string)
    addTo(string) name("trim") returns(string)
    addTo(string) name("do") param(stringDoBlock) returns (doneType)
    addTo(string) name("size") returns(number)
    addTo(string) name("iter") returns(iterator)

    extend(point) with(base)
    addTo (point) name ("==") param(point) returns(boolean)
    addTo(point) name("x") returns(number)
    addTo(point) name("y") returns(number)
    addTo(point) name("distanceTo") param(point) returns(number)
    addTo(point) name("+") param(point) returns(point)
    addTo(point) name("-") param(point) returns(point)
    addTo(point) name("*") param(point) returns(point)
    addTo(point) name("/") param(point) returns(point)
    addTo(point) name("length") returns(number)

    def fold: ObjectType = blockTaking(list[aParam.ofType(dynamic), aParam.ofType(dynamic)])
        returning (dynamic)
    extend (listTp) with (base)
    addTo (listTp) name("at") param(number) returns(dynamic)
    addTo(listTp) names(list["at","put"]) parts(list[ list[number], list[dynamic] ]) returns(doneType)
    addTo(listTp) name("push") param(dynamic) returns(doneType)
    addTo(listTp) name("add") param(dynamic) returns(listTp)
    addTo(listTp) name("addFirst") param(dynamic) returns(listTp)   // need to add varparams
    addTo(listTp) name("addLast") param(dynamic) returns(listTp)
    addTo(listTp) name("addAll") param(listTp) returns(listTp)
    addTo(listTp) name("pop") returns(dynamic)
    addTo(listTp) name("size") returns(number)
    addTo(listTp) name("iter") returns(iterator)
    addTo(listTp) name("iterator") returns(iterator)
    addTo(listTp) name("contains") param(dynamic) returns(boolean)
    addTo(listTp) name("indexOf") param(dynamic) returns(number)
    addTo(listTp) name("indices") returns(listTp)
    addTo(listTp) name("first") returns(dynamic)
    addTo(listTp) name("last") returns(dynamic)
    addTo(listTp) name("prepended") param(dynamic) returns(listTp)
    addTo(listTp) name("++") param(listTp) returns (listTp)
    addTo(listTp) name("reduce") params(list[dynamic, fold]) returns (dynamic)
    addTo(listTp) name("reversed") returns(dynamic)
    addTo(listTp) name("removeFirst") returns(dynamic)
    addTo(listTp) name("removeLast") returns(dynamic)
    addTo(listTp) name("removeAt") param(number) returns(dynamic)
    addTo(listTp) name("remove") param(dynamic) returns(listTp)
    addTo(listTp) name("removeAll") param(listTp) returns(listTp)
    addTo(listTp) name("copy") returns(listTp)
    addTo(listTp) name("sort") returns(listTp)
    addTo(listTp) name("reverse") returns(listTp)
    addTo (listTp) name ("==") param(listTp) returns(boolean)

    extend(binding) with(base)
    addTo(binding) name("key") returns(dynamic)
    addTo(binding) name("value") returns(dynamic)

    addTo(boolBlock) name("apply") returns(boolean)
    addTo(doneBlock) name("apply") returns(doneType)


    addTo (prelude) name("print") param(base) returns(doneType)
    addTo (prelude) names(list["while", "do"]) parts(list[list[boolBlock], list[doneBlock] ]) returns(doneType)
    addTo (prelude) names(list["for", "do"]) parts(list[list[listTp], list[dynamicDoneBlock] ]) returns(doneType)

    scope.types.at("Unknown") put(dynamic)
    scope.types.at("Done") put(doneType)
    scope.types.at("Object") put(base)
    scope.types.at("Pattern") put(pattern)
    scope.types.at("Boolean") put(boolean)
    scope.types.at("Number") put(number)
    scope.types.at("String") put(string)
    scope.types.at("List") put(listTp)
    scope.types.at("Set") put(set)
    scope.types.at("Sequence") put(sequence)
    scope.types.at("Dictionary") put(dictionary)
    scope.types.at("Point") put(point)
    scope.types.at("Binding") put(binding)
    scope.types.at("Range") put(rangeTp)

    addVar("Unknown") ofType(pattern)
    addVar("Dynamic") ofType(pattern)
    addVar("Done") ofType(pattern)
    addVar("Object") ofType(pattern)
    addVar("Pattern") ofType(pattern)
    addVar("Boolean") ofType(pattern)
    addVar("Number") ofType(pattern)
    addVar("String") ofType(pattern)
    addVar("List") ofType(pattern)
    addVar("Set") ofType(pattern)
    addVar("Sequence") ofType(pattern)
    addVar("Dictionary") ofType(pattern)
    addVar("Point") ofType(pattern)
    addVar("Binding") ofType(pattern)
    addVar("Range") ofType(pattern)

    addVar("done") ofType(self.doneType)
    addVar("true") ofType(boolean)
    addVar("false") ofType(boolean)
    addVar("prelude") ofType (prelude)
}

// Adds name to variables and as parameterless method (really def, not var!)
method addVar (name : String) ofType (oType : ObjectType) → Done is confidential {
    scope.variables.at (name) put (oType)
    scope.methods.at (name) put (aMethodType.member(name) ofType(oType))
}

// For loop with continue.
method for(a) doWithContinue(bl) → Done is confidential {
    for(a) do { e →
        continue'(e, bl)
    }
}

method continue'(e, bl) → Done is confidential {
    bl.apply(e, { return })
}

    //Takes a non-empty list of objectTypes and combines them into a variant type
method fromObjectTypeList(oList : List⟦ObjectType⟧)→ObjectType{
      var varType: ObjectType := oList.at(1)
      var index:Number := 2
      while{index<=oList.size}do{

        //Combine types that are subsets of one-another
        if (varType.isSubtypeOf (oList.at(index))) then {
            varType := oList.at(index)
        } elseif {oList.at(index).isSubtypeOf(varType).not} then {
            varType := varType | oList.at(index)
        }

        index := index +1
      }
      varType

}
