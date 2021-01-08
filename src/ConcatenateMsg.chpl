module ConcatenateMsg
{
    use ServerConfig;
    
    use Time only;
    use Math only;
    use Reflection;
    use Errors;
    
    use MultiTypeSymbolTable;
    use MultiTypeSymEntry;
    use ServerErrorStrings;
    use CommAggregation;
    use PrivateDist;
    
    use AryUtil;

    /* Concatenate a list of arrays together
       to form one array
     */
    proc concatenateMsg(cmd: string, payload: bytes, st: borrowed SymTab) throws {
        param pn = Reflection.getRoutineName();
        var repMsg: string;
        var (nstr, objtype, mode, rest) = payload.decode().splitMsgToTuple(4);
        var n = try! nstr:int; // number of arrays to sort
        var fields = rest.split();
        const low = fields.domain.low;
        var names = fields[low..];
        // Check that fields contains the stated number of arrays
        if (n != names.size) { 
            var errorMsg = incompatibleArgumentsError(pn, 
                             "Expected %i arrays but got %i".format(n, names.size)); 
            writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="IncompatibleArgumentsError"));                                 
            return errorMsg;
        }
        /* var arrays: [0..#n] borrowed GenSymEntry; */
        var size: int = 0;
        var blocksizes: [PrivateSpace] int;
        var blockValSizes: [PrivateSpace] int;
        var nbytes: int = 0;          
        var dtype: DType;
        // Check that all arrays exist in the symbol table and have the same size
        for (rawName, i) in zip(names, 1..) {
            // arrays[i] = st.lookup(name): borrowed GenSymEntry;
            var name: string;
            var valSize: int;
            select objtype {
                when "str" {
                    var valName: string;
                    (name, valName) = rawName.splitMsgToTuple('+', 2);
                    var gval = st.lookup(valName);
                    nbytes += gval.size;
                    valSize = gval.size;
                }
                when "pdarray" {
                    name = rawName;
                }
                otherwise { 
                    var errorMsg = notImplementedError(pn, objtype); 
                    writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));    
                    return errorMsg;                    
                }
            }
            var g: borrowed GenSymEntry = st.lookup(name);
            if (i == 1) {dtype = g.dtype;}
            else {
                if (dtype != g.dtype) {
                    var errorMsg = incompatibleArgumentsError(pn, 
                             "Expected %s dtype but got %s dtype".format(dtype2str(dtype), 
                                    dtype2str(g.dtype)));
                    writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="IncompatibleArgumentsError"));    
                    return errorMsg;
                }
            }
            // accumulate size from each array size
            size += g.size;
            if mode == "interleave" {
              const dummyDomain = makeDistDom(g.size);
              coforall loc in Locales {
                on loc {
                  blocksizes[here.id] += dummyDomain.localSubdomain().size;
                  if objtype == "str" {
                    const e = toSymEntry(g, int);
                    const firstSeg = e.a[e.aD.localSubdomain().low];
                    var mybytes: int;
                    if here.id == numLocales - 1 {
                      mybytes = valSize - firstSeg;
                    } else {
                      mybytes = e.a[e.aD.localSubdomain().high + 1] - firstSeg;
                    }
                    blockValSizes[here.id] += mybytes;
                  }
                }
              }
            }
        }
        var blockstarts: [PrivateSpace] int;
        var blockValStarts: [PrivateSpace] int;
        if mode == "interleave" {
          blockstarts = (+ scan blocksizes) - blocksizes;
          blockValStarts = (+ scan blockValSizes) - blockValSizes;
        }

        // allocate a new array in the symboltable
        // and copy in arrays
        select objtype {
            when "str" {
                var segName = st.nextName();
                var esegs = st.addEntry(segName, size, int);
                ref esa = esegs.a;
                var valName = st.nextName();
                var evals = st.addEntry(valName, nbytes, uint(8));
                ref eva = evals.a;
                var segStart = 0;
                var valStart = 0;
                for (rawName, i) in zip(names, 1..) {
                    var (segName, valName) = rawName.splitMsgToTuple('+', 2);
                    var thisSegs = toSymEntry(st.lookup(segName), int);
                    var newSegs = thisSegs.a + valStart;
                    var thisVals = toSymEntry(st.lookup(valName), uint(8));
                    if mode == "interleave" {
                      coforall loc in Locales {
                        on loc {
                          // Number of strings on this locale for this input array
                          const mynsegs = thisSegs.aD.localSubdomain().size;
                          ref mysegs = thisSegs.a.localSlice[thisSegs.aD.localSubdomain()];
                          // Segments must be rebased to start from blockValStart,
                          // which is the current pointer to this locale's chunk of
                          // the values array
                          esegs.a[blockstarts[here.id]..#mynsegs] = mysegs - mysegs[thisSegs.aD.localSubdomain().low] + blockValStarts[here.id];
                          blockstarts[here.id] += mynsegs;
                          const firstSeg = thisSegs.a[thisSegs.aD.localSubdomain().low];
                          var mybytes: int;
                          if here.id == numLocales - 1 {
                            mybytes = thisVals.size - firstSeg;
                          } else {
                            mybytes = thisSegs.a[thisSegs.aD.localSubdomain().high + 1] - firstSeg;
                          }
                          evals.a[blockValStarts[here.id]..#mybytes] = thisVals.a[firstSeg..#mybytes];
                          blockValStarts[here.id] += mybytes;
                        }
                      }
                    } else {
                      forall (i, s) in zip(newSegs.domain, newSegs) with (var agg = newDstAggregator(int)) {
                        agg.copy(esa[i+segStart], s);
                      }
                      forall (i, v) in zip(thisVals.aD, thisVals.a) with (var agg = newDstAggregator(uint(8))) {
                        agg.copy(eva[i+valStart], v);
                      }
                      segStart += thisSegs.size;
                      valStart += thisVals.size;
                    }
                }
                return "created " + st.attrib(segName) + "+created " + st.attrib(valName);
            }
            when "pdarray" {
                var rname = st.nextName();
                select (dtype) {
                    when DType.Int64 {
                        // create array to copy into
                        var e = st.addEntry(rname, size, int);
                        var start: int;
                        start = 0;
                        for (name, i) in zip(names, 1..) {
                            // lookup and cast operand to copy from
                            const o = toSymEntry(st.lookup(name), int);
                            if mode == "interleave" {
                              coforall loc in Locales {
                                on loc {
                                  const size = o.aD.localSubdomain().size;
                                  e.a[blockstarts[here.id]..#size] = o.a.localSlice[o.aD.localSubdomain()];
                                  blockstarts[here.id] += size;
                                }
                              }
                            } else {
                              ref ea = e.a;
                              // copy array into concatenation array
                              forall (i, v) in zip(o.aD, o.a) with (var agg = newDstAggregator(int)) {
                                agg.copy(ea[start+i], v);
                              }
                              // update new start for next array copy
                              start += o.size;
                            }
                        }
                    }
                    when DType.Float64 {
                        // create array to copy into
                        var e = st.addEntry(rname, size, real);
                        var start: int;
                        start = 0;
                        for (name, i) in zip(names, 1..) {
                            // lookup and cast operand to copy from
                            const o = toSymEntry(st.lookup(name), real);
                            if mode == "interleave" {
                              coforall loc in Locales {
                                on loc {
                                  const size = o.aD.localSubdomain().size;
                                  e.a[blockstarts[here.id]..#size] = o.a.localSlice[o.aD.localSubdomain()];
                                  blockstarts[here.id] += size;
                                }
                              }
                            } else {
                              ref ea = e.a;
                              // copy array into concatenation array
                              forall (i, v) in zip(o.aD, o.a) with (var agg = newDstAggregator(real)) {
                                agg.copy(ea[start+i], v);
                              }
                              // update new start for next array copy
                              start += o.size;
                            }
                        }
                    }
                    when DType.Bool {
                        // create array to copy into
                        var e = st.addEntry(rname, size, bool);
                        var start: int;
                        start = 0;
                        for (name, i) in zip(names, 1..) {
                            // lookup and cast operand to copy from
                            const o = toSymEntry(st.lookup(name), bool);
                            if mode == "interleave" {
                              coforall loc in Locales {
                                on loc {
                                  const size = o.aD.localSubdomain().size;
                                  e.a[blockstarts[here.id]..#size] = o.a.localSlice[o.aD.localSubdomain()];
                                  blockstarts[here.id] += size;
                                }
                              }
                            } else {
                              ref ea = e.a;
                              // copy array into concatenation array
                              forall (i, v) in zip(o.aD, o.a) with (var agg = newDstAggregator(bool)) {
                                agg.copy(ea[start+i], v);
                              }
                              // update new start for next array copy
                              start += o.size;
                            }
                        }
                    }
                    otherwise {
                        var errorMsg = notImplementedError("concatenate",dtype);
                        writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));   
                        return errorMsg;                         
                    }
                }

                return try! "created " + st.attrib(rname);
            }
            otherwise { 
                var errorMsg = notImplementedError(pn, objtype); 
                writeln(generateErrorContext(
                                     msg=errorMsg, 
                                     lineNumber=getLineNumber(), 
                                     moduleName=getModuleName(), 
                                     routineName=getRoutineName(), 
                                     errorClass="NotImplementedError"));    
                return errorMsg;
            }
        }
    }
    
}
