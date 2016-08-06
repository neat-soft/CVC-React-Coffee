module.exports = (configPath, opts, initCb) ->
  require('coffee-script')
  _ = require('lodash')
  qs = require('querystring')
  domain = require('domain')
  moment = require('moment')
  {$p, $v, throttle, di, $u, scope, config, assetPipeline} = require('core')

  [opts, initCb] = [null, initCb] if _.isFunction(opts)
  context = di.context()
  context.configure config.parseConfig('./')...

  unless process.env.NODE_ENV?
    process.env.NODE_ENV = context.config.nodeEnv || "production"

  context.registerConstant '$context', context
  if context.config.s3config?
    _initCb = initCb
    initCb = (context) ->
      tempContext = di.context()
      tempContext.configure config.parseConfig('./')...
      tempContext.register '$p', $p
      tempContext.register '$u', $u
      tempContext.registerAll require('core').aws
      tempContext.registerAll require('core').logger
      tempContext.register 's3config', config.S3Config
      tempContext.invoke (s3config) ->
        s3config.parse().then (s3cfg) ->
          context.configure s3cfg
          _initCb(context)

  context.register 'newrelic', ($options) ->
    if $options?.disabled is true or !$options?.licenseKey?
      return {
        getBrowserTimingHeader: -> ""
        setTransactionName: ->
        createTracer: (label, cb) -> cb
        createWebTransaction: (url, handle) -> handle
        noticeError: ->
        endTransaction: ->
        addCustomParameter: ->
      }
    process.env.NEW_RELIC_APP_NAME = $options?.appName
    process.env.NEW_RELIC_LICENSE_KEY= $options?.licenseKey
    process.env.NEW_RELIC_ERROR_COLLECTOR_IGNORE_ERROR_CODES = ($options?.ignoreErrorCodes || [404, 400]).join(',')
    require('newrelic')

  context.register 'tracer', (newrelic) ->
    (label, callback) -> newrelic.createTracer(label, callback)

  express = require('express')

  context.register '$p', $p
  context.register '$u', $u
  context.register '$v', -> $v
  context.register 'scope', -> scope
  context.registerAll require('core').logger
  context.registerAll require('core').stats
  context.registerAll require('core').aws

  context.register 'statsTracker', (statsTrackerFactory) -> statsTrackerFactory(granularity: 'minutes')

  #We should stop using this one, and let redis rely on redisTime
  context.register 'time', {
    unixTime: -> (new Date()).getTime()
  }

  context.register 'errorHandler',  ($logger, newrelic) ->
    (err, req, res, next) ->
      res.error = err
      if err.message == 'MAX_QUEUE_SIZE_REACHED'
        return res.sendError(503, "TRY AGAIN LATER")
      if err.message == 'NotFound'
        return res.sendError(404, "Not Found")
      newrelic.noticeError(err) if newrelic.noticeError?
      $logger.error $p.filterStackTrace(err.stack) || err
      return res.send(500) unless process.env.NODE_ENV == 'development'
      res.sendError(500, $p.filterStackTrace(err.stack))

  context.register 'domainSupport', (scope, tracer, errorHandler) ->
    index = 0
    (server) ->
      server.use (req, res, next) ->
        _send = res.send
        res.send = (args...) ->
          res._sendInvoked = true
          _send.apply(this, args)
        res.sendError = (code, message, headers) ->
          isJson = req.headers['accept']=='application/json'
          contentType = if isJson then 'application/json' else 'text/plain'
          unless res.headersSent
            res.statusCode = code
            res.setHeader("content-type", contentType)
            if headers?
              _.each headers, (value, header) -> res.setHeader(header, value)
          res.send if isJson then JSON.stringify(message) else message

        nextWrapper = ->
          scope.context.req = req
          scope.context.res = res
          scope.context.tracer = tracer
          scope.context.index = index++
          next()
        currentDomain = scope(nextWrapper)
        currentDomain.on 'error', (err) -> next(err)
        currentDomain.add(req)
        currentDomain.add(res)

  context.register 'scopedVariableFactory', (scope) ->
    (name) ->
      ->
        throw new Error("No Context Set") unless scope.active
        scope.context[name]

  context.register 'timeoutSupport', () ->
    (server, defaultTimeout) ->
      server.use (req, res, next) ->
        req.setTimeout = (timeout) ->
          req.connection.setTimeout(timeout)
          res.connection.setTimeout(timeout)
        req.setTimeout(defaultTimeout) if defaultTimeout?
        next()

  context.register 'requestStatsSupport', ($logger, statsTracker) ->
    f = (server) ->
      server.use (req, res, next) ->
        connectionClosedListener = (err) -> finishRequest("CLOSED")
        req.connection.on 'close', -> res.emit 'done', "CONN-CLOSED"
        res.on 'finish', -> res.emit 'done', "DONE"
        res.on 'close', -> res.emit 'done', "CLOSED"
        next()

      statsTracker.on 'tick', (stats) ->
        perSecond = (stats.requests?.sum || 0) / 60
        @set 'requestsPerSecond', {min: perSecond, max: perSecond, avg: perSecond, sampleCount: 1}

      server.use (req, res, next) ->
        trackableRequest = !req.url.match(/^\/check/)?
        if trackableRequest
          statsTracker.add("requests", 1)
        start = process.hrtime()
        connectionClosedListener = (err) -> finishRequest("CLOSED")
        res.once 'done', (msg) ->
          diff = process.hrtime(start)
          diff = diff[0] * 1e9 + diff[1]
          res.duration = diff / 1e6
          if trackableRequest
            statsTracker.add("responseCode#{res.statusCode}", 1)
            statsTracker.addAverage("latency", res.duration)
        next()

      server.use (req, res, next) ->
        req.clientIp = -> req.headers['HTTP_X_FORWARDED_FOR'] || req.headers['x-forwarded-for'] || req.connection.remoteAddress
        $logger.restrictScope "error" if req.url == '/check'
        url = req.url
        try
          url = decodeURIComponent(req.url)
        catch
        $logger.tagScope req.clientIp(), req.method, url
        $logger.debug "BEGIN REQUEST"
        res.once 'done', (msg) ->
          req.finished = true
          $logger.info msg, {statusCode: res.statusCode, duration: res.duration}
        next()

    f.statsTracker = statsTracker
    f.getCurrentStats = ->
      history = statsTracker.history()
      stats = {}
      _.each history, (entry) ->
        _.each entry.data, (values, key) ->
          stats[key]?=0
          if values.sum?
            stats[key]+=values.sum
          if values.avg?
            stats[key]+=values.avg/history.length
      stats
    f

  context.register 'checkSupport', ($logger, $options, requestStatsSupport, cloudWatch, awsMetadataService) ->
    systemOk = true
    startTime = moment()
    info = null
    minutesToCheck = $options?.minutesToCheck || 10
    scheduleCheck = -> setTimeout checkCloudWatch, 1000*60
    checkCloudWatch = ->
      ($p.when(
        unless info?
          awsMetadataService.getInstanceInfo().then (_info) ->
            info = _info
      ).then ->
        now = moment()
        return unless now.diff(startTime, 'minutes') > minutesToCheck
        from = moment().subtract(11, 'minutes')
        [ cloudWatch.getMetricStatistics("requestsPerSecond", {instanceId: info.instanceId}, 60, 'Average', from, now)
          cloudWatch.getMetricStatistics("requestsPerSecond", {availabilityZone: info.availabilityZone}, 60, 'Average', from, now)
        ].then (instanceMetrics, azMetrics) ->
          $logger.debug "INSTANCE METRICS", [instanceMetrics]
          $logger.debug "AZ METRICS", [azMetrics]
          return unless instanceMetrics.length>=minutesToCheck and azMetrics.length>=minutesToCheck
          instanceAvg = _.reduce(instanceMetrics, ((sum, m) -> sum + parseInt(m.Average)), 0) / instanceMetrics.length
          azAvg = _.reduce(azMetrics, ((sum, m) -> sum + parseInt(m.Average)), 0) / azMetrics.length
          return unless azAvg > 10
          systemOk = ((azAvg - instanceAvg)/azAvg < .5)
          logMessage = "Processed [#{instanceAvg}] avg requests vs [#{azAvg}] for the availability zone."
          $logger.info(logMessage) if systemOk
          $logger.error(logMessage) if !systemOk
      ).finally ->
        scheduleCheck()
    (server) ->
      if $options?.intelligentCheck == true
        scheduleCheck()
        server.get '/check', (req, res) ->
          return res.send("OK") if systemOk
          res.sendError(500, "Degraded Performance Detected") if !systemOk
      else
        server.get '/check', (req, res) ->
          res.send "OK"
      server.get '/status', (req, res) ->
        res.send requestStatsSupport.getCurrentStats()

  context.register 'restSupport', ($logger) ->
    f = (server) ->
      restParameter = (name, value) -> {
        value       : -> value
        intValue    : ->
          return undefined unless value?
          parseInt(value)
        isPresent   : ->
          throw new Error("#{name} parameter is required") unless value?
          return this
        isInteger   : ->
          throw new Error("#{name} parameter must be an integer") if _.isNaN(parseInt(value))
          return this
      }

      restFunction = (f) -> (req, res, next) ->
        args = $u.parseArguments(f)
        parameters = {}
        body = req.body || {}
        parameters[arg] = restParameter(arg, req.params[arg] || req.query[arg] || body[arg]) for arg in args
        nextInvoked = false
        parameters['$next'] = (args...) ->
          nextInvoked = true
          next(args...)
        handlerResult = $u.invokeByName(null, f, parameters)
        if $p.isPromise(handlerResult)
          handlerResult.then
            success: (result) ->
              unless res._sendInvoked or nextInvoked
                res.send(result)
            error: (err) ->
              if err instanceof Error
                $logger.error(err.stack)
                res.sendError(500, "Internal Error") unless res._sendInvoked or nextInvoked
              else
                res.sendError(400, err, {'content-type': 'application/json'}) unless res._sendInvoked or nextInvoked

      setTransactionName = (url) ->
        return (req, res, next) ->
          if server.locals.newrelic?.setTransactionName?
            server.locals.newrelic.setTransactionName("[#{req.method}] #{url}")
          next()

      concatUrl = (baseUrl, url) ->
        return baseUrl+url unless _.isArray(url)
        _.map url, (u) -> baseUrl+u

      server.rest = {
        all: (url, f) ->
          server.all url, setTransactionName(url)
          server.all url, restFunction(f)
          this
        get: (url, f) ->
          server.get url, setTransactionName(url)
          server.get url, restFunction(f)
          this
        post: (url, f) ->
          server.post url, setTransactionName(url)
          server.post url, restFunction(f)
          this
        put: (url, f) ->
          server.put url, setTransactionName(url)
          server.put url, restFunction(f)
          this
        delete: (url, f) ->
          server.delete url, setTransactionName(url)
          server.delete url, restFunction(f)
          this
        nest: (baseUrl) ->
          all: (url, f) ->
            server.rest.all(concatUrl(baseUrl, url),f)
            this
          get: (url, f) ->
            server.rest.get(concatUrl(baseUrl, url),f)
            this
          post: (url, f) ->
            server.rest.post(concatUrl(baseUrl, url),f)
            this
          put: (url, f) ->
            server.rest.put(concatUrl(baseUrl, url),f)
            this
          delete: (url, f) ->
            server.rest.delete(concatUrl(baseUrl, url),f)
            this
          nest: (url) ->
            server.rest.nest(concatUrl(baseUrl, url))
      }
      server.use (req, res, next) ->
        res.set('Connection', 'close')
        next()
    f

  context.register 'memoryWatcher', ($logger) ->
    (maxMemory) ->
      memwatch = require('memwatch-next');
      memwatch.on 'leak', (d) ->
        $logger.error("LEAK:", d);
      memwatch.on 'stats', (stats) ->
        if stats.current_base > 1024*1024*maxMemory
          $logger.error "TOO MUCH MEMORY LEAKED, TERMINATING!!!"
          setTimeout (-> process.exit(1)), 500

  context.register 'requestThrottle', (scopedVariableFactory) ->
    ths = {}
    $req = scopedVariableFactory('req')
    self = (key, concurrency, maxBacklog, block) ->
      [concurrency, maxBacklog, block] = [null, null, concurrency] unless maxBacklog?
      [maxBacklog, block] = [null, maxBacklog] unless block?
      throw new Error("missing required parameters key, [concurrency, [maxBacklog]], block") unless block?
      concurrency?=20
      maxBacklog?=1000
      ths[key]?=throttle(concurrency, maxBacklog) unless ths[key]?
      ths[key] ->
        return if $req().finished is true
        block()

  startTime = process.hrtime()
  $p.when(initCb(context)).then (serverInit) ->
    serverName = opts?.name || 'server'

    context.register serverName, ($options, $logger, errorHandler, newrelic) ->
      serverDomain = domain.create()
      server = undefined
      serverDomain.on 'error', (err) ->
        $logger.error "ERROR IN SERVER DOMAIN!"
        $logger.error $u.inspect(err, 20), err.stack
        newrelic.noticeError(err) if newrelic.noticeError?
        if err?.failure is true or server.started!=true
          $logger.error "FAILURE DETECTED!!! EXITING!"
          process.exit(1)
      serverDomain.run ->
        server = express()
        server.disable('x-powered-by');
        server.locals.newrelic = newrelic
        server.$logger = $logger

        $p.when(serverInit(server)).then ->
          server.use (err, req, res, next) -> errorHandler(err, req, res, next)

          ports = _.flatten([$options.port])
          _.each ports, (port) ->
            server.listen(port, $options.host)
          server.host = $options.host
          server.port = $options.port
          server.started = true

          diff = process.hrtime(startTime)
          timeMs = (diff[0] * 1e9 + diff[1])/1e6
          $logger.info "Started in [#{timeMs}ms] on #{server.host}:#{server.port}"
          server

    context[serverName].then ->

module.exports.defaultRestServer = (opts, initCb) ->
  require('http').globalAgent.maxSockets = 10000
  require('https').globalAgent.maxSockets = 10000
  $p = require('./promise')
  _ = require('lodash')
  bodyParser = require('body-parser');

  [opts, initCb] = [{}, opts] unless initCb?
  opts = _.defaults opts, {
    maxMemory: 100
    defaultTimeout: 60*1000
  }

  module.exports './', opts, (context) ->
    $p.when(initCb(context)).then (serverInit) ->
      (server) -> context.invoke (domainSupport,timeoutSupport,requestStatsSupport,checkSupport,restSupport,memoryWatcher,scopedVariableFactory) ->
        memoryWatcher(opts.maxMemory)
        domainSupport(server)
        timeoutSupport(server, opts.defaultTimeout)
        requestStatsSupport(server)
        server.use(bodyParser.json({strict:false}))
        restSupport(server)
        checkSupport(server)
        context.register '$req', ->  scopedVariableFactory('req')
        context.register '$res', ->  scopedVariableFactory('res')

        shipMetricsToCloudWatchInterval = context.config.server?.shipMetricsToCloudWatchInterval
        if shipMetricsToCloudWatchInterval?
          context.registerAll require('core').cloudWatch
          context.invoke (cloudWatchMetricShipper) ->
            cloudWatchMetricShipper.monitor(requestStatsSupport.statsTracker, shipMetricsToCloudWatchInterval)

        serverInit(server)
