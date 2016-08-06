should = require("should")
throttle = require("../src/throttle")
expect = require("../src/expect")
$p = promise = require('../src/promise')
$u = require('../src/utilities')

describe "Throttle", ->
  it "should limit concurrency to an inner block", ->
    th = throttle(2)
    counter = 0
    th -> promise.resolved(counter++)
    th -> promise.resolved(counter++)
    th -> promise.resolved(counter++)
    counter.should.equal 2

  it "should execute blocks synchronously if throttle is set to 1", (done) ->
    th = throttle(1)
    counter = 0
    concurrency = 0
    block = ->
      return promise.error("Concurrency greater than 1") if concurrency > 1
      promise.create (p) ->
        setTimeout((-> concurrency--;p.resolve(counter++)),100)
    [ th(-> block())
      th(-> block())
      th(-> block())
    ].then (counters...) ->
      counters.length.should.equal 3
      done()

  it "should support blocks that don't return promises", ->
    th = throttle(2)
    counter = 0
    th -> counter++
    th -> counter++
    th -> counter++
    counter.should.equal 2

  it "should return a promise for each block invocation", (done) ->
    th = throttle(2)
    p = promise.create()
    (th -> p).then -> done()
    p.resolve()

  it "should support optional timeout", (done) ->
    th = throttle(2)
    th(50, -> promise.create()).then
      error: (err) ->
        err.message.should.equal("TIMEOUT WHILE EXECUTING THROTTLED BLOCK")
        done()

  it "should support default timeout", (done) ->
    th = throttle(2, undefined, 50)
    th(-> promise.create()).then
      error: (err) ->
        err.message.should.equal("TIMEOUT WHILE EXECUTING THROTTLED BLOCK")
        done()

  it "should support maximum queue size", (done) ->
    th = throttle(2,1)
    counter = 0
    errorCaught = false
    f = ->
      counter++
      promise.create (p) ->
        setTimeout (-> p.resolve()), 100
    [ (th(-> f()))
      (th(-> f()))
      (th(-> f()))
      (th(-> f()).then
        success: -> should.fail("Success should not be called")
        error: (err) ->
          counter.should.equal 2
          th.getBacklog().should.equal 1
          err.message.should.equal(throttle.MAX_QUEUE_SIZE_REACHED)
          errorCaught = true
          promise.error(err)
      )
    ].then
      success: -> should.fail("Success should not be called")
      error: (err) ->
        counter.should.equal 3
        th.getBacklog().should.equal 0
        err.message.should.equal(throttle.MAX_QUEUE_SIZE_REACHED)
        err.fromIndex.should.equal 3
        errorCaught.should.equal(true)
        done()

describe "Fifo", ->
  it "should process work as its comming in, in proper chunks", (done) ->
    processedItems = []
    processor = (items) ->
      items.length.should.equal(5)
      processedItems=processedItems.concat(items)
    fifo = throttle.fifo(5, 10, processor)
    fifo.push [1,2,3,4,5,6,7,8,9,10]
    fifo.waitUntilDone().then ->
      processedItems.should.eql [1,2,3,4,5,6,7,8,9,10]
      done()

  it "should queue up work until maxBacklog and then wait before any more items are added", (done) ->
    expected = [
      [1..5]
      [6..10]
      [10..14]
      [15..19]
    ]
    p = null
    executions = 0
    processor = (data) ->
      executions++
      data.should.eql(expected.shift())
      p = $u.pause(1)
    fifo = throttle.fifo(5, 5, processor)
    fifo.push([1..5]).then ->
      fifo.backlog().should.equal(5, "queue not full after initial push")
      result = fifo.push([6..10])
      $p.isPromise(result).should.equal(true, "push did not return a promise")
      fifo.backlog().should.equal(5, "queue should not grow if max backlog is reached")
      executions.should.equal(1)
      result.then ->
        executions.should.equal(2)
        fifo.backlog().should.equal(5)
        fifo.waitUntilDone().then ->
          fifo.backlog().should.equal(0)
          done()

