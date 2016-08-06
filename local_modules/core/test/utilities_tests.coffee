should = require('should')
$u = require('../src/utilities')
$p = require('../src/promise')
_ = require('lodash')

describe "bindToCurrentDomain", ->
  d1 = d2 = null
  f = (requiredDomain) -> ->
    return should.not.exist(process.domain) unless requiredDomain?
    process.domain.should.equal(requiredDomain)

  beforeEach ->
    createDomain = require('domain').createDomain
    d1 = createDomain()
    d2 = createDomain()

  it "should bind to an existing domain", ->
    f1 = null
    d1.run ->
      f1 = $u.bindToActiveDomain(f(d1))
    d2.run ->
      f1()

  it "should bind to a non-existing domain", ->
    f1 = $u.bindToActiveDomain(f(null))
    d2.run ->
      f1()

describe "String", () ->
  it "should support toCamelCase", ->
    $u.toCamelCase("hello_world").should.equal("helloWorld")
    $u.toCamelCase("hello").should.equal("hello")

  it "should support toSnakeCase", ->
    $u.toSnakeCase("helloWorld").should.equal("hello_world")
    $u.toSnakeCase("helloWorldUser").should.equal("hello_world_user")
    $u.toSnakeCase("hello").should.equal("hello")

  it "should support toVariableName", ->
    $u.toVariableName("MTurkAPI").should.equal("mturkApi")
    $u.toVariableName("HelloWorld").should.equal("helloWorld")
    $u.toVariableName("HITLayoutId").should.equal("hitLayoutId")
    $u.toVariableName("Hello World").should.equal("helloWorld")
    $u.toVariableName("Hello World 1").should.equal("helloWorld1")
    $u.toVariableName("HIT Layout Id").should.equal("hitLayoutId")

  it "Should parse regular functions", ->
    f = (a,b) ->
    $u.parseArguments(f).should.eql(["a","b"])

  it "Should parse anonymous functions", ->
    $u.parseArguments((a,b) ->).should.eql(["a","b"])

  it "Should parse constructors", ->
    class A
      constructor:(a,b) ->
    $u.parseArguments(A).should.eql(["a","b"])

  it "Should inject regular functions", (done) ->
    f = (a, b) ->
      a.should.equal "A"
      b.should.equal "B"
      done()

    $u.invokeByName this, f, {
      a: "A"
      b: "B"
    }

  it "should inject $argNames when invoking by name", (done) ->
    f = (a, $argNames) ->
      a.should.equal "Hello"
      $argNames.should.eql ["a", "$argNames"]
      done()
    $u.invokeByName this, f, {a: "Hello"}

  it "Should not override parameters in subsequent arrays", (done) ->
    f = (a, b, d) ->
      a.should.equal "A"
      b.should.equal "B"
      d.should.equal "D"
      done()

    $u.invokeByName this, f, {a: "A", b: "B"}, {a: "C", d: "D"}

  it "should pull last element in the array to the right", ->
    ($u.pullLast 1, undefined, undefined).should.eql [undefined, undefined, 1]
    ($u.pullLast 1, 2, undefined).should.eql [1, undefined, 2]

describe "spawnBuffered", ->
  it "should execute a command and buffer the stdout", (done) ->
    $u.spawnBuffered("/bin/sh", "-c" ,"echo Hello World").then (stdout) ->
      stdout.toString().trim().should.equal("Hello World")
      done()

  it "should execute a command and buffer the stderr", (done) ->
    $u.spawnBuffered("/bin/sh", "-c" ,"echo Hello World 1>&2").then (stdout, stderr) ->
      stderr.toString().trim().should.equal("Hello World")
      done()

  it "should execute a command and trigger an error if return code is not 0", (done) ->
    $u.spawnBuffered("/bin/sh", "-c" ,"echo Hello World; exit 1").then
      success: -> should.fail("Success should not be called")
      error: (code, stdout, stderr) ->
        code.should.equal 1
        stdout.toString().trim().should.equal("Hello World")
        done()

describe "spawnUnbufferedOutput", ->
  it "should execute a command and leave output unbuffered", (done) ->
    proc = $u.spawnUnbufferedOutput("/bin/sh", "-c" ,"echo Hello World")
    output = ""
    proc.stdout.on 'data', (data) -> output+=data
    proc.then (stderr) ->
      stderr.length.should.equal 0
      output.trim().should.equal("Hello World")
      done()

  it "should execute a command and buffer the stderr", (done) ->
    $u.spawnUnbufferedOutput("/bin/sh", "-c" ,"echo Hello World 1>&2").then (stderr) ->
      stderr.toString().trim().should.equal("Hello World")
      done()

  it "should execute a command and trigger an error if return code is not 0", (done) ->
    $u.spawnUnbufferedOutput("/bin/sh", "-c" ,"echo Hello World 1>&2; exit 1").then
      success: -> should.fail("Success should not be called")
      error: (code, stderr) ->
        code.should.equal 1
        stderr.toString().trim().should.equal("Hello World")
        done()

  it "should support a basic even string to int hash function", ->
    counters = [0,0,0,0,0]
    for i in [1...100000]
      counters[$u.hashCode($u.md5(i.toString()))%5]++
    for i in [1...counters.length]
      (Math.abs((counters[0]-counters[i])/counters[0]) < .02).should.be.true

  describe "groupByPrefix", ->
    original = {hello:'world!', test:1, iFly:1, iSleep:2, iNap:3, youSleep: 1, youNap: 2}
    grouped = {hello:'world!', test:1, i: {fly:1, sleep:2, nap:3}, you: {sleep: 1, nap: 2}}
    it "should group object properties by common prefix", ->
      $u.groupByPrefix(original, {i:'i', you:'you'}).should.eql(grouped)

    it "should rename prefix if different", ->
      $u.groupByPrefix({iFly:1}, {i:'you'}).should.eql({you:{fly:1}})

    describe "flattenObject", ->
      it 'should flatten object', ->
        $u.flattenObject(grouped).should.eql(original)

      it 'should rename prefixes', ->
        $u.flattenObject({you:{fly:1}}, _.invert({i:'you'})).should.eql({iFly:1})

      it 'should pass through functions', ->
        f = -> "OK"
        $u.flattenObject({f: f}).should.eql({f: f})

      it 'should pass through dates, integers, and strings', ->
        d = new Date()
        $u.flattenObject({d: d, i: 1, s: "Hello"}).should.eql({d: d, i: 1, s: "Hello"})

  describe "pageBlock", (done) ->
    it "should paginate until false is returned", (done) ->
      count = 0
      ($u.pageBlock 0, (page) ->
        count++
        return true if page < 3
      ).then ->
        count.should.equal(4)
        done()

    it "should propogate errors from the block", ->
      $u.pageBlock(0, (page) -> $p.error("OOPS")).should.eql(error: ["OOPS"])
