should = require("should")
scope = require("../src/scope")
$p = require("../src/promise")
$u = require("../src/utilities")
expect = require('../src/expect')
_ = require('lodash')

describe "Scope", ->
  s = null
  afterEach ->
    s.dispose()

  it "should execute the block passed to scope", (done) ->
    s = scope(done)

  it "should catch the error directly within block", (done) ->
    s = scope -> throw new Error("Hello")
    s.on 'error',  (err) ->
      err.message.should.equal "Hello"
      done()

  it "should catch the error indirectly within block", (done) ->
    s = scope -> setImmediate -> throw new Error("Hello")
    s.on 'error',  (err) ->
      err.message.should.equal "Hello"
      done()

  it "should check if there is an active scope", (done) ->
    scope.active.should.equal(false)
    s = scope ->
      setImmediate ->
        scope.active.should.equal(true)
        done()

  it "should retrieve the currently active scope", (done) ->
    should.not.exist(scope.current)
    s = scope ->
      setImmediate ->
        scope.current.should.equal(s)
        done()

  it "should permit access to the variables(context) inside the scope", (done) ->
    should.not.exist(scope.context)
    s = scope ->
      scope.context.test = "Hello World!"
      setImmediate ->
        scope.context.test.should.equal("Hello World!")
        done()

  describe "run", ->
    it "should support blocks that return promises", (done) ->
      scope.active.should.equal(false, "no scope should exist in the beginning of the test")
      block = -> $p.create (p) -> setImmediate -> p.resolve("OK")
      scope.run(block).then (result) ->
        result.should.equal("OK")
        scope.active.should.equal(false, "no scope should exist in after the test")
        done()

    it "should not support blocks that dont return promises", (done) ->
      block = ->
      scope.run(block).then
        failure: (err) ->
          err.message.should.equal("Block must return a promise")
          done()

    it "should propogate errors correctly", (done) ->
      block = -> $p.create (p) -> setImmediate -> p.error("ERR")
      scope.run(block).then
        success: -> should.fail("success should not be called")
        error: (args...) ->
          args.should.eql(["ERR"])
          done()

    it "should propogate failures correctly", (done) ->
      block = -> $p.create (p) -> setImmediate -> p.failure("ERR")
      scope.run(block).then
        success: -> should.fail("success should not be called")
        failure: (args...) ->
          args.should.eql(["ERR"])
          done()

    it "should properly handle blocks that throw errors", (done) ->
      (scope.run ->
        throw "OOPS"
      ).then
        failure: (err) ->
          err.should.equal("OOPS")
          done()

    it "should support nested scopes", (done) ->
      (scope.run ->
        scope.context.variable = "V1"
        (scope.run ->
          should.not.exist(scope.context.variable)
          scope.context.variable = "V2"
          $p.resolved()
        ).then ->
          scope.context.variable.should.equal("V1")
          $p.resolved()
      ).then -> done()
