should = require('should')
{$p, $u, di, expect, config} = require('../index')
_ = require('lodash')

di.describe 'cloudWatchMetricShipper', (ctx, it) ->
  stats = null
  beforeEach (done) ->
    ctx.registerAll require('../src/stats')
    ctx.registerAll require('../src/cloud_watch')
    ctx.register 'statsTracker', (statsTrackerFactory) -> statsTrackerFactory(granularity: 'minute')
    ctx.registerMock 'cloudWatch'
    ctx.invoke (statsTracker, cloudWatchMetricShipper) ->
      stats = statsTracker
      done()

  it 'should add a value and track stats to current stats', ->
    stats.add('KEY1', 1, '2016-01-01T03:00:00')
    stats.add('KEY2', 1, '2016-01-01T03:00:00')
    stats.add('KEY2', 2, '2016-01-01T03:15:00')
    history = stats.history()
    ctx.cloudWatchMetricShipper.convertStatsTrackerHistory(history[0].data, {KEY2: 'Seconds'}).should.eql
      KEY1: [{ Maximum: 1, Minimum: 1, sampleCount: 1, sum: 1 }, 'Count']
      KEY2: [{ Maximum: 1, Minimum: 1, sampleCount: 1, sum: 1 }, 'Seconds']
