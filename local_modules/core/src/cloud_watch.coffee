moment = require('moment')
_ = require('lodash')
$u = require('./utilities')

exports.cloudWatchMetricShipper = ($options, $logger, cloudWatch) ->
  defaultUnitMapping =
    latency: 'Milliseconds'

  return self = {
    convertStatsTrackerHistory: (statsTrackerHistory, unitMapping = {}) ->
      _.object _.map statsTrackerHistory, (v, k) ->
        if v.avg?
          v.sum = v.avg
          v.sampleCount = 1
          delete v.avg
        v = _.merge {Minimum: v.min, Maximum: v.max}, _.omit(v, 'min', 'max')
        [k, [v, unitMapping[k] || 'Count']]

    monitor: (statsTracker, interval = 30, unitMapping) ->
      alreadyPushed = []
      unitMapping = _.merge {}, defaultUnitMapping, unitMapping
      sendMetricsToCloudwatch = ->
        history = statsTracker.history()
        newEntries = _.reject history, (entry) -> _.indexOf(alreadyPushed, entry.timestamp) > -1
        ($u.pageBlock 0, (i) ->
          return false unless newEntries[i]?
          {timestamp, data} = newEntries[i]
          data = self.convertStatsTrackerHistory(data, unitMapping)
          alreadyPushed.push(timestamp)
          cloudWatch.recordMetrics(data, {}, moment(timestamp).unix()).then -> true
        ).then(
          success: ->
            alreadyPushed = _.map history, (entry) -> entry.timestamp
            setTimeout sendMetricsToCloudwatch, interval*1000
          error: (err) ->
            $logger.error("Error shipping metrics to cloudwatch [#{err.message}]")
            setTimeout sendMetricsToCloudwatch, interval*1000*10
        )

      sendMetricsToCloudwatch()
  }

