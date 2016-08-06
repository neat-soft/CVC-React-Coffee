_ = require('lodash')
throttle = require('./throttle')
$u = require('./utilities')
$p = require('./promise')
moment = require('moment')
url = require('url')

requestToFunctionMapper = (block) -> (req, res) ->
  $u.invokeByName(null, block, {'$req':req, '$res': res}, req.params, req.query)

appendToChain = (chain, item) ->
  chain = $u.extendObject(chain, {elements: []}) unless chain.elements?
  chain.elements.push(item)
  chain

module.exports = {
  use: (block) ->
    appendToChain this, block

  throttle: (concurrent, maxQueue) ->
    [th, concurrent, maxQueue] = [concurrent, undefined, undefined] if _.isFunction(concurrent)
    th = throttle(concurrent, maxQueue) unless th?
    appendToChain this, (req, res, next) ->
      th -> $p.when(next())

  exitOnFailure: ->
    appendToChain this, (req, res, next) ->
      result = next()
      $p.when(result).bindOnce
        failure: (err) ->
          console.log "FAILURE DETECTED: EXITING", err.stack
          process.exit(1)

  mapErrors: ->
    appendToChain this, (req, res, next) ->
      $p.when(next()).bindOnce
        error: (err) ->
          res.send(err?.responseCode || 500, err.message)
        failure: (err) ->
          res.send(500)

  logRequests: (logger) ->
    appendToChain this, (req, res, next) ->
      start = process.hrtime();
      log = (type, args...) ->
        diff = process.hrtime(start)
        typeToLevelMap = {success: 'info', error: 'warn', failure: 'error'}
        message = "[#{moment().format("YYYYMMDD hh:mm:ss.SSS ZZ")}] #{req.connection.remoteAddress}:#{req.connection.remotePort} [#{req.route.path}(%s)]"
        meta = {}
        meta.error = args?[0]?.message || args if type!='success'
        meta.duration = (diff[0] * 1e9 + diff[1])/1e6
        objToString = (obj, level) ->
          level ||= 0
          return obj unless  _.isObject(obj)
          str = ""
          for own k, v of obj
            str+="#{if str.length>0 then ', ' else ''}#{k}=#{objToString(v, level+1)}"
          if level>0 then "[#{str}]" else str

        logger.log typeToLevelMap[type], message, objToString($u.merge(req.params, req.query)), meta
      $p.when(next()).bindOnce
        success: (args...) -> log('success', args...)
        error: (args...) -> log('error', args...)
        failure: (args...) -> log('failure', args...)

  sendResults: ->
    appendToChain this, (req, res, next) ->
      $p.when(next()).bindOnce
        success: (result) ->
          res.send(200, result)

  responseHandler: ->
    this.mapErrors().sendResults()

  domainWrapper: ->
    appendToChain this, (req, res, next) ->
      $p.inDomain ->
        process.domain.add(req)
        process.domain.add(res)
        $p.when(next())

  then: (block) ->
    chain = this.elements
    chain.push requestToFunctionMapper(block)
    (req, res) ->
      invokeChainItem = (index) ->
        next = -> invokeChainItem(index+1)
        try
          chain[index](req, res, next)
        catch e
          return $p.failure(e)
      invokeChainItem(0)
}
