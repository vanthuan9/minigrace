#pragma ExtendedLineups
#pragma noTypeChecks
dialect "none"
import "standardGrace" as sg

import "ast" as ast
import "xmodule" as xmodule
import "io" as io
import "SharedTypes" as share
import "ScopeModule" as sc
import "ObjectTypeModule" as ot

inherit sg.methods

type MethodType = share.MethodType
type ObjectType = share.ObjectType
type ObjectTypeFactory = share.ObjectTypeFactory
type MethodTypeFactory = share.MethodTypeFactory
type AstNode = share.AstNode
type MixPart = share.MixPart
type Param = share.Param
type Parameter = share.Parameter

def cache: Dictionary = sc.cache
def allCache: Dictionary = sc.allCache
def anObjectType: share.ObjectTypeFactory = ot.anObjectType
def scope: share.Scope = sc.scope
def aParam: Param = ot.aParam
def aMethodType:MethodTypeFactory = ot.aMethodType


// Checker error

def CheckerFailure is public = Exception.refine "CheckerFailure"

// return the return type of the block (as declared)
method objectTypeFromBlock(block: AstNode) → ObjectType {
        def bType = typeOf(block)

        if(bType.isDynamic) then { return anObjectType.dynamic }

        def numParams: Number = block.params.size
        def applyName: String = if (numParams == 0) then {
            "apply"
        } else {
            "apply({numParams})"
        }
        def apply: MethodType = bType.getMethod(applyName)

        match(apply) case { (ot.noSuchMethod) →
            def strip = {x → x.nameString}
            TypeError.raise ("1000: the expression `{share.stripNewLines(block.toGrace(0))}` of " ++
                "type '{bType}' does not satisfy the type 'Block'") with(block)
        } case { meth : MethodType →
            return meth.returnType
        }
}

// Return the return type of the block as obtained by type-checking
// the last expression in the block
method objectTypeFromBlockBody(body: Sequence⟦AstNode⟧) → ObjectType {
    if(body.size == 0) then {
        anObjectType.doneType
    } else {
        typeOf(body.last)
    }
}


// check the type of node and insert into cache associated with the node
method checkTypes (node: AstNode) → Done {
    io.error.write "\n233: checking types of {node.nameString}"
    cache.at (node) ifAbsent {
        io.error.write "\n235: {node.nameString} not in cache"
        node.accept (astVisitor)
    }
}

// check type of node, put in cache & then return type
method typeOf (node: AstNode) → ObjectType {
    checkTypes (node)
    cache.at (node) ifAbsent {
        CheckerFailure.raise "cannot type non-expression {node}" with (node)
    }
}

// retrieve from cache the inheritable type of an object
method inheritableTypeOf (node: AstNode) → ObjectType {
    allCache.at (node) ifAbsent {
        CheckerFailure.raise "cannot find confidential type of {node}" with (node)
    }
}

// Exceptions while type-checking. (Currently not used)
def ObjectError: outer.ExceptionKind = TypeError.refine("ObjectError")

// Class declaration error. (Currently not used)
def ClassError: outer.ExceptionKind = TypeError.refine("Class TypeError")

// Declaration of method does not correspond to actual type
def MethodError = TypeError.refine("Method TypeError")

// Def and var declarations.  Type of def or var declaration does not
// correspond to value associated with it
def DefError: outer.ExceptionKind = TypeError.refine("Def TypeError")

// Scoping error declaration with imports
def ScopingError: outer.ExceptionKind = TypeError.refine("ScopingError")

// type of part of method request (actual call, not declaration)
type RequestPart = {
   args → List⟦AstNode⟧
   args:=(a: List⟦AstNode⟧) → Done
}

// Check if the signature and parameters of a request match
// the declaration, return the type of the result
method check (req : share.Request)
        against(meth : MethodType) → ObjectType is confidential {
    def name: String = meth.name   // CHANGE TO NAMESTRING

    for(meth.signature) and(req.parts) do { sigPart: MixPart, reqPart: RequestPart →
        def params: List⟦Param⟧ = sigPart.parameters
        def args: Collection⟦AstNode⟧   = reqPart.args

        def pSize: Number = params.size
        def aSize: Number = args.size

        if(aSize != pSize) then {
            def which: String = if (aSize > pSize) then { "many" } else { "few" }
            def where: Number = if (aSize > pSize) then {
                args.at (pSize + 1)
            } else {
            // Can we get beyond the final argument?
                req.value
            }

            outer.RequestError
                .raise("too {which} arguments to method part " ++
                    "'{sigPart.name}', expected {pSize} but got {aSize}")
                    with(where)
        }

        for (params) and (args) do { param: Param, arg: AstNode →
            def pType: ObjectType = param.typeAnnotation
            def aType: ObjectType = typeOf(arg)
            io.error.write ("\n1631 Checking {arg} of type {aType} is subtype of {pType}"++
                "\nwhile checking {req} against {meth}")
            if (aType.isConsistentSubtypeOf (pType).not) then {
                outer.RequestError.raise("the expression " ++
                    "`{stripNewLines(arg.toGrace(0))}` of type '{aType}' does not " ++
                    "satisfy the type of parameter '{param}' in the " ++
                    "method '{name}'") with(arg)
            }
        }
    }
    meth.returnType
}

// Throw error only if type of node is not consistent subtype of eType
method check (node: AstNode) matches (eType : ObjectType)
        inMethod (name : String) → Done is confidential {
    def aType: ObjectType = typeOf(node)
    if (aType.isConsistentSubtypeOf (eType).not) then {
        MethodError.raise("the method '{name}' declares a result of " ++
            "type '{eType}', but returns an expression of type " ++
            "'{aType}'") with (node)
    }
}

// break of input string into list of strings as divided by separator
method split (input : String, separator : String) → List⟦String⟧ {
    var start: Number := 1
    var end: Number := 1
    var output: List⟦ List⟦String⟧ ⟧ := list[]
    while {end < input.size} do {
        if (input.at(end) == separator) then {
            var cand := input.substringFrom(start)to(end-1)
            if (cand.size > 0) then {
                output.push(cand)
            }
            start := end + 1
        }
        end := end + 1
    }
    output.push(input.substringFrom(start)to(end))
    return output
}

// Pair of public and confidential types of an expression
// Generating objects
type PublicConfidential = {
    publicType → ObjectType
    inheritableType → ObjectType | false
}

// Returns pair of public and confidential type of expression that can be
// inherited from
class pubConf (pType: ObjectType, cType: ObjectType ) → PublicConfidential{
    method publicType → ObjectType {pType}
    method inheritableType → ObjectType {cType}
    method asString → String {
        "confidential type is {cType}\npublic type is {pType}"
    }
}


// Static type checker visitor
// methods return false if goes no further recursively
def astVisitor: ast.AstVisitor is public = object {
    inherit ast.baseVisitor

    // Default behavior serving as placeholder only for cases not yet implemented
    method checkMatch(node: AstNode) → Boolean {
        io.error.write "1436: checkMatch in astVisitor"
        true
    }

    // type-check if statement
    method visitIf (ifnode: share.If) → Boolean {
        def cond: AstNode = ifnode.value
        if (typeOf (cond).isConsistentSubtypeOf (anObjectType.boolean).not) then {
            outer.RequestError.raise ("1366: the expression `{stripNewLines (cond.toGrace (0))}` does not " ++
                "satisfy the type 'Boolean' for an 'if' condition'") with (cond)
        }

        def thenType: ObjectType = objectTypeFromBlock(ifnode.thenblock)

        def hasElse: Boolean = ifnode.elseblock.body.size > 0
        def elseType: ObjectType = if (hasElse) then {
            objectTypeFromBlock(ifnode.elseblock)
        } else {
            anObjectType.doneType
        }

        // type of expression is whichever branch has largest type.
        // If incompatible return variant formed by the two types
        def ifType: ObjectType = if (hasElse) then {
            if (thenType.isConsistentSubtypeOf (elseType)) then {
                elseType
            } elseif {elseType.isConsistentSubtypeOf(thenType)} then {
                thenType
            } else {
                thenType | elseType
            }
        } else {
            anObjectType.doneType
        }

        // save type in cache
        cache.at (ifnode) put (ifType)
        false
    }

    // Type check block.  Fails if don't give types to block parameters
    // params are identifier nodes.
    method visitBlock (block: AstNode) → Boolean {
        // Raises exception if block parameters not given types
        for (block.params) do {p→
            if (((p.kind == "identifier") || {p.wildcard.not}) && {p.decType.value=="Unknown"}) then {
                CheckerFailure.raise("no type given to declaration"
                    ++ " of parameter '{p.value}'") with (p)
            }
        }

        def body = sequence(block.body)
        var retType: ObjectType

        scope.enter {
            for(block.params) do { param →
                // Isn't param always a string?Special cases when using match
                // where pattern is string literal or number
                // I'm not sure this is right.  Doesn't seem like anything should be added
                // for literals!
                match (param)
                  case { _ : share.StringLiteral | share.NumberLiteral→
                    //scope.variables.at(param.value)
                    //    put(objectTypeFromDType(param))
              //} case { _ : NumberLiteral →
                    //scope.variables.at(param.value)
                    //    put(objectTypeFromDType(param))
                } case { _ →
                    io.error.write("\n1517: {param.value} has {param.dtype}")
                    scope.variables.at(param.value)
                                      put(anObjectType.fromDType(param.dtype))
                }
            }


            collectTypes(body)

            for(body) do { stmt: AstNode →
                checkTypes(stmt)
            }

            retType := objectTypeFromBlockBody(body)
        }
        // At this point, know block type checks.

        // Now compute type of block and put in cache
        def parameters = list[]
        for(block.params) do { param: AstNode →
            match (param)
              case { _:share.StringLiteral →
                parameters.push(aParam.withName(param.value)
                                    ofType(anObjectType.fromDType(param)))
            } case { _:share.NumberLiteral →
                parameters.push(aParam.withName(param.value)
                                    ofType(anObjectType.fromDType(param)))
            } case { _ →
                parameters.push(aParam.withName(param.value)
                                    ofType(anObjectType.fromDType(param.dtype)))
            }
        }

        def blockType: ObjectType = anObjectType.blockTaking(parameters)
            returning(retType)

        cache.at (block) put (blockType)
        io.error.write "block has type {blockType}"
        false
    }

    method visitMatchCase (node: share.MatchCase) → Boolean {
        def matchee = node.value
        var matcheeType: ObjectType := typeOf(matchee)
        //Note: currently only one matchee is supported
        def paramTypesList: List⟦ObjectType⟧ = emptyList
        def returnTypesList: List⟦ObjectType⟧ = emptyList
        var paramType: ObjectType
        var returnType: ObjectType

        //goes through each case{} and accumulates its parameter and return types
        for(node.cases) do{block →

          if(block.params.size != 1) then{
            outer.RequestError.raise("1518: The case you are matching to, " ++
              "{stripNewLines(block.toGrace(0))}, has more than one argument "++
              "on the left side. This is not currently supported.") with (matchee)
          }

          //If param is a general case(ie. n:Number), accumulate its type to
          //paramTypesList; ignore if it is a specific case(ie. 47)
          def blockParam : Parameter = block.params.at(1)
          match (blockParam.dtype)
            case{ s:share.StringLiteral →
              io.error.write"\n Got StringLiteral"
          } case{ n:share.NumberLiteral →
              io.error.write"\n Got NumberLiteral"
          } case{ t:true →
              io.error.write"\n Got BooleanLiteral"
          } case{ f:false →
              io.error.write"\n Got BooleanLiteral"
          } case{ _ →
              def typeOfParam = anObjectType.fromDType(blockParam.decType)

              if (paramTypesList.contains(typeOfParam).not) then {
                  paramTypesList.add(typeOfParam)
              }
          }

          //Return type collection
          def blockReturnType : ObjectType = objectTypeFromBlock(block)
          if (returnTypesList.contains(blockReturnType).not) then {
            returnTypesList.add(blockReturnType)
          }
        }

        //io.error.write("\n371: The paramTypesList contains {paramTypesList}\n")
        //io.error.write("\n370: The returnTypesList contains {returnTypesList}\n")

        paramType := ot.fromObjectTypeList(paramTypesList)
        returnType := ot.fromObjectTypeList(returnTypesList)

        io.error.write "\nparamType now equals: {paramType}"
        io.error.write "\nreturnType now equals: {returnType}"

        if (matcheeType.isSubtypeOf(paramType).not) then {
          outer.TypeError.raise("1519: the matchee `{stripNewLines(matchee.toGrace(0))}`"++
            " of type {matcheeType} does not " ++
            "match the type(s) {paramTypesList} of the case(s)") with (matchee)
        }

        cache.at(node) put (returnType)

        false
    }




    // not implemented yet
    method visitTryCatch (node: AstNode) → Boolean {
        io.error.write "\n1544: TryCatch visit not implemented yet\n"
        checkMatch (node)
    }

//    method visitMethodType (node) → Boolean {
//        io.error.write "\n1549: visiting method type {node} not implemented\n"
//
//        runRules (node)
//
//        node.parametersDo { param →
//            runRules (parameterFromNode(param))
//        }
//
//        return false
//    }

//    method visitType (node) → Boolean {
//        io.error.write "\n1561: visiting type {node} (not implemented)\n"
//        checkMatch (node)
////        io.error.write "432: done visiting type {node}"
//    }

    method visitMethod (meth: AstNode) → Boolean {
        io.error.write "\n1567: Visiting method {meth}\n"

        // ensure all parameters have known types and provide return type
        for (meth.signature) do {s: AstNode →
            for (s.params) do {p: AstNode →
                if ((p.kind == "identifier") && {p.wildcard.not} && {p.decType.value=="Unknown"}) then {
                    CheckerFailure.raise("no type given to declaration"
                        ++ " of parameter '{p.value}'") with (p)
                }
            }
        }
        if (meth.decType.value=="Unknown") then {
            CheckerFailure.raise ("no return type given to declaration"
                ++ " of method '{meth.value.value}'") with (meth.value)
        }

        // meth.value is Identifier Node
        def name: String = meth.value.value
        def mType: MethodType = aMethodType.fromNode(meth)
        def returnType: ObjectType = mType.returnType

        io.error.write "\n1585: Entering scope for {meth}\n"
        scope.enter {
            for(meth.signature) do { part: AstNode →
                for(part.params) do { param: AstNode →
                    scope.variables.at(param.value)
                        put(anObjectType.fromDType(param.dtype))
                }
            }

            collectTypes((meth.body))
            io.error.write "\n1595: collected types for {list(meth.body)}\n"

            for(meth.body) do { stmt: AstNode →
                checkTypes(stmt)

                // Write visitor to make sure return statements have right type
                stmt.accept(object {
                    inherit ast.baseVisitor

                    method visitReturn(ret) → Boolean is override {
                        check (ret.value) matches (returnType) inMethod (name)
                        // note sure why record returnType?
                        cache.at(ret) put (returnType)
                        return false
                    }

                    method visitMethod(node) → Boolean is override {
                        false
                    }
                })
            }

            if(meth.body.size == 0) then {
                if(anObjectType.doneType.isConsistentSubtypeOf(returnType).not) then {
                    MethodError.raise("the method '{name}' declares a " ++
                        "result of type '{returnType}', but has no body") with (meth)
                }
            } else {
                def lastNode: AstNode = meth.body.last
                if (share.Return.match(lastNode).not) then {
                    def lastType = typeOf(lastNode)
                    if(lastType.isConsistentSubtypeOf(returnType).not) then {
                        MethodError.raise("the method '{name}' declares a " ++
                            "result of type '{returnType}', but returns an " ++
                            "expression of type '{lastType}'") with (lastNode)
                    }
                }
                io.error.write ("\n2048 type of lastNode in method {meth.nameString}" ++
                                                    " is {lastNode.kind}")
                if (lastNode.kind == "object") then {
                    visitObject(lastNode)
                    def confidType: ObjectType = allCache.at(lastNode)
                    allCache.at(meth.nameString) put (confidType)
                    io.error.write "\n2053 confidType is {confidType} for {meth.nameString}"
                }
            }
        }

        // if method is just a member name then can record w/variables
        if (isMember(mType)) then {
            scope.variables.at(name) put(returnType)
        }

        // always record it as a method
        scope.methods.at(name) put(mType)

        cache.at(meth) put (anObjectType.doneType)
        false

    }

    method visitCall (req) → Boolean {
        def rec: AstNode = req.receiver

        io.error.write "\n1673: visitCall's call is: {rec.nameString}.{req.nameString}"
        //io.error.write "\nTypes scope at visitCall is : {scope.types}"\
        //io.error.write "\nVariable scope at visitCall is : {scope.variables}"

        var tempDef := scope.variables.find("$elf") butIfMissing{anObjectType.dynamic}
        //io.error.write "\nCache at visitCall is: {cache}"

        // receiver type
        def rType: ObjectType = if(rec.isIdentifier &&
            {(rec.nameString == "self") || (rec.nameString =="module()object")}) then {
            io.error.write "\n1675: looking for type of self"
            scope.variables.find("$elf") butIfMissing {
                Exception.raise "type of self missing" with(rec)
            }
        } else {
            io.error.write "\n2085 rec.kind = {rec.kind}"
            typeOf(rec)
        }
        //io.error.write "\n1680: type of receiver {rec} is {typeOf(rec)}"
        //io.error.write "\n1681: rType is {rType}"

        def callType: ObjectType = if (rType.isDynamic) then {
            io.error.write "rType: {rType} is dynamic}"
            anObjectType.dynamic
        } else {
            //Since we can't have a method or a type with the same name. A call
            //on a name can be searched in both method and type lists
            //Just have to assume that the programmer used nonconflicting names- Joe

            var name: String := req.nameString
            if (name.contains "$object(") then {
                req.parts.removeLast
                name := req.nameString
            }
            def completeCall : String = "{req.receiver.nameString}.{req.nameString}"
            io.error.write "\n2154: {completeCall}"
            io.error.write "\n2155: {req.nameString}"
            io.error.write "\nrequest on {name}"

            io.error.write "\n2000: rType.methods is: {rType.methods}"
            match(rType.getMethod(name))
              case { (ot.noSuchMethod) →
                io.error.write "\n2001: got to case noSuchMethod"
                io.error.write "\n2002: scope here is {scope.types}"
                scope.types.findAtTop(completeCall) butIfMissing {
                    //Joe - possibly come back and change error msg maybe
                    //less informative, but less confusing msg

                    outer.RequestError.raise("no such method or type'{name}' in " ++
                        "`{stripNewLines(rec.toGrace(0))}` of type\n" ++
                        "    '{rType}' \nin type \n  '{rType.methods}'")
                            with(req)
                }
            } case { meth : MethodType →
                io.error.write "\nchecking request {req} against {meth}"
                check(req) against(meth)
            }
        }
        io.error.write "\n1701: callType: {callType}"
        cache.at(req) put (callType)
        true  // request to continue on arguments
    }

    // returns false so don't recurse into object
    method visitObject (obj :AstNode) → Boolean {
        def pcType: PublicConfidential = scope.enter {
            processBody (list (obj.value), obj.superclass)
        }
        cache.at(obj) put (pcType.publicType)
        allCache.at(obj) put (pcType.inheritableType)
        io.error.write "\n1971: *** Visited object {obj}"
        io.error.write (pcType.asString)
        io.error.write "\n2153: Scope at end is: {scope.methods}"
        false
    }

    //Process dialects and import statements
    //TODO: handle dialects
    method visitModule (node: AstNode) → Boolean {  // added kim
        io.error.write "\n1698: visiting module {node}"

        def importNodes: List⟦AstNode⟧ = emptyList
        def bodyNodes: List⟦AstNode⟧ = list(node.value)

        //goes through the body of the module and processes imports
        for (bodyNodes) do{ nd : AstNode →
            match (nd)
              case {imp: share.Import →
                //visitimport processes the import and puts its type on
                //the variable scope and method scope
                visitImport(imp)
                importNodes.add(nd)
          //} case {dialect}
            } case {_:Object → }//do nothing
        }

        //removes import statements from the body of the module
        for(importNodes) do{nd : AstNode →
            bodyNodes.remove(nd)
        }

        def withoutImport : AstNode = ast.moduleNode.body(bodyNodes)
                                named (node.nameString) scope (node.scope)
        io.error.write "\n2186 Types scope before collecting types is {scope.types}"
        collectTypes (list (withoutImport.body))
        io.error.write "\n2186 Types scope after collecting types is {scope.types}"

        visitObject (withoutImport)
    }

    // array literals represent collections (should fix to be lineups)
    method visitArray (lineUpLiteral) → Boolean {
        io.error.write "\n1704: visiting array {lineUpLiteral}"
        cache.at (lineUpLiteral) put (anObjectType.collection)
        false
    }

    // members are treated like calls
    method visitMember (node: AstNode) → Boolean {
        visitCall (node)
    }

    method visitGeneric (node: AstNode) → Boolean {
        io.error.write "\n1715: visiting generic {node} (not implemented)"
        checkMatch (node)
    }

    // look up identifier type in scope
    method visitIdentifier (ident: AstNode) → Boolean {
        //io.error.write "\nvisitIdentifier scope.variables processing node
        //    {ident} is {scope.variables}"
        def idType: ObjectType = match(ident.value)
          case { "outer" →
            outerAt(scope.size)
        } case { _ →
            scope.variables.find(ident.value) butIfMissing { anObjectType.dynamic }
        }
        cache.at (ident) put (idType)
        true

    }

    method visitTypeDec(node: share.TypeDeclaration) → Boolean {
        io.error.write "visit type dec for {node}"
        cache.at(node) put (anObjectType.fromDType(node.value))
        io.error.write "\n656: type dec for node has in cache {cache.at(node)}"
        false
    }

    // Fix later
    method visitOctets (node: AstNode) → Boolean {
        io.error.write "\n1736: visiting Octets {node} (not implemented)"
        false
    }

    // type of string is String
    // Why do these return true?  Nothing to recurse on.
    method visitString (node: AstNode) → Boolean {
        cache.at (node) put (anObjectType.string)
        true
    }

    // type of number is Number
    method visitNum (node: AstNode) → Boolean {
        cache.at (node) put (anObjectType.number)
        true
    }

    // If the op is & or |, evaluate it
    // Otherwise treat it as a call
    method visitOp (node: AstNode) → Boolean {
        io.error.write"\n2283 type checking op"
        if(node.value == "&") then {
            cache.at(node) put (typeOf(node.left) & typeOf(node.right))
        } elseif {node.value == "|"} then {
            cache.at(node) put (typeOf(node.left) | typeOf(node.right))
        } else {
            visitCall(node)
        }
        false
    }

    method visitTypeLiteral(node: share.TypeLiteral) → Boolean {
        cache.at(node) put(anObjectType.fromDType(node))
        true
    }

    method visitBind (bind: AstNode) → Boolean {
        io.error.write "\n 1758: Visit Bind"
        def dest: AstNode = bind.dest

        match (dest) case { _ : share.Member →
            var nm: String := dest.nameString
            if (! nm.endsWith ":=(1)") then {
                nm := nm ++ ":=(1)"
            }
            // rec.memb
            def rec: AstNode = dest.in

            // Type of receiver
            def rType: ObjectType = if(share.Identifier.match(rec) && {rec.value == "self"}) then {
                scope.variables.find("$elf") butIfMissing {
                    Exception.raise "type of self missing" with(rec)
                }
            } else {
                typeOf(rec)
            }

            if (rType.isDynamic) then {
                anObjectType.dynamic
            } else {

                match(rType.getMethod(nm))
                  case { (ot.noSuchMethod) →
                    outer.RequestError.raise("no such method '{nm}' in " ++
                        "`{stripNewLines(rec.toGrace(0))}` of type '{rType}'") with (bind)
                } case { meth : MethodType →
                    def req = ast.callNode.new(dest,
                        list [ast.callWithPart.new(dest.value, list [bind.value])])
                    check(req) against(meth)
                }
            }

        } case { _ →
            def dType: ObjectType = typeOf(dest)

            def value: AstNode = bind.value
            def vType: ObjectType = typeOf(value)

            if(vType.isConsistentSubtypeOf(dType).not) then {
                DefError.raise("the expression `{stripNewLines(value.toGrace(0))}` of type " ++
                    "'{vType}' does not satisfy the type '{dType}' of " ++
                    "`{stripNewLines(dest.toGrace(0))}`") with (value)
            }
        }
        cache.at (bind) put (anObjectType.doneType)
        false
    }


    // handles both defs and var declarations
    method visitDefDec (defd: AstNode) → Boolean {
        if (defd.decType.value=="Unknown") then {
            var typ: String := "def"
            if (share.Var.match(defd)) then { typ := "var" }
            CheckerFailure.raise("no type given to declaration"
                ++ " of {typ} '{defd.name.value}'") with (defd.name)
        }
        var defType: ObjectType := anObjectType.fromDType(defd.dtype)
        io.error.write "\n1820: defType is {defType}"
        def value = defd.value

        if(value != false) then {
            def vType: ObjectType = typeOf(value)
            // infer type if definition w/out type
            if(defType.isDynamic && (defd.kind == "defdec")) then {
                defType := vType
            }
            if(vType.isConsistentSubtypeOf(defType).not) then {
                DefError.raise("the expression `{stripNewLines(value.toGrace(0))}` of type " ++
                    "'{vType}' does not have type {defd.kind} " ++
                    "annotation '{defType}'") with (value)
            }
        }

        def name: String = defd.nameString
        scope.variables.at(name) put(defType)
        if (defd.isReadable) then {
            scope.methods.at(name) put(aMethodType.member(name) ofType(defType))
        }
        if (defd.isWritable) then {
            def name' = name ++ ":=(1)"
            def param = aParam.withName(name) ofType(defType)
            def sig = list[ot.aMixPartWithName(name') parameters(list[param])]
            scope.methods.at(name')
                put(aMethodType.signature(sig) returnType(anObjectType.doneType))
        }
        cache.at (defd) put (anObjectType.doneType)
        false
    }

    // Handle variable declaration like definition
    method visitVarDec (node: AstNode) → Boolean {
        visitDefDec (node)
    }

    // Grab information from gct file
    //Move processImport back into visitImport
    method visitImport (imp: AstNode) → Boolean {
        io.error.write "\n1861: visiting import {imp}"
        // headers of sections of gct form keys
        // Associated values are lines beneath the header
        def gct: Dictionary⟦String, List⟦String⟧⟧ = xmodule.parseGCT(imp.path)
        def impName : String = imp.nameString
        io.error.write("\n1953 gct is {gct}")
        io.error.write("\n1954 keys are {gct.keys}\n")

        // Define a list of types that we have yet to resolve. All public types
        // are placed in this list at the start
        def unresolvedTypes: List⟦String⟧ = list[]
        if (gct.containsKey("types")) then {
            for(gct.at("types")) do { typ →
                unresolvedTypes.push(typ)
            }
        }

        // Collect the type definition associated with each type
        def typeDefs : Dictionary⟦String, List⟦String⟧⟧ = emptyDictionary
        gct.keys.do { key : String →
            //example key: 'methodtypes-of:MyType:'
            if (key.startsWith("methodtypes-of:")) then {
                //gets the name of the type
                def typeName: String = split(key, ":").at(2)

                typeDefs.at(typeName) put(gct.at(key))
            }
        }

        //Loops until all imported types are resolved and stored in the types scope
        while{unresolvedTypes.size > 0} do {
            //To resolve its given type, importHelper recursively resolves other
            //unresolved types that its given type's type definition depends on.
            importHelper(unresolvedTypes.at(1), impName, unresolvedTypes,
                                                                      typeDefs)
        }

        //retrieves the names of public methods from imported module
        def importMethods : Set⟦MethodType⟧ = emptySet

        def importedMethodTypes: List⟦String⟧ = gct.at("publicMethodTypes")
                                                          ifAbsent { emptyList }

        //construct the MethodType corressponding to each method name
        for (importedMethodTypes) do { methSig : String →
            //if the method name begins with a '$', then it is a method that
            //returns an object corresponding to a public module that was
            //imported by our own import. We have already constructed the type
            //that this '$nickname' method returns in the while-do above. Since
            //that type is the type of an import and is not from a type-dec,
            //we want to remove it from our types scope after we've used it to
            //construct this '$nickname' method.
            if (methSig.at(1) == "$") then{
                def name : String = methSig.substringFrom(2) to
                                                    (methSig.indexOf("→") - 2)
                def mixPart : MixPart = ot.aMixPartWithName(name)
                                                          parameters(emptyList)

                def retType : ObjectType =
                    scope.types.findAtTop("{impName}.{name}")
                        butIfMissing { Exception.raise
                            ("\nCannot find type " ++
                                "{impName}.{name}. It is not defined in the " ++
                                "{impName} GCT file. Likely a problem with " ++
                                "writing the GCT file.")}

                importMethods.add(aMethodType.signature(list[mixPart])
                                                          returnType (retType))

                //remove the type belonging to '$nickname' from the types scope
                scope.types.stack.at(1).removeKey("{impName}.{name}")
            } else {
                importMethods.add(aMethodType.fromGctLine(methSig, impName))
            }
        }

        // Create the ObjectType and MethodType of import
        def impOType: ObjectType = anObjectType.fromMethods(importMethods)
        def sig: List⟦MixPart⟧ = list[ot.aMixPartWithName(impName)
                                                  parameters (emptyList)]
        def impMType: MethodType = aMethodType.signature(sig) returnType (impOType)

        // Store import in scopes and cache
        scope.variables.at(impName) put(impOType)
        scope.methods.at(impName) put(impMType)
        cache.at(imp) put (impOType)
        io.error.write"\n2421: ObjectType of the import {impName} is: {impOType}"
        false
    }

    //Resolve the imported type,'typeName', and store it in the types scope
    //
    //Param typeName - name of the imported type to be resolved
    //      impName  - nickname of the imported file containing 'typeName'
    //      unresolvedTypes - list of unresolved types
    //      typeDefs - maps all imported types from 'impName' to their type
    //                 definitions
    method importHelper(typeName : String, impName : String,
                        unresolvedTypes : List⟦String⟧,
                        typeDefs : Dictionary⟦String, List⟦String⟧⟧) → Done {

        if (typeDefs.containsKey(typeName).not) then {
            Exception.raise ("\nCannot find type {typeName}. It is not " ++
                "defined in the {impName} GCT file. Likely a problem with " ++
                "writing the GCT file.")
        }
        io.error.write "\n 2413: looking for {typeName} defined as {typeDefs.at(typeName)}"

        //Holds the type literals that make up 'typeName'
        def typeLiterals: Dictionary⟦String,ObjectType⟧ = emptyDictionary

        //Holds all methods belonging to 'typeName'
        def typeMeths: Set⟦MethodType⟧ = emptySet

        def typeDef : List⟦String⟧ = typeDefs.at(typeName)

        //populates typeLiterals with all the type literals declared in the type
        while {(typeDef.size > 0) && {typeDef.at(1).startsWithDigit}} do {
            def methPrefix : String = split(typeDef.at(1), " ").at(1)

            if (typeLiterals.containsKey(methPrefix).not) then {
                typeLiterals.at(methPrefix)
                                        put (anObjectType.fromMethods(emptySet))
            }
            typeLiterals.at(methPrefix).methods.add(
                          aMethodType.fromGctLine(typeDef.removeFirst, impName))
        }

        //*******************************************************
        //At this point in the method, typeDef only contains the
        //lines that come after the type literal definitions
        //*******************************************************

        //This will hold the resulting ObjectType of the type being evaluated
        def myType : ObjectType = if (typeDef.size == 0) then {
            //type is defined by a type literal
            if (typeLiterals.size == 0) then {
                anObjectType.fromMethods(emptySet)
            } else {
                typeLiterals.values.first
            }
        } else {
            def fstLine : String = typeDef.at(1)
            if ((fstLine.at(1) == "&") || {fstLine.at(1) == "|"}) then {
                //type is defined by operations on other types
                importOpHelper(typeDef, typeLiterals, typeName, impName,
                                                      unresolvedTypes, typeDefs)
            } elseif {anObjectType.preludeTypes.contains(fstLine)} then {
                //type is defined by a prelude type
                scope.types.findAtTop("{fstLine}") butIfMissing{
                    Exception.raise ("\nCannot find type {fstLine}. "++
                        "Likely a problem with writing the GCT file.")
                }
            } else {
                //type is defined by an imported type
                if (unresolvedTypes.contains(fstLine)) then {
                    importHelper(fstLine, impName, unresolvedTypes, typeDefs)
                }
                scope.types.findAtTop("{impName}.{fstLine}") butIfMissing{
                    Exception.raise ("\nCannot find type {impName}.{fstLine}."++
                        " Likely a problem with writing the GCT file.")
                }
            }
        }

        io.error.write ("\nThe type {impName}.{typeName} was put in the scope as" ++
                                      " {impName}.{typeName}::{myType}")

        io.error.write "\n2483 trying to remove {typeName} from {unresolvedTypes}"
        unresolvedTypes.remove(typeName)
        scope.types.at("{impName}.{typeName}") put (myType)
    }

    //recursively parse pre-ordered type definitions from GCT file
    //
    //Param list - the list of strings from the GCT file that represents the pre-order
    //                traversal of the AstNode tree
    //Param typeLits - Holds all the pre-processed type literals from the type definition
    //                    mapped to digits as temporary type names
    //The other parameters are just so this method can recursively call importHelper
    method importOpHelper (typeDef : List⟦String⟧,
                typeLits : Dictionary⟦String,ObjectType⟧, typeName : String,
                impName : String, unresolvedTypes : List⟦String⟧,
                typeDefs : Dictionary⟦String, List⟦String⟧⟧) → ObjectType {

        io.error.write("\nCalled importOpHelper on {typeName} with the " ++
                                                          "typeDef of {list}")
        def elt : String = typeDef.removeFirst
        //elt is an op, and what comes after it is its left side and right side
        if (elt == "&") then {
            def leftSide  : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            def rightSide : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            leftSide & rightSide
        } elseif {elt == "|"} then {
            def leftSide  : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            def rightSide : ObjectType = importOpHelper(typeDef, typeLits, elt,
                                            impName, unresolvedTypes, typeDefs)
            leftSide | rightSide
        //elt refers to an already-processed type literal
        } elseif {elt.startsWithDigit} then {
            typeLits.at(elt)
        //elt is an identifier, which must be resolved then found in the scope
        } else {
            if (unresolvedTypes.contains(elt)) then {
                importHelper (elt, impName, unresolvedTypes, typeDefs)
            }
            io.error.write ("\n2470 scope before search in import is" ++
                                                            "{scope.types}")
            scope.types.findAtTop("{impName}.{elt}") butIfMissing {
                                  ScopingError.raise("Could not " ++
                                        "find type {elt} from import in scope")
            }
        }
    }

    method visitReturn (node: AstNode) → Boolean {
        cache.at(node) put (typeOf(node.value))
        false
    }

    method visitInherits (node: AstNode) → Boolean {
        io.error.write "\n1999: visit inherits with {node} which has kind {node.kind}"
        io.error.write "\n1999: visit inherits with {node} which has receiver {node.value.receiver}"
        io.error.write "\n1999: visit inherits with {node} which has parts {node.value.parts.removeLast}"
        cache.at(node) put (typeOf(node.value))
        io.error.write "\n2000 has type {typeOf(node.value)}"
        false
    }


    // Not done
    // Should be treated like import, but at top level
    // Add to base type
    method visitDialect (node: AstNode) → Boolean {
        io.error.write "\n1919: visiting dialect {node}"
        checkMatch (node)
    }

}


// DEBUG: Outer not handled correctly yet

method outerAt(i : Number) → ObjectType is confidential {
    // Required to cope with not knowing the prelude.
    if(i <= 1) then {
        return anObjectType.dynamic
    }
    io.error.write "processing outer"

    def vStack: List⟦Dictionary⟧ = scope.variables.stack

    def curr: ObjectType = vStack.at(i)

    //Joe-how does an ObjectType have an 'at' method
    return curr.at("outer") ifAbsent {
        def prev: ObjectType = outerAt(i - 1)

        def mStack: List⟦Dictionary⟧ = scope.methods

        def vars: Dictionary = vStack.at(i - 1)
        def meths: Set⟦MethodType⟧ = mStack.at(i - 1).values

        //Joe - maybe do outer.types
        def oType: ObjectType = anObjectType.fromMethods(meths)
        def mType: MethodType = aMethodType.member("outer") ofType(oType)

        curr.at("outer") put(oType)
        mStack.at(i).at("outer") put(mType)

        oType
    }
}


// Typing methods.
// Type check body of object definition
method processBody (body : List⟦AstNode⟧, superclass: AstNode | false)
                                                → ObjectType is confidential {
    io.error.write "\n1958: superclass: {superclass}\n"

    var inheritedMethods: Set⟦MethodType⟧ := emptySet
    def hasInherits = false ≠ superclass
//    io.error.write "\n1965: hasInherits is {hasInherits}\n"
    var publicSuperType: ObjectType := anObjectType.base
    def superType: ObjectType = if(hasInherits) then {
        def inheriting: AstNode = superclass
//        inheriting.accept(object {
//            inherit ast.baseVisitor

//            def illegal = ["self", "super"]

//            method visitIdentifier(ident) {
//                if(illegal.contains(ident.value)) then {
//                    ObjectError.raise("reference to '{ident.value}' " ++
//                        "in inheritance clause") with (ident)
//                }
//                true
//            }
//        })
        io.error.write "aliases: {superclass.aliases}"
        if (superclass.aliases.size > 0) then {
            io.error.write "first alias is {superclass.aliases.at(1).newName.kind}"
        }
        
        io.error.write "\nGT1981: checking types of inheriting = {inheriting}\n"
        var name: String := inheriting.value.nameString
        if (name.contains "$object(") then {
            inheriting.value.parts.removeLast
            name := inheriting.value.nameString
        }

        // Handle exclusions and aliases
        // Exclusions only for now
        // Unfortunately no type info with exclusions, so if code says
        // exclude p(s:String) and p in subclass takes a Number, it will
        // be dropped without any warning of the error.
        var inheritedType: ObjectType := allCache.at(name)
        inheritedMethods := inheritedType.methods.copy
        publicSuperType := typeOf(inheriting.value)
        var pubInheritedMethods := publicSuperType.methods.copy
        for (superclass.exclusions) do {ex →
            for (inheritedMethods) do {im →
//                io.error.write "\n1124 comparing {ex.nameString} and {im.nameString}"
                if (ex.nameString == im.nameString) then {
//                    io.error.write "\n1126 removing {im}"
                    inheritedMethods.remove(im)
                }
            }
            for (pubInheritedMethods) do {im →
//                io.error.write "\n1124 comparing {ex.nameString} and {im.nameString}"
//                io.error.write "\n1124 comparing {ex.dtype} and {im}"
                if (ex.nameString == im.nameString) then {
//                    io.error.write "\n1126 removing {im}"
                    pubInheritedMethods.remove(im)
                }
            }
        }
        inheritedType := anObjectType.fromMethods(inheritedMethods)
        publicSuperType := anObjectType.fromMethods(pubInheritedMethods)

        io.error.write "\1144: public super type: {publicSuperType}"
        io.error.write "\n1145: inherited type: {inheritedType}"

        inheritedType
    } else {
        anObjectType.base
    }
    io.error.write "\n1989: superType is {superType}\n"
    scope.variables.at("super") put(superType)

    // If the super type is dynamic, then we can't know anything about the
    // self type.  TODO We actually can, because an object cannot have two
    // methods with the same name.

    // Type including all confidential features
    var internalType: ObjectType

    // Type including only public features
    def publicType: ObjectType = if(superType.isDynamic) then {
        scope.variables.at("$elf") put(superType)
        superType
    } else {
        // Collect the method types to add the two self types.
        def isParam: Param = aParam.withName("other") ofType (anObjectType.base)
        def part: MixPart = ot.aMixPartWithName("isMe")parameters(list[isParam])

        // add isMe method as confidential
        def isMeMeth: MethodType = aMethodType.signature(list[part]) returnType(anObjectType.boolean)

        def publicMethods: Set⟦MethodType⟧ = publicSuperType.methods.copy
        def allMethods: Set⟦MethodType⟧ = superType.methods.copy
        allMethods.add(isMeMeth)

        // collect embedded types in these dictionaries
        def publicTypes: Dictionary⟦String,ObjectType⟧ = emptyDictionary
        def allTypes: Dictionary⟦String,ObjectType⟧ = emptyDictionary

        // gather types for all methods in object
        // TODO: Worry about overriding with refined signature
        for(body) do { stmt: AstNode →
            io.error.write "\n2009: processing {stmt}"
            match(stmt) case { meth : share.Method →
                def mType: MethodType = aMethodType.fromNode(meth)
                checkOverride(mType,allMethods,publicMethods)
                allMethods.add(mType)
                io.error.write "\n1158 Adding {mType} to allMethods"
                io.error.write "\n1159 AllMethods: {allMethods}"
                
                if(isPublic(meth)) then {
                    publicMethods.add(mType)
                }

                scope.methods.at(meth.nameString) put(mType)

                //A method that is a Member has no parameter and is identical to
                //a variable, so we also store it inside the variables scope
                if(isMember(mType)) then {
                    scope.variables.at(mType.name) put(mType.returnType)
                }

            } case { defd : share.Def | share.Var →
                def mType: MethodType = aMethodType.fromNode(defd)
                allMethods.add(mType)
                io.error.write "\n1177 AllMethods: {allMethods}"

                //create method to access def/var
                if(defd.isReadable) then {
                    publicMethods.add(mType)
                }

                //update scope with reference to def/var
                scope.methods.at(mType.name) put(mType)
                scope.variables.at(mType.name) put(mType.returnType)

                //constructs setter method for writable vars
                if(defd.isWritable) then {
                    def name': String = defd.nameString ++ ":=" //(1)"  ?? is name right?
                    def dType: ObjectType = anObjectType.fromDType(defd.dtype)
                    def param: Param = aParam.withName(defd.nameString) ofType(dType)
                    def sig: List⟦MixPart⟧ = list[ot.aMixPartWithName(name') parameters(list[param])]

                    def aType: MethodType = aMethodType.signature(sig) returnType(anObjectType.doneType)
                    scope.methods.at(name') put(aType)
                    allMethods.add(aType)
                    io.error.write "\n1197 AllMethods: {allMethods}"

                    publicMethods.add(aType)
                }

            } case { td : share.TypeDeclaration →
                //Now does nothing if given type declaration; might make this raise an error later
            } case { _ → io.error.write"\n2617 ignored {stmt}"}
        }
        io.error.write "\n1201 allMethods: {allMethods}"
        internalType := anObjectType.fromMethods(allMethods)
        scope.variables.at("$elf") put (internalType)
        io.error.write "\n1204: Internal type is {internalType}"
        anObjectType.fromMethods(publicMethods)
    }

    scope.variables.at("self") put(publicType)
    io.error.write "\n2744: Type of self is {publicType}"

    // Type-check the object body.
    def indices: Collection⟦Number⟧ = if(hasInherits) then {
        2..body.size
    } else {
        body.indices
    }

    for(indices) do { i: Number →
        io.error.write "\n2070: checking index {i} at line {body.at(i).line}"
        checkTypes(body.at(i))
        io.error.write "\n2072: finished index {i}\n"
    }

    io.error.write "\n 2674 types scope is: {scope.types}"
    io.error.write "\n 2675 methods scope is: {scope.methods}"
    pubConf(publicType,internalType)
}

method checkOverride(mType: MethodType, allMethods: Set⟦MethodType⟧,
                                        publicMethods: Set⟦MethodType⟧) → Done {
    def oldMethType: MethodType = allMethods.find{m:MethodType →
        mType.nameString == m.nameString
    } ifNone {return}
    io.error.write "\n1233 Found new method {mType} while old was {oldMethType}"
    if(mType.isSpecialisationOf(emptyList, oldMethType).ans.not) then {
        MethodError.raise ("Type of overriding method {mType} is not"
            ++ " a specialization of existing method {oldMethType}") with (mType)
    }
    allMethods.remove(oldMethType)
    if (publicMethods.contains(oldMethType)) then {
        publicMethods.remove(oldMethType)
    }
}



def TypeDeclarationError = TypeError.refine "TypeDeclarationError"

// The first pass over a body, collecting all type declarations so that they can
// reference one another declaratively.
method collectTypes(nodes : Collection⟦AstNode⟧) → Done is confidential {
    def names: List⟦String⟧ = list[]

    for(nodes) do { node →
        match(node) case { td : share.TypeDeclaration →
            io.error.write"\nmatched as typeDec"
            if(names.contains(td.nameString)) then {
                TypeDeclarationError.raise("the type {td.nameString} uses " ++
                    "the same name as another type in the same scope") with(td)
            }

            names.push(td.nameString)
            scope.types.at(td.nameString)
                                    put(anObjectType.definedByNode (td.value))
        } case { _ →
        }
    }
    // io.error.write "1881: done collecting types"
}


// Determines if a node is publicly available.
method isPublic(node : share.Method | share.Def | share.Var) → Boolean is confidential {
    match(node) case { _ : share.Method →
        for(node.annotations) do { ann →
            if(ann.value == "confidential") then {
                return false
            }
        }

        true
    } case { _ →
        for(node.annotations) do { ann →
            if((ann.value == "public") || (ann.value == "readable")) then {
                return true
            }
        }

        false
    }
}


// Determines if a method will be accessed as a member.
method isMember(mType : MethodType) → Boolean is confidential {
    (mType.signature.size == 1) && {
        mType.signature.first.parameters.size == 0
    }
}


// Helper methods.

// For loop with break.
method for(a) doWithBreak(bl) → Done {
    for(a) do { e →
        bl.apply(e, {
            return
        })
    }
}

// For loop with continue.
method for(a) doWithContinue(bl) → Done {
    for(a) do { e →
        continue'(e, bl)
    }
}

method continue'(e, bl) → Done is confidential {
    bl.apply(e, { return })
}


// Replace newline characters with spaces. This is a
// workaround for issue #116 on the gracelang/minigrace
// git repo. The result of certain astNodes.toGrace(0)
// is a string containing newlines, and error messages
// containing these strings get cut off at the first
// newline character, resulting in an unhelpful error
// message.
method stripNewLines(str) → String is confidential {
    str.replace("\n")with(" ")
}

//class parameterFromNode (node) → Parameter is confidential {
//    inherit ast.identifierNode.new (node.name, node.dtype)
//    method kind { "parameter" }
//}

def thisDialect is public = object {
    method astChecker (moduleObj) { moduleObj.accept(astVisitor) }
}