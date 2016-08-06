if Object.prototype.toPromise?
  module.exports = require('core').promise
  return

util = require('util')
_ = require('lodash')
events = require('events')
$u = require('./utilities')
createDomain = require('domain').create
Proxy = require('node-proxy')
{DefaultProxyHandler} = require('./default_proxy_handler')

__globalProxyList = []
__pendingEmits = []
__globalEmitScheduled = false
__stackDelimiter = '  -----------'
exports.filterStackTrace = __stackTraceFilter = (stack) ->
  return unless stack?
  stack = stack.split('\n')
  stack = _.reject stack, (line) -> (line.match(/[ \t]+at[ ]+.*node_modules/)? or line.match(/^[ ]+at[^\/]*$/)) and !line.match('/node_modules\/core/')?
  stack = _.reject stack, (line) -> line.match(/[ \t]+at[ ]+.*(Promise|promise)/)? and !(line.match(/test/)? and !line.match(/node_modules/)?)
  stack = _.map stack, (line) -> line.replace(/Object\.defineProperty\.value\./,'')
  stack = _.reject stack, (line, index) -> stack[index+1]==line or line==''
  stack = _.reject stack, (line, index) -> (index>0 and line == __stackDelimiter and !stack[index-1].match(/[ \t]+at .*/)?)
  stack.pop() if stack[stack.length-1] == __stackDelimiter
  stack = stack.join('\n')+'\n'
  stacks = stack.split(__stackDelimiter)
  stacks = _.reject stacks, (item, index) -> stacks[index+1]==item
  stacks.join(__stackDelimiter)

__mergeStackTraces = (currentError, parentCallSite) ->
  return unless parentCallSite?
  mergeStackTraces = (stack) ->
    stack += parentCallSite.stack.replace(/.+\n/, __stackDelimiter+'\n')
    stack = stack.replace(/\n[ ]*--------------------[ ]*\n/, __stackDelimiter+'\n')
    stack = __stackTraceFilter(stack)
    if stack.length > 1024*16
      stack=stack.substring(0, 1024*16)+"\n  ..."
    stack
  origDescriptor = Object.getOwnPropertyDescriptor(currentError, 'stack')
  if origDescriptor.value?
    currentError.stack = mergeStackTraces(currentError.stack)
  else
    newDescriptor = _.defaults {
      get: -> mergeStackTraces(origDescriptor.get.apply(this))
    }, origDescriptor
    Object.defineProperty(currentError, 'stack', newDescriptor)

exports.Promise = class Promise extends events.EventEmitter
  bindOnce: (events) ->
    self = this
    listeners = {}
    clearListeners = ->
      for own event, listener of listeners
        self.removeListener(event, listener)
    for own event, cb of events
      do (event, cb) ->
        listeners[event] = (args...) ->
          clearListeners()
          cb.apply(this, args)
        self.once event, listeners[event]
    self

  scheduleEvent: (event, args...) ->
    return if @emitScheduled
    @resultType = event
    @resultResolved = true
    @result = args
    __pendingEmits.push =>
      @emitScheduled = false
      try
        @emit event, args...
        @_callSite = null
      catch e
        setImmediate => @emit 'error', e
    unless __globalEmitScheduled
      process.nextTick =>
        while __pendingEmits.length > 0
          __pendingEmits.shift()()
        __globalEmitScheduled = false
      __globalEmitScheduled = true
    @emitScheduled = true

  constructor: (_callSite) ->
    @resultResolved = false
    @_callSite = _callSite
    Error.captureStackTrace(@_callSite = {}, Promise) unless @_callSite?
    errorListener = (args...) =>
      if args[0] instanceof Error
        __mergeStackTraces(args[0], @_callSite)
        @_callSite = null
        throw args[0]
      throw new Error(util.format(args...))
    failureListener = (args...) =>
      if args[0] instanceof Error
        __mergeStackTraces(args[0], @_callSite)
        @_callSite = null
        throw args[0] if args.length == 1
      err = new Error(util.format(args...))
      err.failure = true
      throw err
    @on 'removeListener', ->
    @on 'error', errorListener
    @on 'failure', failureListener
    @on 'newListener', (event, listener) =>
      (@removeListener 'error', errorListener) if (event=='error' and listener!=errorListener)
      (@removeListener 'failure', failureListener) if (event=='failure' and listener!=failureListener)

  resolve: (values...) ->
    if values.length == 1 and exports.isPromise(values[0])
      values[0].then
        success: (args...) => @resolve(args...)
        error: (args...) => @error(args...)
        failure: (args...) => @failure(args...)
      return undefined
    if(@resultResolved)
      throw new Error("Invalid attempt to resolve a resolved promise")
    @scheduleEvent 'success', values...
    undefined

  isResolved: ->
    @resultResolved

  error: (args...) ->
    if args[0] instanceof Error and @_callSite?
      __mergeStackTraces(args[0], @_callSite)
    if(@resultResolved)
      throw new Error("Invalid attempt to resolve a resolved promise")
    @scheduleEvent 'error', args...

  failure: (args...) ->
    if args[0] instanceof Error
      args[0].failure = true
      __mergeStackTraces(args[0], @_callSite)

    if(@resultResolved)
      throw new Error("Invalid attempt to resolve a resolved promise")
    @scheduleEvent 'failure', args...

  resolveCallback: ->
    (args...) =>
      @resolve(args...)

  then: (theCb) ->
    wrapCallback = (cb) =>
      (args...) ->
        try
          cb.apply(this, args)
        catch e
          exports.failure(e)

    exports.create (p) =>
      callbacks =
        success: (results...) => p.resolve(results...)
        error: (err...) => p.error(err...)
        failure: (err...) => p.failure(err...)
      unless theCb?
        theCb = (args...) -> exports.resolved(args...)
      theCb = {success: theCb} if _.isFunction(theCb)
      _.each theCb, (f, k) ->
        callbacks[k] = $u.bindToActiveDomain((results...) => p.resolve(wrapCallback(f)(results...)))
      @bindOnce callbacks
      if @resultResolved is true then @scheduleEvent @resultType, @result...

  finally: (block) ->
    @then {
      success: (results...) -> exports.when(block('success', results...)).then -> exports.resolved(results...)
      error: (results...) -> exports.when(block('error', results...)).then -> exports.error(results...)
      failure: (results...) -> exports.when(block('failure', results...)).then -> exports.failure(results...)
    }

  proxy: (unproxyCb) ->
    self = this
    target = {
      then: (args...) -> self.then(args...)
      unproxy: (cb) ->
        self.then (values...) ->
          throw new Error("Unable to proxy a promise that resolves more than one value") if values.length > 1
          cb.apply(values[0])
    }
    target.unproxy(unproxyCb) if unproxyCb
    delegate = _.keys(target)
    handler = new DefaultProxyHandler(target)
    handler.get = (receiver, name) ->
      return this.target[name] if name in delegate
      (args...) ->
        self.then (values...) ->
          throw new Error("Unable to proxy a promise that resolves more than one value") if values.length > 1
          func = values[0]?[name]
          throw new Error("[#{name}] is not a member function") unless _.isFunction(func)
          func.apply(values[0], args)
    Proxy.create(handler)

  thenProxy: (theCb) ->
    theCb?= (proxy) -> proxy
    args = $u.parseArguments(theCb)
    promises = (exports.create() for arg in args)
    proxies = []
    _.each promises, (p) ->
      proxy = p.proxy()
      proxies.push proxy
      __globalProxyList.push p
      p.then(
        success: ->
        error: ->
        failure: ->
      ).then ->
        __globalProxyList = _.without(__globalProxyList, p)
    @then (results...) ->
      _.each promises, (p, i) ->
        p.resolve(results[i])
    theCb(proxies...)

  rescueIf: (code) ->
    @then
      error: (err, args...) ->
        return if err?.code == code
        promise.error(err, args...)

exports.then = (args...) -> exports.when(undefined).then(args...)

exports.waitForAllProxiesToResolve = ->
  __globalProxyList.then ->

exports.promise = exports.create = (_callSite, cb) ->
  [_callSite, cb] = [null, _callSite] if _.isFunction(_callSite)
  Error.captureStackTrace(_callSite = {}, exports.create) unless _callSite?
  p = new Promise(_callSite)
  try
    cb(p) if cb?
  catch e
    p.failure(e)
  p

#Deprecated, not sure how stable it is, better to handle domains outside of promises
exports.inDomain = (cb) ->
  domain = createDomain()
  resolved = false
  p = exports.create()
  domain.on 'error', (err) ->
    if p.isResolved() == true
      throw new Error("Unable to handle error [#{err?.message}], promise already resolved!")
    domain.exit()
    p.failure(err)
  domain.run ->
    exports.when(cb()).then
      success: (results...) -> domain.exit();p.resolve(results...)
      error: (err...) -> domain.exit();p.error(err...)
      failure: (err...) -> domain.exit();p.failure(err...)
  p

exports.when = (valueOrPromise) ->
  return valueOrPromise if exports.isPromise(valueOrPromise)
  exports.resolved(valueOrPromise)

exports.resolved=(values...) ->
  Error.captureStackTrace(_callSite = {}, exports.create)
  p = new Promise(_callSite)
  p.resolve(values...)
  p

exports.error = (err...) ->
  exports.create {stack: ""}, (p) ->
    p.error(err...)

exports.failure = (err...) ->
  exports.create (p) ->
    p.failure(err...)

exports.timeout = (timeout) ->
  exports.create (p) ->
    setTimeout (-> p.resolve()), timeout

exports.isPromise = (o) -> o instanceof Promise

exports.promise.merge = exports.merge=(promises...) ->
  if(!promises? or promises.length==0)
    return exports.resolved()
  mergedPromise = exports.create()
  results = []
  firstError = null
  firstFailure = null
  resolved = 0
  finish = ->
    resolved++
    if(resolved == promises.length)
      return mergedPromise.failure(firstFailure...) if firstFailure?
      return mergedPromise.error(firstError...) if firstError?
      mergedPromise.resolve(results...)

  for index in [0..promises.length-1]
    curPromise = promises[index]
    do (curPromise, index) ->
      if(util.isArray(curPromise))
        curPromise = if(curPromise.length==1) then curPromise[0] else exports.merge(curPromise...)
      curPromise.then
        success: (values...) ->
          results[index] = if values.length==1 then values[0] else values
          finish()
        error: (errors...) ->
          for err in errors
            err.fromIndex = index if err? and err instanceof Error
          firstError = errors unless firstError?
          finish()
        failure: (errors...) ->
          for err in errors
            err.fromIndex = index if err? and err instanceof Error
          firstFailure = errors unless firstFailure?
          finish()

  mergedPromise

wrappingCallBackStack = []
exports.ecb = ->
  p = exports.create()
  wrappingCallBackStack.push p
  cb = (err, results...) ->
    return p.error(err, results...) if err?
    p.resolve(results...)
    return
  cb

exports.cb = ->
  p = exports.create()
  wrappingCallBackStack.push p
  cb = (results...) ->
    p.resolve(results...)
    return
  cb

exports.wrap = ->
  return wrappingCallBackStack.pop()

exports.wrapAll = (target, functions) ->
  proxy = {}
  _.each functions, (f) ->
    proxy[f] = (args...) ->
      exports.wrap(target[f].call(target, args..., exports.ecb()))
  proxy

Object.defineProperty Array.prototype, 'merge',
  enumerable: false
  value: (preserveArray) ->
    result = exports.merge(_.filter(this, (e) -> e?)...)
    if preserveArray||false
      result.then (args...) -> args
    else
      result

Object.defineProperty Array.prototype, 'then',
  enumerable: false
  value: (args...) ->
    (_.map this, (e) ->
      return exports.resolved(e) unless e?
      return exports.resolved(e) if _.isFunction(e)
      return exports.resolved(e) unless exports.isPromise(e)
      e
    ).merge().then(args...)

Object.defineProperty Array.prototype, 'syncExecute',
  enumerable: false
  value: (scope, cb) ->
    [scope, cb] = [undefined, scope] unless cb?
    exports.callOrPromise cb, (p) =>
      final = []
      exec = (i) =>
        if (i>=this.length)
          p.resolve(final...)
        else
          (if _.isFunction(this[i])
            this[i].call(scope, final.slice(0)...)
          else if exports.isPromise(this[i])
            this[i]
          else
            exports.resolved(this[i])
          ).whenReady (results...) ->
            final = final.concat(results)
            process.nextTick -> exec(i+1)
      process.nextTick -> exec(0)

Object.defineProperty Object.prototype, 'toPromise',
  enumerable: false
  value: (cb) ->
    exports.create (p) =>
      promises = _.filter(_.map(this, (v, k) ->
        return unless exports.isPromise(v)
        v.keyName = k
        v
      ), (v) -> v?)
      promises.then
        success: =>
          for promise in promises
            this[promise.keyName]=if promise.result.length == 1 then promise.result[0] else promise.result
          p.resolve(this)
        error: (err...) => p.error(err...)
        failure: (err...) => p.failure(err...)

exports.reject= (err) ->
  exports.create (p) -> p.error(err)

ShouldPromise = undefined

createShouldPromiseClass = ->
  ShouldPromise = class ShouldPromise
    constructor: (@result, @_not) ->
      @_not=false unless @_not == true

  Object.defineProperty ShouldPromise.prototype, 'not',
    enumerable: false
    get: ->
      return new ShouldPromise(@result, !@_not)

  should = require('should')
  staticChecks = ['exist']
  for k in ["eql", "equal", "not", "be", "exist"]
    do (k) ->
      unless (k.match(/Assert/) or ShouldPromise.prototype[k]?)
        Object.defineProperty ShouldPromise.prototype, k,
          enumerable: false
          value: (args...) ->
            self = this
            compareResults = (result) ->
              result = result[0] if result.length < 2
              if result?
                if k in staticChecks
                  sh = should
                  sh = sh.not if self._not == true
                  sh[k](result, args...)
                else
                  sh = result.should
                  sh = sh.not if self._not == true
                  sh[k](args...)
              else
                throw new Error("Null values can only be checked for existance") unless k in ["not", "exist"]
                sh = should
                sh = sh.not if self._not == true
                sh[k](result, args...)
            this.result.then
              success: (result...) -> compareResults(result)
              error: (err...) -> compareResults(error: err)


Object.defineProperty Promise.prototype, 'should',
  enumerable: false
  get: () ->
    createShouldPromiseClass() unless ShouldPromise?
    new ShouldPromise(this)
