{EventEmitter} = require('events')
moment = require('moment')
_ = require('lodash')


exports.StatsTrackerFactory = ($p) ->
  return (opts) ->
    opts = _.merge {}, opts, {format: moment.ISO_8601, maxHistory: 20}
    throw new Error("granularity is a required option") unless opts.granularity?
    history = []
    data = {}
    currentTimestamp = null
    eventEmitter = new EventEmitter()
    return self = {
      add: (key, value, timestamp, isAverage) ->
        timestamp = moment(timestamp).startOf(opts.granularity)
        if !currentTimestamp?
          currentTimestamp = timestamp
        else if currentTimestamp? and timestamp.isAfter(currentTimestamp)
          eventEmitter.emit 'tick', data
          history.push(timestamp: currentTimestamp.format(opts.format), data: data)
          history = history.slice(-opts.maxHistory)
          data = {}
          currentTimestamp = timestamp
        stats = data[key]?={min: 0, max: 0, sampleCount: 0}
        if isAverage and !stats.avg? and !stats.sum?
          stats.avg?=0
        else if !isAverage and !stats.avg? and !stats.sum?
          stats.sum?=0
        stats.min = if stats.sampleCount==0 then value else Math.min(stats.min, value)
        stats.max = if stats.sampleCount==0 then value else Math.max(stats.max, value)
        stats.sampleCount++
        if isAverage
          stats.avg+= (value - stats.avg)/stats.sampleCount
        else
          stats.sum+= value
        stats

      addAverage: (key, value, timestamp) -> self.add(key, value, timestamp, true)
      set: (key, statValues) -> data[key]=statValues
      currentStats: -> _.cloneDeep(data)
      history: -> _.cloneDeep(history)
      on: (event, handler) -> eventEmitter.on(event, handler.bind(this))
    }

