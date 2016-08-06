domain = require('domain')
events = require('events')
$p = require('./promise')
_ = require("lodash")

module.exports = (block) ->
  currentDomain = domain.create()
  currentDomain.__context__ = {}
  currentDomain.run ->
    try
      block()
    catch e
      setImmediate ->
        currentDomain.emit 'error', e
  currentDomain.on 'dispose', ->
    currentDomain.__context__ = undefined
  currentDomain

Object.defineProperty module.exports, "current",
    get: ->
      domain.active

Object.defineProperty module.exports, "active",
    get: ->
      domain.active?

Object.defineProperty module.exports, "context",
    get: ->
      domain.active?.__context__

Object.defineProperty module.exports, "run",
  enumerable: false
  value: (block) ->
    throw new Error("Block must be a function") unless _.isFunction(block)
    $p.create (p) ->
      result = null
      d = module.exports ->
        try
          result = block()
        catch e
          result = $p.failure(e)
      d.on 'error', (e...) ->
        d.exit()
        #console.log e, p.result
        p.error(e...) unless p.isResolved()
      if $p.isPromise(result)
        result.then
          success: (args...) ->
            d.exit()
            p.resolve(args...)
          error: (args...) ->
            d.exit()
            p.error(args...)
          failure: (args...) ->
            d.exit()
            p.failure(args...)
      else
        d.exit()
        p.failure(new Error("Block must return a promise"))

