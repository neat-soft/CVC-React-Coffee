should = require("should")
restBuilder = require('../src/rest_builder')
$p = require("../src/promise")
expect = require('../src/expect')
throttle = require('../src/throttle')

describe "Rest Builder", ->
  describe "throttle", ->
    it "should throttle a request", (done) ->
      counter = 0

      f = restBuilder.throttle(1,0).then (rq,rs) ->
        counter++
        $p.create()
      f({}, {})
      f({}, {}).then
        success: -> should.fail("[success] should not be called")
        error: (err) ->
          counter.should.equal(1)
          err.message.should.equal(throttle.MAX_QUEUE_SIZE_REACHED)
          done()

    it "should execute block when available", (done) ->
      f = restBuilder.throttle(1,1).then (rq, rs) ->
        $p.resolved("OK")
      f({},{}).then (result) ->
        result.should.equal "OK"
        done()

  describe "domainWrapper", ->
    it "should pass through requests/responses without errors", (done) ->
      f = restBuilder.domainWrapper().then (rq, rs) ->
        $p.resolved("OK")

      f({},{}).then
        success: (result) ->
          result.should.equal("OK")
          done()
        error: -> should.fail("[error] should not be called")
        failure: -> should.fail("[failure] should not be called")

    it "should wrap a request in a domain and convert uncaught errors in callbacks into failures", (done) ->
      f = restBuilder.domainWrapper().then (rq, rs) ->
        setTimeout (-> throw new Error("ERR1")),10
        $p.create()

      f({},{}).then
        success: -> should.fail("[success] should not be called")
        error: -> should.fail("[error] should not be called")
        failure: (err) ->
          err.message.should.equal("ERR1")
          done()
