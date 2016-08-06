promise = require('./promise')
$u = require('./utilities')
_ = require('lodash')
module.exports = (expectedArgs...) ->
  invoked = false
  invocationCount = 0
  mock = (args...) ->
    throw new Error("No recorded expectations left when invoking #{$u.argsToString(args)}") if mock.expectations.length == 0
    if mock.expectations[0].args.length == 1 and _.isFunction(mock.expectations[0].args[0])
      mock.expectations[0].args[0].apply(null, args)
    else
      args.should.eql mock.expectations[0].args
    invoked = true
    invocationCount++
    returnValue = mock.expectations[0].result
    mock.expectations = mock.expectations[1..]
    returnValue
  mock._mock = true
  mock.expectations = [{args: expectedArgs, result: undefined}]
  mock.findExpectation = (args) ->
    for exp in mock.expectations
      return if(isEqual(exp, args))
  mock.andReturn = (result) ->
    mock.expectations[mock.expectations.length-1].result = result
    mock
  mock.andResolve = (result) ->
    mock.andReturn(promise.resolved(result))
  mock.isInvoked = -> invoked
  mock.hasExpectations = -> mock.expectations.length>0
  mock.expect = (expectedArgs...) ->
    mock.expectations.push {args:expectedArgs, result:undefined}
    mock
  mock

module.exports.validate = (mocks...) ->
  for mock in mocks
    if mock.constructor?
      objName = "#{mock.constructor.name}."
    for own name, func of mock
      if func._mock is true
        throw new Error("#{objName}#{name}(#{$u.argsToString(func.expectations[0].args)}) was never invoked") if func.hasExpectations()
