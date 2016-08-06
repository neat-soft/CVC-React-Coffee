should = require("should")
di = require("../src/di")
promise = require('../src/promise')
{newObject} = require('../src/new_object')

describe "Dependency Injector", ->
  describe "Context", ->
    context = null
    beforeEach ->
      context = di.context()

    it "should register new singletons, but not instantiate them", ->
      context.register "Obj", (a,b) ->
        fail("Should not be invoked")

      should.exist context.registered['Obj']

    it "should instantiate new singletons", (done) ->
      context.register "Obj", ->
        test: ->
          done()

      obj1 = context.lookup 'Obj'
      obj2 = context.lookup 'Obj'
      should.exist obj1
      obj1.should.equal obj2
      obj1.test()

    it "should support registering constants", ->
      context.register "hello", "HELLO"
      context.lookup("hello").should.equal("HELLO")

    it "should support registering functions as constants", ->
      context.registerConstant "hello", (a) -> "HELLO"
      context.lookup("hello")().should.equal("HELLO")

    it "should inject dependencies", (done) ->
      context.register "d1", -> {}
      context.register "d2", -> {}
      context.register "obj", (d1, d2) ->
        d1.should.equal context.lookup("d1")
        d2.should.equal context.lookup("d2")
        done()

      context.lookup "obj"

    it "should create new instances of classes", ->
      class A
        constructor: (@z) ->

      context.register("z", "HELLO")
      context.register("a", A)
      context.register("b", A)

      context.lookup("a").z.should.equal "HELLO"
      context.lookup("a").should.not.equal(context.lookup("b"))
      context.lookup("a").__proto__.should.equal(context.lookup("b").__proto__)

    it "should properly inject super constructor", ->
      class A
        constructor: (@z) ->
          @z1="INIT"

      class B extends A
        constructor: (@x) ->
          @x1="INIT"
          super()

      class C extends B
        constructor: (@y) ->
          @y1="INIT"
          super()

      context.register("z", "HELLO")
      context.register("x", "WORLD")
      context.register("y", "!")
      context.register("b", C)

      context.lookup("b").x1.should.equal "INIT"
      context.lookup("b").z1.should.equal "INIT"
      context.lookup("b").y1.should.equal "INIT"
      context.lookup("b").z.should.equal "HELLO"
      context.lookup("b").x.should.equal "WORLD"
      context.lookup("b").y.should.equal "!"

      should.not.exist (new C()).z
      should.not.exist (new C()).x
      should.not.exist (new C()).y

      should.not.exist (new B()).z
      should.not.exist (new B()).x
      should.not.exist (new B()).y

    it "should support invoking arbitrary functions", ->
      f = (a, b) ->
        a.should.equal "HELLO"
        b.should.equal "WORLD!"
        return "#{a} #{b}"

      context.register "a", "HELLO"
      context.register "b", "WORLD!"
      context.invoke(f).should.equal "HELLO WORLD!"

    it "should set nextClassName for newObject", ->
      context.register "a", -> newObject {value:"Hello"}
      context.a.constructor.toString().should.equal "function a() {}"

    it "should handle circular dependencies by injecting stubs and then setting prototypes", ->
      context.register 'a', (b) -> {run: (n) -> b.run(n)*2}
      context.register 'b', (a) -> {run: (n) -> n+1}
      context.lookup('a').run(1).should.equal(4)

      context.register 'd', (c) -> {run: (n) -> c.run(n)*2}
      context.register 'c', (d) -> {run: (n) -> n+1}
      context.lookup('d').run(1).should.equal(4)

    it "should support functions that return promises", (done) ->
      apromise = promise.create()
      context.register 'a', -> apromise
      promise.isPromise(context.lookup('a')).should.equal true
      context.lookup('a').then (value) ->
        value.should.equal "WORLD!"
        context.lookup('a').should.equal "WORLD!"
        done()
      apromise.resolve "WORLD!"

    it "should support functions that depend on promises", (done) ->
      apromise = promise.create()
      context.register 'a', -> apromise
      context.register 'b', (a) -> "HELLO #{a}"
      promise.isPromise(context.lookup('a')).should.equal true
      context.lookup('b').then (value) ->
        value.should.equal "HELLO WORLD!"
        done()
      apromise.resolve "WORLD!"

    it "should support configure", ->
      cfg = a: b: {c: 1, d: "Hello World!"}
      context.configure(cfg)
      context.config.a.should.eql cfg.a

    it "should do a nested merge of multiple configure options", ->
      cfg1 = a: b: c: 1
      cfg2 = a: b: c: 2
      context.configure(cfg1, cfg2)
      context.config.a.should.eql cfg2.a

    it "should supply options as part of the variables for the constructor", ->
      ctr = (a, b) ->
        a.should.equal "Hello"
        b.should.equal "World"
        "OK"
      context.configure {test: {b: "World"}}
      context.register "a", "Hello"
      context.register 'test', ctr
      context.test.should.equal "OK"

    it "should pass entire options hash when $options parameter is used", ->
      ctr = (a, $options) ->
        $options.should.eql {b: "World"}
        a.should.equal "Hello"
        "OK"
      context.configure {test: {b: "World"}}
      context.register "a", "Hello"
      context.register 'test', ctr
      context.test.should.equal "OK"

    it "should invoke constructor functions with this as the context", ->
      context.register "a", -> context == this
      context.a.should.equal(true)

    it "should support dynamic factories that are resolved during instantiation", ->
      context.configure {b: {world: "World"}}
      context.register "helloFactory", ->
        (name, $options) ->
          name.should.equal("b")
          "Hello #{$options.world}!"
      context.register 'b', ($hello) -> $hello
      context.b.should.equal("Hello World!")

    it "should support delegating to a parent context if the object is not available", ->
      parentContext = di.context()
      parentContext.register 'parent', () -> "world"
      context.register 'child', (parent) -> "hello "+parent
      context.setParent(parentContext)
      context.child.should.equal("hello world")

