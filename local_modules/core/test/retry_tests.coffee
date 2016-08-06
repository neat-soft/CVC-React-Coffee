should = require('should')
retry = require('../src/retry')
$p = require('../src/promise')

describe "retry", ->
  it "should retry with exponential backoff", (done) ->
    count = 0
    start = process.hrtime()
    (retry /RetryMe/, 5, 2, (counter) ->
      count++
      return "OK" if counter == 3
      $p.error(new Error("RetryMe"))
    ).then (result) ->
      diff = process.hrtime(start)
      timeMs = (diff[0] * 1e9 + diff[1])/1e6
      (timeMs > 28).should.equal.true
      count.should.equal(4)
      result.should.equal("OK")
      done()

  it "should fail after max number of retries", (done) ->
    count = 0
    (retry /RetryMe/, 3, 2, (counter) ->
      count++
      $p.error(new Error("RetryMe"))
    ).then
      success: -> should.fail("success should not be called")
      error: (result) ->
        result.message.should.equal("RetryMe")
        count.should.equal(4)
        done()

  it "should support using function to check the error block", (done) ->
    count = 0
    errorHandler = (err) -> err.message == 'RetryMe'
    (retry errorHandler, 3, 2, (counter) ->
      count++
      $p.error(new Error("RetryMe"))
    ).then
      success: -> should.fail("success should not be called")
      error: (result) ->
        result.message.should.equal("RetryMe")
        count.should.equal(4)
        done()

  it "make sure the stack trace isn't shown multiple times for code that's retried", (done) ->
    errorHandler = (err) -> err.message == 'RetryMe'
    f = (counter) ->
      $p.error(new Error("RetryMe"))
    (retry errorHandler, 3, 2, f).then
      success: -> should.fail("success should not be called")
      error: (result) ->
        result.stack.match(/at doRetry/g).length.should.equal(1)
        done()

