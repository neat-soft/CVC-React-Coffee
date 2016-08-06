should = require('should')
moment = require('moment')
{$p, $u, di, expect, throttle} = require('../index')
_ = require('lodash')

di.describe 'dqsProvider', (ctx, it) ->
  beforeEach (done) ->
    ctx.configure {
      mysqlConnectionPool:
        connectionInfo: {host: 'localhost', user:'dev', password: 'pass', database: "test"}
      dqsProvider:
        waitTime: 10
    }
    ctx.registerAll require('../src/mysql')
    ctx.registerAll require('../src/item_buffer')
    (ctx.invoke (mysqlConnectionPool) ->
      mysqlConnectionPool (conn) ->
        conn.execute("DROP TABLE IF EXISTS dqs")
    ).then ->
      ctx.registerAll require('../src/dqs')
      done()

  afterEach (done) ->
    ctx.mysqlConnectionPool (conn) ->
      conn.execute("DROP TABLE IF EXISTS dqs").then -> done()

  describe "Queueing system", ->
    beforeEach (done) -> ctx.invoke (dqsProvider) -> done()
    testMessage = "Hello World!"
    testRef = $u.md5(testMessage)
    it "should enqueue message and return a reference", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).should.equal(testRef).then ->
        ctx.dqsProvider.get("TEST_QUEUE", testRef).should.equal(testMessage)

    it "should dequeue previously enqueued messages", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 5*60).should.eql(_.object [[ref, testMessage]])

    it "dequeued messages should be delayed by retryIn parameter", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 5*60).should.eql(_.object [[ref, testMessage]]).then ->
          ctx.dqsProvider.getDelay("TEST_QUEUE", ref).then (delay) ->
            (delay > 240).should.equal(true, "delay should be more than 4 minutes")
            (delay <= 300).should.equal(true, "delay should be less than or equal to 5 minutes")

    it "dequeuing a messages should incremenet retried counter", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref) ->
        ctx.dqsProvider.getAttemptCount("TEST_QUEUE", ref).should.equal(0).then ->
          ctx.dqsProvider.dequeue("TEST_QUEUE", 5*60).should.eql(_.object [[ref, testMessage]]).then ->
            ctx.dqsProvider.getAttemptCount("TEST_QUEUE", ref).should.equal(1)

    it "a message should no longer dequeue after 5 attempts", ->
      th = throttle(1)
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref) ->
        (for i in [1..5]
          th ->
            ctx.dqsProvider.dequeue("TEST_QUEUE", 0).should.eql(_.object [[ref, testMessage]])
        ).then ->
          ctx.dqsProvider.dequeue("TEST_QUEUE", 0).should.eql({})

    it "should dequeue a limited number of previously enqueued messages", ->
      (_.map [1..10], (i) ->
        ctx.dqsProvider.enqueue("TEST_QUEUE", "Hello #{i}")
      ).then (refs) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 5*60, 3).then (result) ->
          _.keys(result).length.should.equal(3)

    it "should support getTime", ->
      ctx.dqsProvider.getTime().then (time) ->
        (moment(time).diff(moment(), 'seconds') < 2).should.equal(true)

    it "should honor delay when enqueing", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage, 5*60).then (ref) ->
        ctx.dqsProvider.getDelay("TEST_QUEUE", ref).then (delay) ->
          (delay > 240).should.equal(true, "delay should be more than 4 minutes")
          (delay <= 300).should.equal(true, "delay should be less than or equal to 5 minutes")
          ctx.dqsProvider.dequeue("TEST_QUEUE", 5*60).should.eql({})

    it "should delay items based on current time", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref) ->
        ctx.dqsProvider.getDelay("TEST_QUEUE", ref).then (delay) ->
          delay.should.equal(0)
          ctx.dqsProvider.delay("TEST_QUEUE", 100, ref).then ->
            ctx.dqsProvider.getDelay("TEST_QUEUE", ref).then (delay) ->
              delay.should.equal(100)

    it "should override processAfter", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage, 10).then (ref) ->
        ctx.dqsProvider.getDelay("TEST_QUEUE", ref).should.equal(10).then ->
          ctx.dqsProvider.processAfter("TEST_QUEUE", moment().add(10, 'minutes').toDate(), ref).then ->
            ctx.dqsProvider.getDelay("TEST_QUEUE", ref).then (delay) ->
              (delay > 590 and delay < 610).should.equal(true)

    it "should remove an item from the queue by reference", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage, 5*60).then (ref) ->
        ctx.dqsProvider.remove("TEST_QUEUE", ref).then ->
          ctx.dqsProvider.get("TEST_QUEUE", ref).should.not.exist()

    it "should remove an item from the queue", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage, 5*60).then (ref) ->
        ctx.dqsProvider.removeItems("TEST_QUEUE", testMessage).then ->
          ctx.dqsProvider.get("TEST_QUEUE", ref).should.not.exist()

    it "should monitor a queue and invoke a processor as soon as there are items available", ->
      monitorManager = ctx.dqsProvider.monitor "TEST_QUEUE", 5*60, (message) ->
        message.should.equal(testMessage)
        monitorManager.stop()
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref) ->
        monitorManager.wait().then ->
          ctx.dqsProvider.get("TEST_QUEUE", ref).then (result) ->
            should.not.exist(result)

    it "should keep monitoring even if processing one item fails", ->
      count = 0
      ctx.$logger.error = ->
      monitorManager = ctx.dqsProvider.monitor "TEST_QUEUE", 5*60, (msg) ->
        count++
        monitorManager.stop() if count == 2
        $p.error("OOPS")
      [ ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage)
        ctx.dqsProvider.enqueue("TEST_QUEUE", "Hello 2")
      ].then (ref1, ref2) ->
        monitorManager.wait().then ->
          [ ctx.dqsProvider.get("TEST_QUEUE", ref1).should.equal(testMessage)
            ctx.dqsProvider.get("TEST_QUEUE", ref2).should.equal("Hello 2")
          ].then ->

    it "should monitor a queue and return multiple items if they are available", ->
      counter = 0
      (_.map [1..10], (i) -> ctx.dqsProvider.enqueue("TEST_QUEUE", "TEST #{i}")).then ->
        monitorManager = ctx.dqsProvider.monitorBatch "TEST_QUEUE", 5*60, 2, (messages...) ->
          messages.length.should.equal(2)
          counter+=messages.length
          monitorManager.stop() if counter == 10
        monitorManager.wait().then ->
          ctx.dqsProvider.getQueueSize("TEST_QUEUE").should.equal(0)

    it "should monitor a queue and invoke a batch processor as soon as there are items available", ->
      counter = 0
      monitorManager = ctx.dqsProvider.monitorBatch "TEST_QUEUE", 5*60, 1, (messages...) ->
        messages.length.should.equal(1)
        counter+=messages.length
        monitorManager.stop() if counter == 10
      $u.pause(1000).then ->
        (_.map [1..10], (i) -> ctx.dqsProvider.enqueue("TEST_QUEUE", "TEST #{i}")).then ->
          monitorManager.wait().then ->
            ctx.dqsProvider.getQueueSize("TEST_QUEUE").should.equal(0)

    it "should monitor a queue and survive dequeue errors/failures", ->
      count = 0
      ctx.$logger.error = ->
      ctx.dqsProvider.dequeue = ->
        count++
        monitorManager.stop() if count >= 2
        return $p.error("OOPS")
      monitorManager = ctx.dqsProvider.monitor "TEST_QUEUE", 5*60, ->
      [ ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage)
        ctx.dqsProvider.enqueue("TEST_QUEUE", "Hello 2")
        ctx.dqsProvider.enqueue("TEST_QUEUE", "Hello 2")
      ].then (ref1, ref2) ->
        monitorManager.wait().then ->
          count.should.equal(2)

    it "should support getting the queue size", ->
      ctx.dqsProvider.getQueueSize("TEST_QUEUE").should.equal(0).then ->
        [ ctx.dqsProvider.enqueue("TEST_QUEUE", "Hello1")
          ctx.dqsProvider.enqueue("TEST_QUEUE", "Hello2")
        ].then ->
          ctx.dqsProvider.getQueueSize("TEST_QUEUE").should.equal(2)

    it "should reset attempts when inserting an existing item into the queue", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref1) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 100).then ->
          ctx.dqsProvider.getAttemptCount("TEST_QUEUE", ref1).should.equal(1)
          ctx.dqsProvider.enqueue("TEST_QUEUE", testMessage).then (ref2) ->
            ref2.should.equal(ref1)
            ctx.dqsProvider.getQueueSize("TEST_QUEUE").should.equal(1)
            ctx.dqsProvider.getAttemptCount("TEST_QUEUE", ref1).should.equal(0)

    it "should support objects as messages", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", key:'value').then (ref1) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 100).then (results)->
          results[ref1].should.eql(key: 'value')

    it "should support integers as messages", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", 234).then (ref1) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 100).then (results)->
          results[ref1].should.equal(234)

    it "should support floats as messages", ->
      ctx.dqsProvider.enqueue("TEST_QUEUE", 2.34).then (ref1) ->
        ctx.dqsProvider.dequeue("TEST_QUEUE", 100).then (results)->
          results[ref1].should.equal(2.34)

  describe "dqsBatchJobProvider", ->
    beforeEach (done) ->
      ctx.registerMock 'dqsProvider'
      done()
    afterEach (done) ->
      ctx.dqsBatchJobProvider.stop().then -> done()

    describe "calcNextRunOn", ->
      it "should add a few days to a given time", ->
        moment(ctx.dqsBatchJobProvider._calcNextRunOn("2016-01-01", {
          frequency: 2 * 60 * 24
        })).toString().should.eql("Sun Jan 03 2016 00:00:00 GMT-0500")

      it "should force a paricular hour and minute", ->
        moment(ctx.dqsBatchJobProvider._calcNextRunOn("2016-01-01", {
          frequency: 2 * 60 * 24
          hour: 4
          minute: 3
        })).toString().should.eql("Sun Jan 03 2016 04:03:00 GMT-0500")

    it "should schedule registered jobs after registering it", ->
      ctx.dqsBatchJobProvider._enqueueMissingJobs = expect().andResolve()
      ctx.dqsBatchJobProvider.register('TEST1', {frequency: 1}, (->)).then ->
        ctx.dqsBatchJobProvider._enqueueMissingJobs.hasExpectations().should.equal(false)

    it "should enqueue missing jobs with proper delay", ->
      ctx.dqsBatchJobProvider._definitions['TEST1'] = {
        ref: "XYZ"
        frequencyDef: {frequency: 2}
      }
      ctx.dqsProvider.getDelay = expect("JOB_QUEUE", "XYZ").andResolve(null)
      ctx.dqsBatchJobProvider.scheduleJob = expect("TEST1", {frequency: 2}).andResolve()
      ctx.dqsBatchJobProvider._enqueueMissingJobs()

    it "should schedule job with a proper delay", ->
      ctx.dqsProvider.enqueue = expect("JOB_QUEUE", "TEST", 120).andResolve("XYZ")
      ctx.dqsProvider.getDelay = expect("JOB_QUEUE", $u.md5("TEST")).andResolve(10)
      ctx.dqsBatchJobProvider.scheduleJob("TEST", {frequency: 2})

    it "should schedule job with rounding to a proper time", ->
      ctx.dqsProvider.enqueue = expect("JOB_QUEUE", "TEST", 86400).andResolve("XYZ")
      ctx.dqsProvider.getTime = expect().andResolve(moment("2016-01-02 03:44:00 -05:00").toDate())
      ctx.dqsProvider.processAfter = expect("JOB_QUEUE", moment("2016-01-03 03:15:00 -05:00").toDate(), "XYZ").andResolve()
      ctx.dqsProvider.getDelay = expect("JOB_QUEUE", $u.md5("TEST")).andResolve(10)
      ctx.dqsBatchJobProvider.scheduleJob("TEST", {frequency: 24*60, hour: 3, minute: 15})

    it "should schedule the next execution before executing job", ->
      ctx.dqsBatchJobProvider._definitions['TEST1'] = {
        ref: "XYZ"
        frequencyDef: "FREQ"
        block: expect().andResolve('XYZ')
      }
      ctx.dqsBatchJobProvider.scheduleJob = expect("TEST1", "FREQ").andResolve()
      ctx.dqsBatchJobProvider.executeJob("TEST1").should.equal('XYZ')

    it "should keep rescheduling a job while its executing", ->
      ctx.dqsBatchJobProvider._definitions['TEST1'] = {
        ref: "XYZ"
        frequencyDef: "FREQ"
        rescheduleFrequency: 100
        block: -> $u.pause(300).then -> 'XYZ'
      }
      ctx.dqsBatchJobProvider.scheduleJob = expect("TEST1", "FREQ").andResolve()
                                           .expect("TEST1", "FREQ").andResolve()
                                           .expect("TEST1", "FREQ").andResolve()
      ctx.dqsBatchJobProvider.executeJob("TEST1").should.equal('XYZ').then ->
        ctx.dqsBatchJobProvider.scheduleJob.hasExpectations().should.equal(false)

