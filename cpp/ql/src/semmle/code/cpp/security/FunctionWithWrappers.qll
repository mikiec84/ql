import cpp
import PrintfLike
private import TaintTracking

bindingset[index]
private string toCause(Function func, int index) {
  result = func.getQualifiedName() + "(" + func.getParameter(index).getName() + ")"
  or
  not exists(func.getParameter(index).getName()) and
  result = func.getQualifiedName() + "(arg " + index + ")"
}

/**
 * Whether the parameter at index 'sourceParamIndex' of function 'source' is passed
 * (without any evident changes) to the parameter at index 'targetParamIndex' of function 'target'.
 */
private predicate wrapperFunctionStep(
  Function source, int sourceParamIndex, Function target, int targetParamIndex
) {
  not target.isVirtual() and
  not source.isVirtual() and
  source.isDefined() and
  exists(Call call, Expr arg, Parameter sourceParam |
    // there is a 'call' to 'target' with argument 'arg' at index 'targetParamIndex'
    target = resolveCall(call) and
    arg = call.getArgument(targetParamIndex) and
    // 'call' is enclosed in 'source'
    source = call.getEnclosingFunction() and
    // 'arg' is an access to the parameter at index 'sourceParamIndex' of function 'source'
    sourceParam = source.getParameter(sourceParamIndex) and
    not exists(sourceParam.getAnAssignedValue()) and
    arg = sourceParam.getAnAccess()
  )
}

/**
 * An abstract class for representing functions that may have wrapper functions.
 * Wrapper functions propagate an argument (without any evident changes) to this function
 * through one or more steps in a call chain.
 *
 * The design motivation is to report a violation at the location of the argument
 * in a call to the wrapper function rather than the function being wrapped, since
 * that is usually the more appropriate place to fix the violation.
 *
 * Subclasses should override the characteristic predicate and 'interestingArg'.
 */
abstract class FunctionWithWrappers extends Function {
  /**
   * Which argument indices are relevant for wrapper function detection.
   */
  predicate interestingArg(int arg) { none() }

  /**
   * Whether 'func' is a (possibly nested) wrapper function that feeds a parameter at the given index
   * through to an interesting parameter of 'this' function at the given call chain 'depth'.
   * The call chain depth is limited to 4.
   */
  private predicate wrapperFunctionLimitedDepth(
    Function func, int paramIndex, string callChain, int depth
  ) {
    // base case
    func = this and
    interestingArg(paramIndex) and
    callChain = toCause(func, paramIndex) and
    depth = 0
    or
    // recursive step
    exists(Function target, int targetParamIndex, string targetCause, int targetDepth |
      this.wrapperFunctionLimitedDepth(target, targetParamIndex, targetCause, targetDepth) and
      targetDepth < 4 and
      wrapperFunctionStep(func, paramIndex, target, targetParamIndex) and
      callChain = toCause(func, paramIndex) + ", which calls " + targetCause and
      depth = targetDepth + 1
    )
  }

  /**
   * Whether 'func' is a (possibly nested) wrapper function that feeds a parameter at the given index
   * through to an interesting parameter of 'this' function.
   *
   * The 'cause' gives the name of 'this' interesting function and its relevant parameter
   * at the end of the call chain.
   */
  private predicate wrapperFunctionAnyDepth(Function func, int paramIndex, string cause) {
    // base case
    func = this and
    interestingArg(paramIndex) and
    cause = toCause(func, paramIndex)
    or
    // recursive step
    exists(Function target, int targetParamIndex |
      this.wrapperFunctionAnyDepth(target, targetParamIndex, cause) and
      wrapperFunctionStep(func, paramIndex, target, targetParamIndex)
    )
  }

  /**
   * Whether 'func' is a (possibly nested) wrapper function that feeds a parameter at the given index
   * through to an interesting parameter of 'this' function.
   *
   * If there exists a call chain with depth at most 4, the 'cause' reports the smallest call chain.
   * Otherwise, the 'cause' merely reports the name of 'this' interesting function and its relevant
   * parameter at the end of the call chain.
   *
   * If there is more than one possible 'cause', a unique one is picked (by lexicographic order).
   */
  predicate wrapperFunction(Function func, int paramIndex, string cause) {
    cause =
      min(string callChain, int depth |
        this.wrapperFunctionLimitedDepth(func, paramIndex, callChain, depth) and
        depth = min(int d | this.wrapperFunctionLimitedDepth(func, paramIndex, _, d) | d)
      |
        callChain
      )
    or
    not this.wrapperFunctionLimitedDepth(func, paramIndex, _, _) and
    cause =
      min(string targetCause, string possibleCause |
        this.wrapperFunctionAnyDepth(func, paramIndex, targetCause) and
        possibleCause = toCause(func, paramIndex) + ", which ends up calling " + targetCause
      |
        possibleCause
      )
  }

  /**
   * Whether 'arg' is an argument in a call to an outermost wrapper function of 'this' function.
   */
  predicate outermostWrapperFunctionCall(Expr arg, string callChain) {
    exists(Function targetFunc, Call call, int argIndex |
      targetFunc = resolveCall(call) and
      this.wrapperFunction(targetFunc, argIndex, callChain) and
      (
        exists(Function sourceFunc | sourceFunc = call.getEnclosingFunction() |
          not wrapperFunctionStep(sourceFunc, _, targetFunc, argIndex)
        )
        or
        not exists(call.getEnclosingFunction())
      ) and
      arg = call.getArgument(argIndex)
    )
  }
}

class PrintfLikeFunction extends FunctionWithWrappers {
  PrintfLikeFunction() { printfLikeFunction(this, _) }

  override predicate interestingArg(int arg) { printfLikeFunction(this, arg) }
}
