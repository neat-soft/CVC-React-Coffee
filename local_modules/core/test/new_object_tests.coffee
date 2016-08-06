should = require('should')
{newObject} = require("../src/new_object")

describe "newObject", () ->
  it "should create a named object without a definition", ->
    newObject("test").constructor.toString().should.equal "function test() {}"
    should.not.exist global.test

  it "should create a named object with a definition", ->
    obj = newObject "test", {
      value1: "Hello"
      method1: (a) -> a*2
    }
    obj.method1(2).should.equal(4)
    obj.value1.should.equal("Hello")
    obj.hasOwnProperty("value1").should.equal(true)
    obj.hasOwnProperty("method1").should.equal(true)

  it "should create a named object with a definition and a prototype", ->
    obj = newObject "test", {
      __prototype:
        method1: (a) -> a*2
      value1: "Hello"
    }
    obj.method1(2).should.equal(4)
    obj.value1.should.equal("Hello")
    obj.hasOwnProperty("value1").should.equal(true)
    obj.hasOwnProperty("method1").should.equal(false)

  describe "setNextClassName", ->
    it "should set the name of the class for the next object", ->
      newObject.setNextClassName "World"
      obj = newObject {value1:"Hello"}
      obj.constructor.toString().should.equal "function World() {}"

    it "should reset the next class name after it is used", ->
      newObject.setNextClassName "World"
      obj = newObject {value1:"Hello"}
      obj.constructor.toString().should.equal "function World() {}"
      obj = newObject {value1:"Hello"}
      obj.constructor.toString().should.equal "function CustomObject() {}"