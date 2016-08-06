should = require('should')
{$p, $u, di, expect, config} = require('../index')
_ = require('lodash')

di.describe 'statsTracker', (ctx, it) ->
  stats = null
  beforeEach (done) ->
    ctx.registerAll require('../src/stats')
    ctx.register 'statsTracker', (statsTrackerFactory) -> statsTrackerFactory(granularity: 'minute')
    ctx.invoke (statsTracker) ->
      stats = statsTracker
      done()


  it 'should add a value and track stats to current stats', ->
    stats.add('KEY1', 1)
    stats.add('KEY2', 1)
    stats.add('KEY2', 2)
    stats.currentStats().should.eql({
        KEY1: {min: 1, max: 1, sum: 1, sampleCount: 1}
        KEY2: {min: 1, max: 2, sum: 3, sampleCount: 2}
    })

  it 'should add an average and track it as a single sample to avoid huge sums', ->
    stats.add('KEY1', 1)
    stats.addAverage('KEY2', 1)
    stats.addAverage('KEY2', 2)
    stats.currentStats().should.eql({
        KEY1: {min: 1, max: 1, sum: 1, sampleCount: 1}
        KEY2: {min: 1, max: 2, avg: 1.5, sampleCount: 2}
    })

  it 'should support setting a key with all the stats data', ->
    stats.set('KEY1', {min: 1, max: 1, sum: 2, sampleCount: 2})
    stats.currentStats().should.eql({
        KEY1: {min: 1, max: 1, sum: 2, sampleCount: 2}
    })


  it 'should keep history of stats in a timeseries based on granularity', ->
    stats.add('KEY1', 1, '2016-01-01T00:01:00')
    stats.add('KEY1', 1, '2016-01-01T00:01:30')
    stats.add('KEY1', 2, '2016-01-01T00:02:10')
    stats.add('KEY1', 2, '2016-01-01T00:03:10')
    stats.history().should.eql([
      {timestamp: "2016-01-01T00:01:00-05:00", data: {KEY1: {min: 1, max: 1, sum: 2, sampleCount: 2}}}
      {timestamp: "2016-01-01T00:02:00-05:00", data: {KEY1: {min: 2, max: 2, sum: 2, sampleCount: 1}}}
    ])

  it 'should support derived keys', ->
    stats.on 'tick', (stats) ->
      perSecond = stats.KEY1.sum / 60
      @set 'KEY2', {min: perSecond, max: perSecond, avg: perSecond, sampleCount: 1}
    stats.add('KEY1', 1, '2016-01-01T00:01:00')
    stats.add('KEY1', 2, '2016-01-01T00:01:30')
    stats.add('KEY1', 6, '2016-01-01T00:02:10')
    stats.add('KEY1', 2, '2016-01-01T00:03:10')
    stats.history().should.eql([
      {timestamp: "2016-01-01T00:01:00-05:00", data: {
        KEY1: {min: 1, max: 2, sum: 3, sampleCount: 2}
        KEY2: {min: .05, max: .05, avg: .05, sampleCount: 1}
      }}
      {timestamp: "2016-01-01T00:02:00-05:00", data: {
        KEY1: {min: 6, max: 6, sum: 6, sampleCount: 1}
        KEY2: {min: .1, max: .1, avg: .1, sampleCount: 1}
      }}
    ])
