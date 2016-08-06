promise = require('./promise')
{newObject} = require('./new_object')
Proxy = require('node-proxy')
{DefaultProxyHandler} = require('./default_proxy_handler')
$u = require('./utilities')
_ = require('lodash')

sharedCachedErrors = []
position = 0

ValidationError = (index, type, value, args...) -> newObject "ValidationError", $u.clean {
  index: (if _.isNumber(index) then index else null)
  field: (unless _.isNumber(index) then index else null)
  type: type
  value: value
  args: (args unless args.length == 0)
}

ValidationErrors = (errors, argNames) ->
  self = newObject "ValidationErrors", {
    errors: _.clone(errors)
    __prototype:
      _validationErrorCollection: true
      setNames: (names) -> _.each @errors, (e) -> e.name = names[e.index]
      failedIndexes: -> _.map(@errors, (e) -> e.index)
      toArray: -> _.clone(@errors)
      count: -> @errors.length
      hasErrors: -> @errors.length > 0
  }
  self.setNames(argNames) if argNames?
  self

module.exports = $v = (argNames) ->
  [cachedErrors, sharedCachedErrors, position] = [sharedCachedErrors, [], 0]
  return promise.error(ValidationErrors(cachedErrors, argNames)) if cachedErrors.length > 0
  throw new Error("No validation error detected, $v() should not have been called")

$v.required = (values...) ->
  _.each values, (v, i) ->
    sharedCachedErrors.push(ValidationError(position, "required", v)) unless v?
    position++
  $v

$v.ignore = (value) ->
  position++
  $v

$v.isValid = ->
  position = 0
  sharedCachedErrors.length == 0

$v.object = (object) ->
  sharedCachedErrors = []
  position = 0
  currentField = undefined
  optionalField = undefined
  proxy = null
  validators = {
    isPresent: ->
      validators.is("REQUIRED", (v) -> v?)
    isNotEmpty: ->
      validators.isPresent() and validators.is("NOT_EMPTY", (v) -> v!="")
    isString: ->
      validators.is("IS_STRING", (v) -> v? and _.isString(v))
    isNumeric: ->
      validators.is("IS_NUMERIC", (v) -> _.isNumber(v))
    matches: (error, regex) ->
      [error, regex] = ["INVALID", error] unless regex?
      throw new Error("Missing regex") unless regex?
      validators.is(error, (v) -> v? and v.match(regex)?)
    is: (error, validationFunction) ->
      return proxy if optionalField? and not (object[optionalField]? and object[optionalField]!='')
      [error, validationFunction] = ["INVALID", error] unless validationFunction?
      sharedCachedErrors.push(ValidationError(currentField, error, object[currentField])) unless validationFunction(object[currentField])
      proxy
    isOptional: (field) ->
      optionalField = field || currentField
      proxy
    isValid: ->
      $v.isValid()
  }
  handler = new DefaultProxyHandler(object)
  handler.get = (receiver, name) ->
    return null if name in ['constructor']
    return validators[name] if validators[name]?
    currentField = name
    optionalField = null
    proxy
  proxy = Proxy.create(handler)