should = require("should")
promise = require("../src/promise")
moment = require('moment')

describe "Promise", () ->
  beforeEach ->
    require('domain').active.exit() if require('domain').active?

  it "should create a deferred promise", (done) ->
    p = promise.create()
    p.then (value) ->
      should.exist(value)
      value.should.equal("Hello World!")
      done()
    p.resolve("Hello World!")

  it "should respond to an already resolved promises", (done) ->
    p = promise.create()
    p.resolve("Hello World!")

    ok = false
    p.then (value) ->
      should.exist(value)
      value.should.equal("Hello World!")
      done()

  it "should invoke nested callbacks on resolved promises", (done) ->
    p = promise.create()
    p.then ->
      p.then ->
        done()
    p.resolve("OK")

  it "should invoke nested callbacks on resolved promises only once", (done) ->
    p = promise.create()
    count = 0
    p.then ->
      count++
      p.then ->
        count++
    p.resolve("OK")
    setTimeout (
      ->
        count.should.equal(2)
        done()
    ), 10


  it "should invoke callbacks in correct order", (done) ->
    p = promise.create()
    count=0
    order = ""
    p.then () ->
      count++
      order += "A"
    p.then () ->
      count++
      order += "B"
    p.then () ->
      count.should.equal(2)
      order.should.equal("AB")
      done()
    p.resolve("Hello World!")

  it "should not invoke callbacks more than once when listening on resolved promise", (done) ->
    p = promise.resolved("OK")
    count = 0
    p.on 'success', ->
      count++
    p.then ->
    p.then ->
    setImmediate ->
      count.should.equal(1)
      done()

  it "should support a global method to merge promises", (done) ->
    p1 = promise.create()
    p2 = promise.create()
    p3 = promise.create()

    promise.merge(p1, p2, p3).then (values...) ->
      values.should.eql(["Hello","World",["!", "?"]])
      done()
    p1.resolve("Hello")
    p2.resolve("World")
    p3.resolve("!","?")

  it "should support merging nested arrays of promises", (done) ->
    p1 = promise.create()
    p2 = promise.create()
    p3 = promise.create()

    promise.merge(p1, [p2, p3]).then (values...) ->
      values.should.eql(["Hello",["World",["!", "?"]]])
      done()
    p1.resolve("Hello")
    p2.resolve("World")
    p3.resolve("!","?")

  it "should support Array.merge", (done) ->
    [promise.resolved("Hello"), promise.resolved("World")].merge().then (args...) ->
      args.should.eql(["Hello", "World"])
      [promise.resolved("Hello"), promise.resolved("World")].merge(true).then (args) ->
        args.should.eql(["Hello", "World"])
        done()

  it "should throw an error at subsequent attempts to resolve a promise", (done) ->
    p = promise.create()
    second = false
    p.then (value) ->
      if(second)
        throw new Error("Should not call callbacks more than once")
      second = true
      try
        p.resolve("THIS SHOULD FAIL")
        should.fail()
      catch e
        e.message.should.equal("Invalid attempt to resolve a resolved promise")
        done()
    p.resolve("Hello World!")

  it "should support being resolved with a promise", (done) ->
    p1 = promise.create()
    p2 = promise.create()
    p2.resolve(p1)
    p2.then (args...) ->
      args.should.eql [1,2,3]
      done()
    p1.resolve 1,2,3

  it "should support errors when resolved with a promise", (done) ->
    p1 = promise.create()
    p2 = promise.create()
    p2.resolve(p1)
    p2.then
      success: -> should.fail()
      error: (args...) ->
        args.should.eql [1,2,3]
        done()
    p1.error 1,2,3

  it "should support second form of then to capture errors", (done) ->
    p = promise.create()
    p.then
      success: (value) ->
        fail("Should not be called, expecting an error")
      error: (error) ->
        error.should.equal "Hello World!"
        done()
    p.error "Hello World!"

  it "should support finally method", (done) ->
    p = promise.create()
    i = 1
    fp = p.finally((type, err) ->
      type.should.equal("error")
      i = i + err
    )
    fp.then
      success: -> should.fail("Success should not be called")
      error: (err) ->
        err.should.equal(2)
        i.should.equal(3)
        done()
    p.error(2)

  it "should support then method and return the answer of the callback", (done) ->
    p = promise.create()
    r = p.then (r1) -> r1+"R2"
    r.then (result) ->
      result.should.equal "R1R2"
      done()
    p.resolve "R1"

  it "should support then method and return the object answer of the callback", (done) ->
    p = promise.create()
    r = p.then (r1) -> {a:r1+"R2", f:[1,2,3]}
    r.then (result) ->
      result.should.eql {a:"R1R2", f:[1,2,3]}
      done()
    p.resolve "R1"

  it "should support then method and return the promise of the callback", (done) ->
    p = promise.create()
    r = p.then (r1) -> promise.resolved(r1+"R2")
    r.then (result) ->
      result.should.equal "R1R2"
      done()
    p.resolve "R1"

  it "should support chaining then methods for resolved promises", (done) ->
    p = promise.resolved("X").then (x) -> promise.resolved("#{x}YZ")
    p.then (s) ->
      s.should.equal "XYZ"
      done()

  it "should support separate callbacks for success/error with then method", (done) ->
    p1 = promise.create()
    p2 = p1.then
      success: (v) -> v+1
      error  : (v) -> v+2
    p2.then (v) ->
      v.should.equal 2
      done()
    p1.resolve(1)

  it "should support passing errors to separate callbacks with then method", (done) ->
    p1 = promise.create()
    p2 = p1.then
      success: (v) -> v+1
      error  : (v) -> v+2
    p2.then (v) ->
      v.should.equal 3
      done()
    p1.error(1)

  it "propogate errors through the then chain", (done) ->
    p1 = promise.create()
    p2 = p1.then -> promise.error("ERR2")
    p3 = p2.then
      success: -> fail()
      error: (err) ->
        err.should.equal("ERR1")
        done()
    p1.error("ERR1")

  it "should support resolving properties of objects", (done) ->
    obj = {
      p1: 1
      p2: promise.resolved(1).then -> {a:2, z:3}
      p3: promise.resolved(3)
    }
    obj.toPromise().then ->
      obj.should.eql {p1:1, p2:{a:2, z:3}, p3:3}
      done()

  it "should correctly handle errors when resolving properties of objects", (done) ->
    obj = {
      p1: 1
      p2: promise.resolved(1).then -> {a:2, z:3}
      p3: promise.error("ERROR1")
    }
    obj.toPromise().then
      error: (err) ->
        err.should.equal("ERROR1")
        done()

  it "should correctly handle functions as results", (done) ->
    [p1, p2, p3] = [promise.create(), promise.create(), promise.create()]
    f = ->
    [p1, p2, p3].then (results...) ->
      results.should.eql [null, f, "HELLO WORLD!"]
      done()
    p1.resolve(null)
    p2.resolve(f)
    p3.resolve("HELLO WORLD!")

  it "should preserve the domain of the caller", (done) ->
    domain = require('domain')
    main = domain.create()
    main.index = 'main'
    should.not.exist(domain.active, "No domain should exist before the test")
    main.run ->
      [d1, d2] = [domain.createDomain(), domain.createDomain()]
      d1.index = 0
      d2.index = 1
      p = promise.create()
      [p1, p2] = [promise.create(), promise.create()]
      check = (expected) -> (r) ->
        r.should.equal(2)
        should.exist(domain.active)
        domain.active.index.should.equal(expected, "INCORRECT DOMAIN #{domain.active.index}")
      d1.run ->
        p.then(check(0)).then ->
          p1.resolve()
      d2.run ->
        p.then(check(1)).then ->
          p2.resolve()
      p.resolve(2)
      [p1, p2].then ->
        should.exist(domain.active)
        domain.active.index.should.equal 'main', "INCORRECT DOMAIN #{domain.active.index}"
        done()

  describe "safe promise", ->
    it "should correctly handle no errors", (done) ->
      should.not.exist(process.domain, "No domain should exist")
      p = promise.inDomain -> "OK"

      p.then
        success: (result) ->
          should.not.exist(process.domain, "when using then outside the safe block domain should not exist")
          result.should.equal("OK")
          done()
        error: -> should.fail("[error] should not be called")
        failure: -> should.fail("[failure] should not be called")

    it "should invoke inDomain block inside a domain and exit domain for callbacks outside of it", (done) ->
      should.not.exist(process.domain, "No domain should exist")
      p1 = promise.create()
      p = promise.inDomain ->
        should.exist(process.domain, "domain should exist when invoked in an inDomain block")
        "OK"
      p.then (result) ->
        should.not.exist(process.domain, "domain should not exist outside the inDomain block")
        result.should.equal "OK"
        done()

    it "should wrap a request in a domain and convert uncaught errors in callbacks into failures", (done) ->
      should.not.exist(process.domain, "No domain should exist")
      p = promise.inDomain ->
        setTimeout (-> throw new Error("ERR2")),10
        promise.create()

      p.then
        success: -> should.fail("[success] should not be called")
        error: -> should.fail("[error] should not be called")
        failure: (err) ->
          should.not.exist(process.domain, "domain should not exist outside the inDomain block")
          err.message.should.equal("ERR2")
          done()

    it "should support having multiple domains in parallel", (done) ->
      should.not.exist(process.domain, "No domain should exist")
      done1 = promise.create()
      done2 = promise.create()
      p1 = promise.inDomain ->
        process.domain.tag = 1
        setTimeout (-> throw new Error("ERR10")),5
        promise.create()
      p1.then
        success: -> should.fail("[success] should not be called")
        error: -> should.fail("[error] should not be called")
        failure: (err) ->
          should.not.exist(process.domain, "domain should not exist outside the inDomain block")
          err.message.should.equal("ERR10")
          err.domain.tag.should.equal 1
          done1.resolve()

      p2 = promise.inDomain ->
        process.domain.tag = 2
        setTimeout (-> throw new Error("ERR11")),8
        promise.create()
      p2.then
        success: -> should.fail("[success] should not be called")
        error: -> should.fail("[error] should not be called")
        failure: (err) ->
          should.not.exist(process.domain, "domain should not exist outside the inDomain block")
          err.message.should.equal("ERR11")
          err.domain.tag.should.equal 2
          done2.resolve()

      [done1, done2].merge().then -> done()

  describe "wrapping", ->
    it "should wrap callback function (err, results...) and return results", ->
      f = (args..., cb) -> cb(args...)
      promise.wrap(f null, 1, 2,promise.ecb()).should.eql [1,2]

    it "should wrap callback function (err, results...) and return error", ->
      f = (args..., cb) -> cb(args...)
      promise.wrap(f "ERROR", 1, 2,promise.ecb()).then
        success: -> should.fail("success should not be called")
        failure: -> should.fail("success should not be called")
        error: (err) -> err.should.equal("ERROR")


  describe "error handling", ->
    it "should propogate error event if error is returned", (done) ->
      p = promise.create()
      p.then
        success: -> throw new Error("[success] should not be called")
        failure: -> throw new Error("[failure] should not be called")
        error: (err) ->
          err.should.equal("OK")
          done()
      p.error("OK")

    it "should propogate failure event if failure is returned", (done) ->
      p = promise.create()
      p.then
        success: -> throw new Error("[success] should not be called")
        error: -> throw new Error("[error] should not be called")
        failure: (err) ->
          err.should.equal("OK")
          done()
      p.failure("OK")

    it "should propogate failure event if an exception is caught", (done) ->
      p = promise.create()
      np = p.then -> throw new Error("Hello World!")
      np.then
        success: -> throw new Error("[success] should not be called")
        error: -> throw new Error("[error] should not be called")
        failure: (err) ->
          err.message.should.equal("Hello World!")
          done()
      p.resolve("OK")

    it "should propogate the first error from a merged promise", (done) ->
      p1 = promise.create()
      p2 = promise.create()
      p3 = promise.create()
      p = [p1, p2, p3].merge()
      p.then
        success: -> throw new Error("[success] should not be called")
        failure: -> throw new Error("[failure] should not be called")
        error: (err) ->
          err.fromIndex.should.equal 1
          err.message.should.equal("ERR1")
          done()
      p2.error(new Error("ERR1"))
      p1.error(new Error("ERR2"))
      p3.resolve("OK")

    it "should propogate the first failure from a merged promise", (done) ->
      p1 = promise.create()
      p2 = promise.create()
      p3 = promise.create()
      p = [p1, p2, p3].merge()
      p.then
        success: -> throw new Error("[success] should not be called")
        error: -> throw new Error("[error] should not be called")
        failure: (err) ->
          err.fromIndex.should.equal 1
          err.message.should.equal("ERR1")
          done()
      p2.failure(new Error("ERR1"))
      p1.failure(new Error("ERR2"))
      p3.resolve("OK")

    it "should propogate errors when only some of the callbacks are used", (done) ->
      p2 = promise.create()

      p1 = p2.then
        success: -> should.fail("[success] should not be called")

      p1.then
        error: ->
          done()

      p2.error("OK")
      null

    it "should propogate errors when then is called inline with error", (done) ->
      promise.error("ERR3").then
        success: -> throw new Error("[success] should not be called")
        error: (err) ->
          err.should.equal("ERR3")
          done()
        failure: -> throw new Error("[failure] should not be called")

    it "should propogate errors when then is called after an error was resolved", (done) ->
      p = promise.error("ERR3")
      p.once 'error', -> #IGNORE FIRST ERROR OTHERWISE IT WILL BE THROWN
      process.nextTick ->
        p.then
          success: -> throw new Error("[success] should not be called")
          error: (err) ->
            err.should.equal("ERR3")
            done()
          failure: -> throw new Error("[failure] should not be called")

    it "should support nested calls", (done) ->
      p = (p2, i) ->
        return done() if i <=0
        p2.then ->
          p(promise.resolved("OK"), --i)
      p(promise.resolved("OK"), 1001)

    it "should properly handle custom errors with prepared stacks", ->
      p = promise.create()
      myErr = new Error()
      Object.defineProperty myErr, 'stack', {
        writable:true
        configurable:true
        value: "Hello World!"
      }
      p.then
        error: (err) -> err.stack.should.equal("Hello World!")
      p.error(myErr)

    it "should support long stack traces", (done) ->
      errf = (cb) -> setImmediate -> cb(new Error("ERR"))
      f = (cb) -> setImmediate -> errf(cb)
      f1 = ->
        promise.wrap(f(promise.ecb()))
      f1a = (cb) ->
        promise.resolved("asdf").then ->
          cb()
      f2 = -> f1a(f1)
      f2().then
        success: -> should.fail()
        error: (err) ->
          (err.stack.match(/.*f1.*/)?).should.equal(true)
          (err.stack.match(/.*f1a.*/)?).should.equal(true)
          (err.stack.match(/.*f2.*/)?).should.equal(true)
          done()

    it "should support long stack traces in failures", (done) ->
      f1 = -> promise.create (p) -> setImmediate -> p.failure(new Error("Hello"))
      f2 = -> f1()
      f2().then
        success: -> should.fail()
        error: -> should.fail()
        failure: (err) ->
          (err.stack.match(/.*f1.*/)?).should.equal(true)
          (err.stack.match(/.*f2.*/)?).should.equal(true)
          done()

    it "should support long stack traces when failures are thrown rather than returned", (done) ->
      f = (cb) -> throw new Error("Hello")
      f1 = -> promise.wrap(f(promise.ecb()))
      f1a = (cb) -> promise.resolved("asdf").then -> cb()
      f2 = -> f1a(f1)
      f2().then
        success: -> should.fail()
        error: -> should.fail()
        failure: (err) ->
          err.message.should.equal("Hello")
          (err.stack.match(/.*f1.*/)?).should.equal(true)
          (err.stack.match(/.*f1a.*/)?).should.equal(true)
          (err.stack.match(/.*f2.*/)?).should.equal(true)
          done()

  describe "proxy", ->
    it "should always delegate 'then' method to the promise", ->
      p = promise.create()
      proxy = p.proxy()
      setImmediate -> p.resolve("Hello World!")
      proxy.then (v) ->
        v.should.equal("Hello World!")

    it "should create proxy object that will wait for the promise to resolve before proxying any function calls", ->
      p = promise.create()
      proxy = p.proxy()
      setImmediate -> p.resolve("Hello World!")
      v = proxy.toString()
      promise.isPromise(v).should.equal(true)
      v.should.equal("Hello World!")

    it "should send errors to the global/domain handler", ->
      domain = require('domain')
      main = domain.create()
      p = promise.create()
      errPromise = promise.create()
      proxy = p.proxy()
      main.run ->
        setImmediate -> p.error("Hello World!")
      promise.wrap(main.on 'error', promise.cb()).then (err) ->
        err.message.should.equal("Hello World!")

    it "should take a callback and pass it the value of the resolved promise, for performance optimization pattern", ->
      p = promise.create()
      value = p.proxy(-> value = @)
      setImmediate -> p.resolve("Hello World!")
      p.then ->
        value.should.equal("Hello World!")

    it "should support unproxy", ->
      p = promise.create()
      value = p.proxy()
      value.unproxy(-> value = @)
      setImmediate -> p.resolve("Hello World!")
      p.then ->
        value.should.equal("Hello World!")

    it "should support thenProxy method, returning a proxy but continuing exection when the promise is resolved", ->
      p = promise.create()
      p1 = promise.create()
      p2 = promise.create()
      setImmediate -> p1.resolve("Hello")
      setImmediate -> p2.resolve("World!")
      [p1, p2].then().thenProxy (o1, o2) ->
        promise.isPromise(o1.toString())
        promise.isPromise(o2.toString())
        [o1.toString(), o2.toString()].then (v1, v2) ->
          p.resolve("#{v1} #{v2}")
      p.should.equal("Hello World!")

    it "should support thenProxy with no callback", ->
      p1 = promise.create()
      setImmediate -> p1.resolve("Hello")
      proxy = p1.thenProxy()
      promise.isPromise(proxy.toString())
      proxy.toString().should.equal("Hello")

  describe "should property", ->
    it "should support equals", (done) ->
      promise.resolved("OK").should.equal("OK").then ->
        done()
    it "should support not equals", (done) ->
      promise.resolved("OK").should.not.equal("KO").then ->
        done()
    it "should correctly handle null values", (done) ->
      promise.resolved(null).should.not.exist().then ->
        done()
    it "should correctly handle expected errors", (done) ->
      promise.error("OOPS").should.eql(error: ["OOPS"]).then ->
        done()
    it "should support exist", (done) ->
      promise.resolved("OK").should.exist().then ->
        done()
    it "should support not exist", (done) ->
      promise.resolved(null).should.not.exist().then ->
        done()

describe "memory leaks", ->
  @timeout(3*1000)
  testTime = 2
  runTest = (done, testBlock) ->
    startTime = moment()
    counter = 0
    memwatch = require('memwatch-next');
    usedHeap = []
    memwatch.on 'stats', (stats) ->
      usedHeap.push stats.current_base/(1024*1024)

    to = null
    gc = ->
      memwatch.gc()
      to = setTimeout gc, 500
    finish = ->
      clearTimeout(to)
      return done() if usedHeap.length < 3
      memleak = usedHeap[usedHeap.length-1] - usedHeap[1]
      (memleak < 5).should.equal(true, "Memory leak can't be more than 10m, detected [#{memleak}]")
      done()
    doIt = ->
      counter++
      testBlock ->
        return finish() if moment().diff(startTime,'seconds')>=testTime
        doIt()
      null
    doIt()
    gc()

  it "should not leak memory in test1", (done) ->
    runTest done, (cb) ->
      p = promise.create()
      p.resolve()
      p.then ->
        cb()

  it "should not leak memory in test2", (done) ->
    runTest done, (cb) ->
      p = promise.create()
      p.then ->
        cb()
      p.resolve()

  it "should not leak memory in test3", (done) ->
    runTest done, (cb) ->
      p = promise.create()
      setTimeout (-> p.resolve()), 1
      p.then -> cb()
