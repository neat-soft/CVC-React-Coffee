should = require('should')
{$p, di} = require('../index')

di.describe 'RedisQueueProvider', (ctx, it) ->
  beforeEach (done) ->
    ctx.registerAll require('../src/redis')
    ctx.registerAll require('../src/redis_queue')

    ctx.register '$u', require('../src/utilities')
    ctx.register 'time', {
      currentTime: -> new Date(self.unixTime()-skew)
      unixTime: -> (new Date()).getTime()
    }
    ctx.redisPromisePool (redis) ->
      redis.keys("queue:TEST:*").then (keys) ->
        return done() unless keys.length > 0
        redis.del(keys...).then -> done()

  afterEach (done) ->
    ctx.redisPool.destroyAcquired().then -> done()

  require('./redis_queue_tests_helper').genericQueueTests(it, -> ctx.redisQueueProvider)

  describe 'QueueMonitor', ->
    it "should support monitor method", ->
      queueMonitor = ctx.queueMonitorFactory(ctx.redisQueueProvider)
      $p.create (p) ->
        counter=0;
        (ctx.redisQueueProvider.enqueue("TEST", "HELLO#{i}") for i in [0...300]).then ->
          queueMonitor.monitor "TEST", 1, 1, (msg) ->
            counter++
            if counter >= 10
              p.resolve(counter)
          p.then (c) ->
            c.should.equal(10)

  xit "dequeue should be fast with a large queue", ->
    @timeout(1000000)
    time = (block) ->
      start = process.hrtime()
      block().then (results...) ->
        diff = process.hrtime(start)
        timeMs = (diff[0] * 1e9 + diff[1])/1e6
        $p.resolved(results..., timeMs)

    length = 200
    th1 = require("../src/throttle")(1)
    (for i in [1..length]
      do (i) ->
        th1 ->
          (time ->
            (for j in [1..100]
              do (j) ->
                ctx.redisQueueProvider.enqueue("TEST", (i*100)+j)
            ).then ->
          ).then (results..., enqueueTimeMs)->
            ctx.redisQueueProvider.getSize("TEST").then (size) ->
              (time ->
                ctx.redisQueueProvider.dequeue("TEST",15).then (ref, item) ->
                  ctx.redisQueueProvider.remove("TEST", ref)
              ).then (results..., timeMs) ->
                console.log "DONE #{i}[#{size}]", "ENQUEUE TIME: #{enqueueTimeMs/100}", "DEQUEUE TIME : #{timeMs}"
    ).then ->

  xit "should be stable at high concurrency", ->
    length=100
    expectedSum = sum = 0
    expectedSum+=i for i in [0..length]
    enqConc = deqConc = maxEnqConc = maxDeqConc = 0
    (ctx.redisQueueProvider.enqueue("TEST",i) for i in [0..length]).then ->
      (for i in [0..length]
        ctx.redisQueueProvider.dequeue("TEST",15).then (ref, item) ->
          sum+=item
      ).then ->
        sum.should.equal expectedSum





