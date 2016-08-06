_ = require('lodash')

exports.EventManager = ->
  handlers = {}
  return self = {
    on: (event, retryIn, handler) ->
      [retryIn, handler] = [null, retryIn] unless handler?
      handlers[event]?=[]
      handlers[event].push(handler)

    emit: (event, data...) ->
      (_.map handlers[event], (handler) -> handler(data...)).then ->

  }

exports.DqsEventManager = ($options, dqsProvider, eventManager) ->
  monitors = {}
  $options = _.merge {}, {retryIn: 5*60, dequeueBatchSize: 10, processBatchSize: 1}, ($options || {})
  return self = {
    on: (event, opts, handler) ->
      [handler, opts] = [opts, {}] if _.isFunction(opts)
      opts = {retryIn: opts} unless _.isObject(opts)
      opts = _.merge {}, $options, opts
      eventManager.on(event, handler)
      return if $options?.local == true
      monitors[event] = dqsProvider.monitorBatch event, opts.retryIn, opts.dequeueBatchSize, opts.processBatchSize, (message...) ->
        eventManager.emit(event, message...).then ->

    emit: (event, data) ->
      if $options?.local != true
        dqsProvider.enqueue(event, data).then ->
      else
        eventManager.emit(event, data).then ->
  }

exports.SqsEventManager = ($options, sqsProvider, eventManager) ->
  monitors = {}
  $options = _.merge {retryIn: 5*60, blockingTimeout: 20, numMessages: 1}, ($options || {})
  return self = {
    on: (event, opts, handler) ->
      [handler, opts] = [opts, {}] if _.isFunction(opts)
      opts = {retryIn: opts} unless _.isObject(opts)
      opts = _.merge {}, $options, opts
      eventManager.on(event, handler)
      monitors[event] = sqsProvider.monitor event, opts.numMessages, opts.retryIn, opts.blockingTimeout, (message) ->
        eventManager.emit(event, message).then ->

    emit: (event, data) ->
      sqsProvider.enqueue(event, data).then ->
  }

exports.GlobalEventManager = ($options, $p) ->
  providers = {
    'dqs': => this.dqsEventManager
    'sqs': => this.sqsEventManager
    'local': => this.eventManager
  }
  provider = $options?.provider || 'local'
  return $p.error("Uknown provider #{provider}") unless providers[provider]?
  $p.when(providers[provider]()).then (provider) ->
    return self = {
      on: (event, retryIn, handler) -> provider.on(event, retryIn, handler)
      emit: (event, data) -> provider.emit(event, data)
    }