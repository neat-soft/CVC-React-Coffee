should = require('should')
$v = require('../src/validation')
$u = require('../src/utilities')
promise = require('../src/promise')
_ = require('lodash')

describe "Validation", ->
  f = (a, b, c, $argNames) ->
    return $v($argNames) unless $v.required(a, b, c).isValid()
    return promise.resolved(a, b, c)
  it "should return validation errors if there are any", ->
    f(null, 1, null).then
      success: -> should.fail("success should not be called")
      failure: -> should.fail("failure should not be called")
      error: (err) ->
        err.constructor.name.should.equal("ValidationErrors")
        err.count().should.equal(2)
        err.failedIndexes().should.eql([0, 2])

  it "should augment the validation error with field names if available", (done) ->
    f(null, "B", null, $u.parseArguments(f)).then
      error: (err) ->
        err.toArray().should.eql [
          {index: 0, type: "required", name: "a"}
          {index: 2, type: "required", name: "c"}
        ]
        done()

describe 'Object Validation', ->
  it "should allow to validate any field in an object", ->
    f = (o) ->
      return $v() unless $v.object(o)
        .field1.isPresent()
        .field2.isPresent().is(_.isNumber)
        .field3.isPresent()
        .field4.isPresent().is("NOT_A_NUMBER", _.isNumber)
        .isValid()
      return promise.resolved("OK")

    f({field1: "Hello World!", field2: 3, field4: 'A'}).then
      success: -> should.fail("success should not be called")
      failure: -> should.fail("failure should not be called")
      error: (err) ->
        err.constructor.name.should.equal("ValidationErrors")
        err.toArray().should.eql [
          {field: "field3", type: "REQUIRED"}
          {field: "field4", type: "NOT_A_NUMBER", value: "A"}
        ]

  it "should support optional fields", ->
    $v.object({})
      .field1.isOptional()
        .is((v) -> should.fail("validation should not be called"))
      .isValid().should.equal true

  it "should support required fields with an optional dependency", ->
    $v.object({})
      .field1.isOptional()
      .field2.isOptional('field1').isNotEmpty()
      .isValid().should.equal true
    $v.object({field2: 'asdf'})
      .field1.isOptional()
      .field2.isOptional('field1').isNotEmpty()
      .isValid().should.equal true
    $v.object({field1: ''})
      .field1.isOptional()
      .field2.isOptional('field1').isNotEmpty()
      .isValid().should.equal true
    $v.object({field1: 'asdf'})
      .field1.isOptional()
      .field2.isOptional('field1').isNotEmpty()
      .isValid().should.equal false
