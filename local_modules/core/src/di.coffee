_ = require('lodash')
{newObject} = require('./new_object')
{validate} = require('./expect')
{DefaultProxyHandler} = require('./default_proxy_handler')
{parseArguments} = require('./utilities')
Proxy = require('node-proxy')
promise = require('./promise')
$u = require('./utilities')

exports.classToInstanceName = (className) -> $u.toVariableName(className)

exports.context = Context = (injectSuper = true) ->
  internalContext =
    config: {}
    registered: {}
    singletons: {}
    instantiating: {}
    promised: {}
    stubs: {}
    parent: undefined

    reset: ->
      @config={}
      @registered={}
      @singletons={}
      @instantiating={}
      @promised={}
      @stubs={}
      @parent=undefined

    setParent: (parent) ->
      @parent=parent

    configure: (configFilesOrObjects...) ->
      @config = _.merge {}, @config, configFilesOrObjects...

    register: (name, func) ->
      @registered[name] = func

    registerConstant: (name, constant) ->
      @registered[name] = -> constant

    registerAll: (constructors) ->
      for own name, ctr of constructors
        @register(exports.classToInstanceName(name), ctr)

    isDefined: (name) ->
      @singletons[name]? or @registered[name]? or @instantiating[name]? or @promised[name]? or (@parent? and @parent.isDefined(name))

    lookup: (name) ->
      if name is '$invoke'
        return (func) => @invoke func
      return @singletons[name] if @singletons[name]?
      unless @registered[name]?
        throw new Error("Unknown Object [#{name}]") unless @parent?
        return @parent.lookup(name)
      try
        return @promised[name] if @promised[name]?
        if @instantiating[name] is true
          @stubs[name] = {} unless @stubs[name]?
          return @stubs[name]
        @instantiating[name] = true
        instance = @instantiate(name, @registered[name])
        delete @instantiating[name]
        registerSingelton = (instance) =>
          if @stubs[name]?
            @stubs[name].__proto__ = instance
            delete @stubs[name]
          @singletons[name] = instance
        return registerSingelton(instance) unless promise.isPromise(instance)
        @promised[name]=instance
        instance.then (result) =>
          delete @promised[name]
          registerSingelton(result)
      catch e
        throw new Error("Error [#{e.message}] while instantiating [#{name}]")

    invoke: (that, func) ->
      [that, func] = [undefined, that] unless func?
      async = false
      params = for dep in parseArguments(func)
       depInstance = @lookup(dep)
       async = true if promise.isPromise(depInstance)
       depInstance
      return func.apply(that, params) unless async
      params.then (args...) ->
        func.apply(that, args)

    instantiate: (name, func) ->
      return func unless _.isFunction(func)
      getParam = (paramName) =>
        opts = @config?[name] || @parent?.config?[name]
        return opts if paramName == '$options'
        return opts?[paramName] if opts?[paramName]?
        return @lookup(paramName) if @isDefined(paramName)
        if paramName.match(/$.*/)
          factoryName = "#{paramName[1..paramName.length]}Factory"
          if @isDefined(factoryName)
            return promise.when(@lookup(factoryName)).then (factory) -> factory(name, opts)
        throw new Error("Unknown Parameter [#{paramName}]")
      getParams= (f) =>
        deps = parseArguments(f)
        (getParam(dep) for dep in deps)

      wrapFunction= (f) ->
        wrap = (args...) ->
          f.call(this,getParams(f)...)
        if f.__super__?.constructor?
          wrap.__super__ = f.__super__
        wrap.orig = f
        wrap
      unwrapFunction= (wrap) -> wrap.orig
      wrapConstructors= (c) ->
        while(c.__super__?.constructor?)
          c.__super__.constructor = wrapFunction(c.__super__.constructor)
          c = c.__super__.constructor
      unwrapConstructors= (c) ->
        while(c?.__super__?.constructor?)
          c.__super__.constructor = unwrapFunction(c.__super__.constructor)
          c = c.__super__.constructor

      params = getParams(func)
      hasPromises = false
      (hasPromises = true if promise.isPromise(value)) for value in params

      invokeInternal = (params) =>
        if func.name? and func.name != ""
          wrapConstructors func if injectSuper is true
          instance = new func(params...)
          unwrapConstructors func if injectSuper is true
          return instance
        newObject.setNextClassName name
        obj = func.apply(actualContext, params)
        newObject.setNextClassName null
        return obj

      return invokeInternal(params) unless hasPromises
      promisedParams = _.map(params,(param) -> if promise.isPromise(param) then param else promise.resolved(param)).merge()
      promisedParams.then (params...) ->
        invokeInternal(params)

  handler = new DefaultProxyHandler(internalContext)
  handler.get = (receiver, name) ->
    return internalContext[name] if internalContext[name]?
    return internalContext.lookup(name) if internalContext.isDefined(name)
  actualContext = Proxy.create(handler)

exports.TestContext = ->
  context = exports.context(false)
  context.mocks = []
  context.registerMock = (name) ->
    context.register(name, -> newObject())
    context.mocks.push context.lookup(name)
  context

exports.TestContext.it = (contextRef) ->
  (desc, block) ->
    return global.it(desc) unless block?
    global.it desc, (done) ->
      context = contextRef()
      r = block.call(this)
      unless promise.isPromise(r)
        done()
        return r
      r.then ->
        validate(context.mocks...)
        done()

exports.describe = (desc, block) ->
  ctx = exports.TestContext()
  it = exports.TestContext.it(-> ctx)

  describe desc, ->
    beforeEach ->
      ctx.reset()
      ctx.mocks = []
      ctx.register '$p', promise
      ctx.register '$u', $u
      ctx.register '$logger', {
        debug: ->
        info: ->
        error: (err) -> throw new Error(err)
        time: (level, message, block) -> block()
      }
    block(ctx, it)

exports.describeGlobal = (desc, block) ->
  ctx = exports.TestContext()
  it = exports.TestContext.it(-> ctx)

  describe desc, ->
    before ->
      ctx.reset()
      ctx.mocks = []
      ctx.register '$p', promise
      ctx.register '$u', $u
      ctx.register '$logger', {
        debug: ->
        info: ->
        error: (err) -> throw new Error(err)
        time: (level, message, block) -> block()
      }
    block(ctx, it)
