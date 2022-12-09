
module BinOp
{
  use ServerConfig;
  
  use MultiTypeSymbolTable;
  use MultiTypeSymEntry;
  use Logging;
  use Message;
  use BitOps;
  use BigInteger;

  private config const logLevel = ServerConfig.logLevel;
  const omLogger = new Logger(logLevel);

  /*
  Helper function to ensure that floor division cases are handled in accordance with numpy
  */
  inline proc floorDivisionHelper(numerator: ?t, denom: ?t2): real {
    if (numerator == 0 && denom == 0) || (isinf(numerator) && (denom != 0 || isinf(denom))){
      return NAN;
    }
    else if (numerator > 0 && denom == -INFINITY) || (numerator < 0 && denom == INFINITY){
      return -1:real;
    }
    else {
      return floor(numerator/denom);
    }
  }

  /*
  Generic function to execute a binary operation on pdarray entries 
  in the symbol table

  :arg l: symbol table entry of the LHS operand

  :arg r: symbol table entry of the RHS operand

  :arg e: symbol table entry to store result of operation

  :arg op: string representation of binary operation to execute
  :type op: string

  :arg rname: name of the `e` in the symbol table
  :type rname: string

  :arg pn: routine name of callsite function
  :type pn: string

  :arg st: SymTab to act on
  :type st: borrowed SymTab 

  :returns: (MsgTuple) 
  :throws: `UndefinedSymbolError(name)`
  */
  proc doBinOpvv(l, r, e, op: string, rname, pn, st) throws {
    if e.etype == bool {
      // Since we know that the result type is a boolean, we know
      // that it either (1) is an operation between bools or (2) uses
      // a boolean operator (<, <=, etc.)
      if l.etype == bool && r.etype == bool {
        select op {
          when "|" {
            e.a = l.a | r.a;
          }
          when "&" {
            e.a = l.a & r.a;
          }
          when "^" {
            e.a = l.a ^ r.a;
          }
          when "==" {
            e.a = l.a == r.a;
          }
          when "!=" {
            e.a = l.a != r.a;
          }
          when "<" {
            e.a = l.a:int < r.a:int;
          }
          when ">" {
            e.a = l.a:int > r.a:int;
          }
          when "<=" {
            e.a = l.a:int <= r.a:int;
          }
          when ">=" {
            e.a = l.a:int >= r.a:int;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      }
      // All types support the same binary operations when the resultant
      // type is bool and `l` and `r` are not both boolean, so this does
      // not need to be specialized for each case.
      else {
        if ((l.etype == real && r.etype == bool) || (l.etype == bool && r.etype == real)) {
          select op {
            when "<" {
              e.a = l.a:real < r.a:real;
            }
            when ">" {
              e.a = l.a:real > r.a:real;
            }
            when "<=" {
              e.a = l.a:real <= r.a:real;
            }
            when ">=" {
              e.a = l.a:real >= r.a:real;
            }
            when "==" {
              e.a = l.a:real == r.a:real;
            }
            when "!=" {
              e.a = l.a:real != r.a:real;
            }
            otherwise {
              var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
              return new MsgTuple(errorMsg, MsgType.ERROR);
            }
          }
        }
        else {
          select op {
            when "<" {
              e.a = l.a < r.a;
            }
            when ">" {
              e.a = l.a > r.a;
            }
            when "<=" {
              e.a = l.a <= r.a;
            }
            when ">=" {
              e.a = l.a >= r.a;
            }
            when "==" {
              e.a = l.a == r.a;
            }
            when "!=" {
              e.a = l.a != r.a;
            }
            otherwise {
              var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
              return new MsgTuple(errorMsg, MsgType.ERROR); 
            }
          }
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    // Since we know that both `l` and `r` are of type `int` and that
    // the resultant type is not bool (checked in first `if`), we know
    // what operations are supported based on the resultant type
    else if (l.etype == int && r.etype == int) ||
            (l.etype == uint && r.etype == uint)  {
      if e.etype == int || e.etype == uint {
        select op {
          when "+" {
            e.a = l.a + r.a;
          }
          when "-" {
            e.a = l.a - r.a;
          }
          when "*" {
            e.a = l.a * r.a;
          }
          when "//" { // floordiv
            ref ea = e.a;
            ref la = l.a;
            ref ra = r.a;
            [(ei,li,ri) in zip(ea,la,ra)] ei = if ri != 0 then li/ri else 0;
          }
          when "%" { // modulo
            ref ea = e.a;
            ref la = l.a;
            ref ra = r.a;
            [(ei,li,ri) in zip(ea,la,ra)] ei = if ri != 0 then li%ri else 0;
          }
          when "<<" {
            e.a = l.a << r.a;
          }                    
          when ">>" {
            e.a = l.a >> r.a;
          }
          when "<<<" {
            e.a = rotl(l.a, r.a);
          }
          when ">>>" {
            e.a = rotr(l.a, r.a);
          }
          when "&" {
            e.a = l.a & r.a;
          }                    
          when "|" {
            e.a = l.a | r.a;
          }                    
          when "^" {
            e.a = l.a ^ r.a;
          }
          when "**" { 
            if || reduce (r.a<0){
              //instead of error, could we paste the below code but of type float?
              var errorMsg = "Attempt to exponentiate base of type Int64 to negative exponent";
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);  
              return new MsgTuple(errorMsg, MsgType.ERROR);                                
            }
            e.a= l.a**r.a;
          }     
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
            return new MsgTuple(errorMsg, MsgType.ERROR); 
          }
        }
      } else if e.etype == real {
        select op {
          // True division is the only integer type that would result in a
          // resultant type of `real`
          when "/" {
            e.a = l.a:real / r.a:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
            return new MsgTuple(errorMsg, MsgType.ERROR); 
          }   
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    else if (e.etype == int && r.etype == uint) ||
            (e.etype == uint && r.etype == int) {
      select op {
        when ">>" {
          e.a = l.a >> r.a;
        }
        when "<<" {
          e.a = l.a << r.a;
        }
        when ">>>" {
          e.a = rotr(l.a, r.a);
        }
        when "<<<" {
          e.a = rotl(l.a, r.a);
        }
        otherwise {
          var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
          omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
          return new MsgTuple(errorMsg, MsgType.ERROR);
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if (l.etype == uint && r.etype == int) ||
              (l.etype == int && r.etype == uint) {
      select op {
        when "+" {
          e.a = l.a:real + r.a:real;
        }
        when "-" {
          e.a = l.a:real - r.a:real;
        }
        otherwise {
          var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
          omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
          return new MsgTuple(errorMsg, MsgType.ERROR); 
        }   
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    // If either RHS or LHS type is real, the same operations are supported and the
    // result will always be a `real`, so all 3 of these cases can be shared.
    else if ((l.etype == real && r.etype == real) || (l.etype == int && r.etype == real)
             || (l.etype == real && r.etype == int)) {
      select op {
          when "+" {
            e.a = l.a + r.a;
          }
          when "-" {
            e.a = l.a - r.a;
          }
          when "*" {
            e.a = l.a * r.a;
          }
          when "/" { // truediv
            e.a = l.a / r.a;
          } 
          when "//" { // floordiv
            ref ea = e.a;
            ref la = l.a;
            ref ra = r.a;
            [(ei,li,ri) in zip(ea,la,ra)] ei = floorDivisionHelper(li, ri);
          }
          when "**" { 
            e.a= l.a**r.a;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((l.etype == uint && r.etype == real) || (l.etype == real && r.etype == uint)) {
      select op {
          when "+" {
            e.a = l.a:real + r.a:real;
          }
          when "-" {
            e.a = l.a:real - r.a:real;
          }
          when "*" {
            e.a = l.a:real * r.a:real;
          }
          when "/" { // truediv
            e.a = l.a:real / r.a:real;
          } 
          when "//" { // floordiv
            ref ea = e.a;
            ref la = l.a;
            ref ra = r.a;
            [(ei,li,ri) in zip(ea,la,ra)] ei = floorDivisionHelper(li, ri);
          }
          when "**" { 
            e.a= l.a:real**r.a:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((l.etype == int && r.etype == bool) || (l.etype == bool && r.etype == int)) {
      select op {
          when "+" {
            // Since we don't know which of `l` or `r` is the int and which is the `bool`,
            // we can just cast both to int, which will be a noop for the vector that is
            // already `int`
            e.a = l.a:int + r.a:int;
          }
          when "-" {
            e.a = l.a:int - r.a:int;
          }
          when "*" {
            e.a = l.a:int * r.a:int;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((l.etype == real && r.etype == bool) || (l.etype == bool && r.etype == real)) {
      select op {
          when "+" {
            e.a = l.a:real + r.a:real;
          }
          when "-" {
            e.a = l.a:real - r.a:real;
          }
          when "*" {
            e.a = l.a:real * r.a:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    var errorMsg = notImplementedError(pn,l.dtype,op,r.dtype);
    omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
    return new MsgTuple(errorMsg, MsgType.ERROR);
  }

  proc doBinOpvs(l, val, e, op: string, dtype, rname, pn, st) throws {
    if e.etype == bool {
      // Since we know that the result type is a boolean, we know
      // that it either (1) is an operation between bools or (2) uses
      // a boolean operator (<, <=, etc.)
      if l.etype == bool && val.type == bool {
        select op {
          when "|" {
            e.a = l.a | val;
          }
          when "&" {
            e.a = l.a & val;
          }
          when "^" {
            e.a = l.a ^ val;
          }
          when "==" {
            e.a = l.a == val;
          }
          when "!=" {
            e.a = l.a != val;
          }
          when "<" {
            e.a = l.a:int < val:int;
          }
          when ">" {
            e.a = l.a:int > val:int;
          }
          when "<=" {
            e.a = l.a:int <= val:int;
          }
          when ">=" {
            e.a = l.a:int >= val:int;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      }
      // All types support the same binary operations when the resultant
      // type is bool and `l` and `r` are not both boolean, so this does
      // not need to be specialized for each case.
      else {
        if ((l.etype == real && val.type == bool) || (l.etype == bool && val.type == real)) {
          select op {
            when "<" {
              e.a = l.a:real < val:real;
            }
            when ">" {
              e.a = l.a:real > val:real;
            }
            when "<=" {
              e.a = l.a:real <= val:real;
            }
            when ">=" {
              e.a = l.a:real >= val:real;
            }
            when "==" {
              e.a = l.a:real == val:real;
            }
            when "!=" {
              e.a = l.a:real != val:real;
            }
            otherwise {
              var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
              return new MsgTuple(errorMsg, MsgType.ERROR);
            }
          }
        }
        else {
          select op {
            when "<" {
              e.a = l.a < val;
            }
            when ">" {
              e.a = l.a > val;
            }
            when "<=" {
              e.a = l.a <= val;
            }
            when ">=" {
              e.a = l.a >= val;
            }
            when "==" {
              e.a = l.a == val;
            }
            when "!=" {
              e.a = l.a != val;
            }
            otherwise {
              var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
              return new MsgTuple(errorMsg, MsgType.ERROR); 
            }
          }
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    // Since we know that both `l` and `r` are of type `int` and that
    // the resultant type is not bool (checked in first `if`), we know
    // what operations are supported based on the resultant type
    else if (l.etype == int && val.type == int) ||
            (l.etype == uint && val.type == uint) {
      if e.etype == int || e.etype == uint {
        select op {
          when "+" {
            e.a = l.a + val;
          }
          when "-" {
            e.a = l.a - val;
          }
          when "*" {
            e.a = l.a * val;
          }
          when "//" { // floordiv
            ref ea = e.a;
            ref la = l.a;
            [(ei,li) in zip(ea,la)] ei = if val != 0 then li/val else 0;
          }
          when "%" { // modulo
            ref ea = e.a;
            ref la = l.a;
            [(ei,li) in zip(ea,la)] ei = if val != 0 then li%val else 0;
          }
          when "<<" {
            e.a = l.a << val;
          }                    
          when ">>" {
            e.a = l.a >> val;
          }
          when "<<<" {
            e.a = rotl(l.a, val);
          }
          when ">>>" {
            e.a = rotr(l.a, val);
          }
          when "&" {
            e.a = l.a & val;
          }                    
          when "|" {
            e.a = l.a | val;
          }                    
          when "^" {
            e.a = l.a ^ val;
          }
          when "**" { 
            e.a= l.a**val;
          }     
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
            return new MsgTuple(errorMsg, MsgType.ERROR); 
          }
        }
      } else if e.etype == real {
        select op {
          // True division is the only integer type that would result in a
          // resultant type of `real`
          when "/" {
            e.a = l.a:real / val:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
            return new MsgTuple(errorMsg, MsgType.ERROR); 
          }
            
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    else if (e.etype == int && val.type == uint) ||
            (e.etype == uint && val.type == int) {
      select op {
        when ">>" {
          e.a = l.a >> val:l.etype;
        }
        when "<<" {
          e.a = l.a << val:l.etype;
        }
        when ">>>" {
          e.a = rotr(l.a, val:l.etype);
        }
        when "<<<" {
          e.a = rotl(l.a, val:l.etype);
        }
        when "+" {
          e.a = l.a + val:l.etype;
        }
        when "-" {
          e.a = l.a - val:l.etype;
        }
        otherwise {
          var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
          omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
          return new MsgTuple(errorMsg, MsgType.ERROR);
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    // If either RHS or LHS type is real, the same operations are supported and the
    // result will always be a `real`, so all 3 of these cases can be shared.
    else if ((l.etype == real && val.type == real) || (l.etype == int && val.type == real)
             || (l.etype == real && val.type == int)) {
      select op {
          when "+" {
            e.a = l.a + val;
          }
          when "-" {
            e.a = l.a - val;
          }
          when "*" {
            e.a = l.a * val;
          }
          when "/" { // truediv
            e.a = l.a / val;
          } 
          when "//" { // floordiv
            ref ea = e.a;
            ref la = l.a;
            [(ei,li) in zip(ea,la)] ei = floorDivisionHelper(li, val);
          }
          when "**" { 
            e.a= l.a**val;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((l.etype == uint && val.type == real) || (l.etype == real && val.type == uint)) {
      select op {
          when "+" {
            e.a = l.a: real + val: real;
          }
          when "-" {
            e.a = l.a: real - val: real;
          }
          when "*" {
            e.a = l.a: real * val: real;
          }
          when "/" { // truediv
            e.a = l.a: real / val: real;
          } 
          when "//" { // floordiv
            ref ea = e.a;
            ref la = l.a;
            [(ei,li) in zip(ea,la)] ei = floorDivisionHelper(li, val);
          }
          when "**" { 
            e.a= l.a: real**val: real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((l.etype == int && val.type == bool) || (l.etype == bool && val.type == int)) {
      select op {
          when "+" {
            // Since we don't know which of `l` or `r` is the int and which is the `bool`,
            // we can just cast both to int, which will be a noop for the vector that is
            // already `int`
            e.a = l.a:int + val:int;
          }
          when "-" {
            e.a = l.a:int - val:int;
          }
          when "*" {
            e.a = l.a:int * val:int;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((l.etype == real && val.type == bool) || (l.etype == bool && val.type == real)) {
      select op {
          when "+" {
            e.a = l.a:real + val:real;
          }
          when "-" {
            e.a = l.a:real - val:real;
          }
          when "*" {
            e.a = l.a:real * val:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,l.dtype,op,dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    var errorMsg = unrecognizedTypeError(pn, "("+dtype2str(l.dtype)+","+dtype2str(dtype)+")");
    omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
    return new MsgTuple(errorMsg, MsgType.ERROR);
  }

  proc doBinOpsv(val, r, e, op: string, dtype, rname, pn, st) throws {
    if e.etype == bool {
      // Since we know that the result type is a boolean, we know
      // that it either (1) is an operation between bools or (2) uses
      // a boolean operator (<, <=, etc.)
      if r.etype == bool && val.type == bool {
        select op {
          when "|" {
            e.a = val | r.a;
          }
          when "&" {
            e.a = val & r.a;
          }
          when "^" {
            e.a = val ^ r.a;
          }
          when "==" {
            e.a = val == r.a;
          }
          when "!=" {
            e.a = val != r.a;
          }
          when "<" {
            e.a = val:int < r.a:int;
          }
          when ">" {
            e.a = val:int > r.a:int;
          }
          when "<=" {
            e.a = val:int <= r.a:int;
          }
          when ">=" {
            e.a = val:int >= r.a:int;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      }
      // All types support the same binary operations when the resultant
      // type is bool and `l` and `r` are not both boolean, so this does
      // not need to be specialized for each case.
      else {
        if ((r.etype == real && val.type == bool) || (r.etype == bool && val.type == real)) {
          select op {
            when "<" {
              e.a = val:real < r.a:real;
            }
            when ">" {
              e.a = val:real > r.a:real;
            }
            when "<=" {
              e.a = val:real <= r.a:real;
            }
            when ">=" {
              e.a = val:real >= r.a:real;
            }
            when "==" {
              e.a = val:real == r.a:real;
            }
            when "!=" {
              e.a = val:real != r.a:real;
            }
            otherwise {
              var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
              return new MsgTuple(errorMsg, MsgType.ERROR);
            }
          }
        }
        else {
          select op {
            when "<" {
              e.a = val < r.a;
            }
            when ">" {
              e.a = val > r.a;
            }
            when "<=" {
              e.a = val <= r.a;
            }
            when ">=" {
              e.a = val >= r.a;
            }
            when "==" {
              e.a = val == r.a;
            }
            when "!=" {
              e.a = val != r.a;
            }
            otherwise {
              var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
              return new MsgTuple(errorMsg, MsgType.ERROR); 
            }
          }
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    // Since we know that both `l` and `r` are of type `int` and that
    // the resultant type is not bool (checked in first `if`), we know
    // what operations are supported based on the resultant type
    else if (r.etype == int && val.type == int) ||
            (r.etype == uint && val.type == uint) {
      if e.etype == int || e.etype == uint {
        select op {
          when "+" {
            e.a = val + r.a;
          }
          when "-" {
            e.a = val - r.a;
          }
          when "*" {
            e.a = val * r.a;
          }
          when "//" { // floordiv
            ref ea = e.a;
            ref ra = r.a;
            [(ei,ri) in zip(ea,ra)] ei = if ri != 0 then val/ri else 0;
          }
          when "%" { // modulo
            ref ea = e.a;
            ref ra = r.a;
            [(ei,ri) in zip(ea,ra)] ei = if ri != 0 then val%ri else 0;
          }
          when "<<" {
            e.a = val << r.a;
          }                    
          when ">>" {
            e.a = val >> r.a;
          }
          when "<<<" {
            e.a = rotl(val, r.a);
          }
          when ">>>" {
            e.a = rotr(val, r.a);
          }
          when "&" {
            e.a = val & r.a;
          }                    
          when "|" {
            e.a = val | r.a;
          }                    
          when "^" {
            e.a = val ^ r.a;
          }
          when "**" {
            if || reduce (r.a<0){
              var errorMsg = "Attempt to exponentiate base of type Int64 to negative exponent";
              omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
              return new MsgTuple(errorMsg, MsgType.ERROR); 
            }
            e.a= val**r.a;
          }     
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
            return new MsgTuple(errorMsg, MsgType.ERROR); 
          }
        }
      } else if e.etype == real {
        select op {
          // True division is the only integer type that would result in a
          // resultant type of `real`
          when "/" {
            e.a = val:real / r.a:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);                              
            return new MsgTuple(errorMsg, MsgType.ERROR); 
          }
            
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if (val.type == int && r.etype == uint) {
      select op {
        when ">>" {
          e.a = val:uint >> r.a:uint;
        }
        when "<<" {
          e.a = val:uint << r.a:uint;
        }
        when ">>>" {
          e.a = rotr(val:uint, r.a:uint);
        }
        when "<<<" {
          e.a = rotl(val:uint, r.a:uint);
        }
        when "+" {
          e.a = val:uint + r.a:uint;
        }
        when "-" {
          e.a = val:uint - r.a:uint;
        }
        otherwise {
          var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
          omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
          return new MsgTuple(errorMsg, MsgType.ERROR);
        }
      }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    // If either RHS or LHS type is real, the same operations are supported and the
    // result will always be a `real`, so all 3 of these cases can be shared.
    else if ((r.etype == real && val.type == real) || (r.etype == int && val.type == real)
             || (r.etype == real && val.type == int)) {
      select op {
          when "+" {
            e.a = val + r.a;
          }
          when "-" {
            e.a = val - r.a;
          }
          when "*" {
            e.a = val * r.a;
          }
          when "/" { // truediv
            e.a = val:real / r.a:real;
          } 
          when "//" { // floordiv
            ref ea = e.a;
            ref ra = r.a;
            [(ei,ri) in zip(ea,ra)] ei = floorDivisionHelper(val:real, ri);
          }
          when "**" { 
            e.a= val**r.a;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((r.etype == uint && val.type == real) || (r.etype == real && val.type == uint)) {
      select op {
          when "+" {
            e.a = val:real + r.a:real;
          }
          when "-" {
            e.a = val:real - r.a:real;
          }
          when "*" {
            e.a = val:real * r.a:real;
          }
          when "/" { // truediv
            e.a = val:real / r.a:real;
          } 
          when "//" { // floordiv
            ref ea = e.a;
            ref ra = r.a;
            [(ei,ri) in zip(ea,ra)] ei = floorDivisionHelper(val:real, ri);
          }
          when "**" { 
            e.a= val:real**r.a:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((r.etype == int && val.type == bool) || (r.etype == bool && val.type == int)) {
      select op {
          when "+" {
            // Since we don't know which of `l` or `r` is the int and which is the `bool`,
            // we can just cast both to int, which will be a noop for the vector that is
            // already `int`
            e.a = val:int + r.a:int;
          }
          when "-" {
            e.a = val:int - r.a:int;
          }
          when "*" {
            e.a = val:int * r.a:int;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    } else if ((r.etype == real && val.type == bool) || (r.etype == bool && val.type == real)) {
      select op {
          when "+" {
            e.a = val:real + r.a:real;
          }
          when "-" {
            e.a = val:real - r.a:real;
          }
          when "*" {
            e.a = val:real * r.a:real;
          }
          otherwise {
            var errorMsg = notImplementedError(pn,dtype,op,r.dtype);
            omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
            return new MsgTuple(errorMsg, MsgType.ERROR);
          }
        }
      var repMsg = "created %s".format(st.attrib(rname));
      return new MsgTuple(repMsg, MsgType.NORMAL);
    }
    var errorMsg = unrecognizedTypeError(pn, "("+dtype2str(dtype)+","+dtype2str(r.dtype)+")");
    omLogger.error(getModuleName(),getRoutineName(),getLineNumber(),errorMsg);
    return new MsgTuple(errorMsg, MsgType.ERROR);
  }

  proc doBigIntBinOpvv(l, r, op: string) throws {
    var max_bits = max(l.max_bits, r.max_bits);
    var modBy = 1:bigint;
    var has_max_bits = max_bits != -1;
    if has_max_bits {
      modBy <<= max_bits;
    }
    ref la = l.a;
    ref ra = r.a;
    var tmp = makeDistArray(la.size, bigint);
    // i think tmp should be initialized to 0 but just to be sure
    tmp = 0:bigint;

    // had to create bigint specific BinOp procs which return
    // the distributed array because we need it at SymEntry creation time
    if l.etype == bigint && r.etype == bigint {
      // first we try the ops that only work with
      // both being bigint
      select op {
        when "&" {
          tmp = la & ra;
        }
        when "|" {
          tmp = la | ra;
        }
        when "^" {
          tmp = la ^ ra;
        }
        when "/" {
          tmp = la / ra;
        }
      }
    }
    if l.etype == bigint && (r.etype == bigint || r.etype == int || r.etype == uint) {
      // then we try the ops that only work with a
      // left hand side of bigint
      if r.etype != bigint {
        // can't shift a bigint by a bigint
        select op {
          when "<<" {
            tmp = la << ra;
          }
          when ">>" {
            // workaround for right shift until chapel issue #21206
            // makes it into a release, eventually we can just do
            // tmp = la >> ra;
            var divideBy = makeDistArray(la.size, bigint);
            divideBy = 1:bigint;
            divideBy <<= ra;
            tmp = la / divideBy;
          }
          // when "<<<" {
          //   tmp = rotl(l.a, r.a);
          // }
          // when ">>>" {
          //   tmp = rotr(l.a, r.a);
          // }
        }
      }
      select op {
        when "//" { // floordiv
          [(ei,li,ri) in zip(tmp,la,ra)] ei = if ri != 0 then li/ri else 0:bigint;
        }
        when "%" { // modulo
          // we only do in place mod when ri != 0, tmp will be 0 in other locations
          // we can't use ei = li % ri because this can result in negatives
          [(ei,li,ri) in zip(tmp,la,ra)] if ri != 0 then ei.mod(li, ri);
        }
        when "**" {
          if || reduce (ra<0) {
            throw new Error("Attempt to exponentiate base of type BigInt to negative exponent");
          }
          if has_max_bits {
            [(ei,li,ri) in zip(tmp,la,ra)] ei.powMod(li, ri, modBy);
          }
          else {
            tmp = la ** ra;
          }
        }
      }
    }
    if (l.etype == bigint && r.etype == bigint) ||
       (l.etype == bigint && (r.etype == int || r.etype == uint || r.etype == bool)) ||
       (r.etype == bigint && (l.etype == int || l.etype == uint || l.etype == bool)) {
      select op {
        when "+" {
          tmp = la + ra;
        }
        when "-" {
          tmp = l.a - r.a;
        }
        when "*" {
          tmp = l.a * r.a;
        }
      }
    }
    // else {
    //   throw new Error("Unsupported operation: " + op);
    // }
    if has_max_bits {
      // modBy should always be non-zero since we start at 1 and left shift
      tmp.mod(tmp, modBy);
    }
    return tmp;
  }

  proc doBigIntBinOpvvBoolReturn(l, r, op: string) throws {
    select op {
      when "<" {
        return l.a < r.a;
      }
      when ">" {
        return l.a > r.a;
      }
      when "<=" {
        return l.a <= r.a;
      }
      when ">=" {
        return l.a >= r.a;
      }
      when "==" {
        return l.a == r.a;
      }
      when "!=" {
        return l.a != r.a;
      }
      otherwise {
        // we should never reach this since we only enter this proc
        // if boolOps.contains(op)
        throw new Error("Unsupported operation: " + op);
      }
    }
  }

  // proc doBigIntBinOpvs(l, val, op: string) throws {
  //   // had to create bigint specific BinOp procs which return
  //   // the distributed array because we need it at SymEntry creation time
  //   if l.etype == bigint && val.type == bigint {
  //     // first we try the ops that only work with
  //     // both being bigint
  //     select op {
  //       when "&" {
  //         return l.a & val;
  //       }
  //       when "|" {
  //         return l.a | val;
  //       }
  //       when "^" {
  //         return l.a ^ val;
  //       }
  //       when "/" {
  //         return l.a / val;
  //       }
  //     }
  //   }
  //   if l.etype == bigint && (r.etype == bigint || r.etype == int || r.etype == uint) {
  //     // then we try the ops that only work with a
  //     // left hand side of bigint
  //     if r.etype != bigint {
  //       // can't shift a bigint by a bigint
  //       select op {
  //         when "<<" {
  //           return l.a << val;
  //         }
  //         when ">>" {
  //           return l.a >> val;
  //         }
  //         // when "<<<" {
  //         //   return rotl(l.a, val);
  //         // }
  //         // when ">>>" {
  //         //   return rotr(l.a, val);
  //         // }
  //       }
  //     }
  //     select op {
  //       when "//" { // floordiv
  //         ref la = l.a;
  //         ref ra = val;
  //         var tmp = makeDistArray(la.size, bigint);
  //         [(ei,li,ri) in zip(tmp,la,ra)] ei = if ri != 0 then li/ri else 0:bigint;
  //         return tmp;
  //       }
  //       when "%" { // modulo
  //         ref la = l.a;
  //         ref ra = r.a;
  //         var tmp = makeDistArray(la.size, bigint);
  //         [(ei,li,ri) in zip(tmp,la,ra)] ei = if ri != 0 then li%ri else 0:bigint;
  //         return tmp;
  //       }
  //       when "**" {
  //         if || reduce (r.a<0) {
  //           throw new Error("Attempt to exponentiate base of type BigInt to negative exponent");
  //         }
  //         return l.a**r.a;
  //       }
  //     }
  //   }
  //   if (l.etype == bigint && r.etype == bigint) ||
  //      (l.etype == bigint && (r.etype == int || r.etype == uint || r.etype == bool)) ||
  //      (r.etype == bigint && (l.etype == int || l.etype == uint || l.etype == bool)) {
  //     select op {
  //       when "+" {
  //         return l.a + r.a;
  //       }
  //       when "-" {
  //         return l.a - r.a;
  //       }
  //       when "*" {
  //         return l.a * r.a;
  //       }
  //       otherwise {
  //         throw new Error("Unsupported operation: " + op);
  //       }
  //     }
  //   }
  //   else {
  //     throw new Error("Unsupported operation: " + op);
  //   }
  // }

  // proc doBigIntBinOpvsBoolReturn(l, val, op: string) throws {
  //   select op {
  //     when "<" {
  //       return l.a < r.a;
  //     }
  //     when ">" {
  //       return l.a > r.a;
  //     }
  //     when "<=" {
  //       return l.a <= r.a;
  //     }
  //     when ">=" {
  //       return l.a >= r.a;
  //     }
  //     when "==" {
  //       return l.a == r.a;
  //     }
  //     when "!=" {
  //       return l.a != r.a;
  //     }
  //     otherwise {
  //       // we should never reach this since we only enter this proc
  //       // if boolOps.contains(op)
  //       throw new Error("Unsupported operation: " + op);
  //     }
  //   }
  // }
}
