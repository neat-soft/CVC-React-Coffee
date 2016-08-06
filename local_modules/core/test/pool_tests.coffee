should = require("should")
pool = require("../src/pool")
$p = require("../src/promise")

describe "Pool", ->
  pl = counter = null
  create  = -> $p.resolved(counter++)
  destroy = -> $p.resolved(counter--)
  beforeEach ->
    require('domain').active.exit() if require('domain').active?

    counter = 1
    pl = pool.create(create: create, destroy: destroy)

  it "should call create when new instance is requested and return a promise for it", (done) ->
    pl().then (index) ->
      pl.getAvailable().should.equal 9
      index.should.equal(1)
      done()

  it "should support create instances that don't return a promise", (done) ->
    pl1 = pool.create(create: (->counter++), destroy: destroy)
    pl1().then (index) ->
      pl1.getAvailable().should.equal 9
      index.should.equal(1)
      done()

  it "should support with method which automatically releases the instance on success", (done) ->
    (pl (index) ->
      index.should.equal(1)
      pl.getAvailable().should.equal 9
      $p.resolved("Hello World!")
    ).then (result) ->
      pl.getAvailable().should.equal 10
      result.should.eql "Hello World!"
      done()

  it "should support with method which automatically releases the instance on error", (done) ->
    (pl.with (index) ->
      $p.error("Hello World!")
    ).then
      success: -> fail("Success should not be called")
      error: (errs...) ->
        errs.should.eql ["Hello World!"]
        done()

  it "should not reuse destroyed connections", (done) ->
    counter = 0
    opts = {
      create: -> {counter: counter++}
      destroy: (instance) ->
      errorHandler: (poolInstance, instance, err) ->
        poolInstance.destroy(instance)
    }
    pl = pool.create(opts)
    safeError = {error: (err) -> err}
    (pl (instance) -> instance.counter.should.equal(0); return $p.resolved("OK")).then ->
      (pl (instance) -> instance.counter.should.equal(0); return $p.error("ERR")).then(safeError).then ->
        (pl (instance) -> instance.counter.should.equal(1); return $p.resolved("OK")).then(safeError).then ->
          pl.getAllocated().should.equal(1)
          done()

  it "should support destroying all connections from errorHandler", (done) ->
    counter = 0
    opts = {
      create: -> {counter: counter++}
      destroy: (instance) ->
      errorHandler: (poolInstance, instance, err) ->
        poolInstance.destroyAll()
        poolInstance.destroy(instance)
    }
    pl = pool.create(opts)
    safeError = {error: (err) -> err}
    ((pl (instance) ->) for i in [1..10]).then ->
      pl.getStats().should.eql({acquired: 0, allocated: 10, idle:10, available: 10, size: 10, waiting: 0})
      ((pl (instance) -> $p.error("ERR")).then(safeError) for i in [1..5]).then ->
        ((pl (instance) ->) for i in [1..10]).then ->
          pl.destroyAllIdle()
          pl.getStats().should.eql({acquired: 0, allocated: 0, idle: 0, available: 10, size: 10, waiting: 0})
          done()

  it "should track available instances", (done) ->
    pl.getAvailable().should.equal(10)
    pl.getAllocated().should.equal(0)
    finish = ((pl (instance) ->) for i in [1..10])
    pl.getAvailable().should.equal(0)
    pl.getAllocated().should.equal(10)
    finish.then ->
      pl.getAvailable().should.equal(10)
      pl.getAllocated().should.equal(10)
      pl.getIdle().should.equal(10)
      done()

  it "should destroy idle instances", (done) ->
    pl.getAvailable().should.equal(10)
    finish = ((pl (instance) ->) for i in [1..10])
    pl.getAllocated().should.equal(10)
    pl.getAvailable().should.equal(0)
    finish.then ->
      pl.getAllocated().should.equal(10)
      pl.getAvailable().should.equal(10)
      pl.getIdle().should.equal(10)
      pl.destroyAllIdle()
      pl.getAllocated().should.equal(0)
      pl.getAvailable().should.equal(10)
      pl.getIdle().should.equal(0)
      counter.should.equal(1)
      done()

  it "should destroy all instances", (done) ->
    pl.getAllocated().should.equal(0)
    finish = ((pl (instance) ->) for i in [1..10])
    finish.then ->
      finish2 = ((pl (instance) ->) for i in [1..5])
      pl.getAllocated().should.equal(10)
      pl.getIdle().should.equal(5)
      destroy = pl.destroyAll()
      [finish2, destroy].then ->
        pl.getAllocated().should.equal(0)
        counter.should.equal(1)
        done()

  it "should preserve the domain of the caller when using callbacks", (done) ->
    domain = require('domain')
    main = domain.create()
    main.index = 'main'
    should.not.exist(domain.active, "No domain should exist before the test")
    pl = pool.create(create: create, destroy: destroy, max: 2)
    main.run ->
      pl (index) ->
        domain.active.index.should.equal("main", "INCORRECT DOMAIN #{domain.active.index}")
        index.should.equal(1)
        [d1, d2] = [domain.createDomain(), domain.createDomain()]
        d1.index = 0
        d2.index = 1
        d1.run ->
          pl (index) ->
            index.should.equal(2)
            domain.active.index.should.equal(0, "INCORRECT DOMAIN #{domain.active.index}")
        d2.run ->
          pl (index) ->
            index.should.equal(2)
            domain.active.index.should.equal(1, "INCORRECT DOMAIN #{domain.active.index}")
            done()

  it "should support nested acquire", (done) ->
    isDone = false
    $p.when(
      pl (i1) ->
        pl (i2) ->
          i1.should.not.equal(i2)
          isDone = true
    ).then ->
      isDone.should.equal(true)
      done()