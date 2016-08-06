should = require("should")
{$p, di, expect} = require('../index')

di.describe 'Events', (ctx, it) ->
  beforeEach ->
    ctx.registerAll require('../src/events')
    ctx.registerMock 'dqsProvider'

  describe "EventManager", ->
    it "should subscribe to events and invoke handlers when events are emitted", ->
      handler = expect("value").andResolve()
      ctx.eventManager.on 'test', handler
      ctx.eventManager.emit("test", "value").then ->
        handler.hasExpectations().should.equal(false)

    it "should wait for all handlers to be executed before emit promise is resolved", ->
      handler1 = expect("value").andResolve()
      handler2 = expect("value").andResolve()
      ctx.eventManager.on 'test', handler1
      ctx.eventManager.on 'test', handler2
      ctx.eventManager.emit("test", "value").then ->
        handler1.hasExpectations().should.equal(false)
        handler2.hasExpectations().should.equal(false)

    it "should return an error if any of the handlers fail", ->
      handler1 = -> return $p.error("OOPS")
      handler2 = expect("value").andResolve()
      ctx.eventManager.on 'test', handler1
      ctx.eventManager.on 'test', handler2
      ctx.eventManager.emit("test", "value").then
        succes: -> should.fail("success should not be called")
        error: (err) ->
          err.should.equal("OOPS")

  describe 'DqsEventManager', ->
    beforeEach ->
      ctx.registerMock 'eventManager'
    describe 'Local Mode', ->
      beforeEach ->
        ctx.configure {dqsEventManager: local:true}

      it "should emit events to local listeners only", ->
        ctx.eventManager.emit = expect('test', 3).andResolve()
        ctx.dqsEventManager.emit('test', 3)

    describe 'Global Mode', ->
      it "should forward all messages to corresponding dqs queue", ->
        ctx.dqsProvider.enqueue = expect('test', 1).andResolve()
        ctx.dqsEventManager.emit('test', 1)

      it "should monitor a dqs queue and local event manager for events", ->
        ctx.eventManager.on = expect('test', "HANDLER").andResolve()
        ctx.eventManager.emit = expect('test', "MESSAGE").andResolve()
        ctx.dqsProvider.monitorBatch = (event, retryIn, dequeueBatchSize, processBatchSize, handler) ->
          event.should.equal('test')
          retryIn.should.equal(20)
          dequeueBatchSize.should.equal(10)
          processBatchSize.should.equal(1)
          handler("MESSAGE")
        ctx.dqsEventManager.on('test', 20, "HANDLER")

      it "should handle overwriting batch sizes", ->
        ctx.eventManager.on = expect('test', "HANDLER").andResolve()
        ctx.eventManager.emit = expect('test', "MESSAGE").andResolve()
        ctx.dqsProvider.monitorBatch = (event, retryIn, dequeueBatchSize, processBatchSize, handler) ->
          event.should.equal('test')
          retryIn.should.equal(1)
          dequeueBatchSize.should.equal(2)
          processBatchSize.should.equal(3)
          handler("MESSAGE")
        ctx.dqsEventManager.on('test', {retryIn: 1, dequeueBatchSize: 2, processBatchSize: 3}, "HANDLER")

  describe 'GlobalEventManager', ->
    beforeEach ->
      ctx.registerMock 'dqsEventManager'
      ctx.registerMock 'sqsEventManager'
      ctx.registerMock 'localEventManager'

    it "should delegate to dqsEventManager if dqs provider is selected", ->
      ctx.configure {globalEventManager: provider: 'dqs'}
      ctx.dqsEventManager.emit = expect('TEST', 1).andResolve()
      ctx.globalEventManager.then (gem) -> gem.emit 'TEST', 1

    it "should delegate to sqsEventManager if sqs provider is selected", ->
      ctx.configure {globalEventManager: provider: 'sqs'}
      ctx.sqsEventManager.emit = expect('TEST', 2).andResolve()
      ctx.globalEventManager.then (gem) -> gem.emit 'TEST', 2

    it "should delegate to eventManager if local provider is selected", ->
      ctx.configure {globalEventManager: provider: 'local'}
      ctx.eventManager.emit = expect('TEST', 3).andResolve()
      ctx.globalEventManager.then (gem) -> gem.emit 'TEST', 3
