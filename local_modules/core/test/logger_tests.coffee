should = require("should")
logger = require("../src/logger")
scope = require("../src/scope")
$p = require("../src/promise")
$u = require("../src/utilities")
expect = require('../src/expect')
_ = require('lodash')

describe "LoggerFactory", ->
  loggerMock = null
  $l = null
  beforeEach ->
    loggerMock = {}
    $l = logger.LoggerFactory($p, $u, {})("TEST")
    $l._parent.baseLogger = loggerMock

  it "should create a logger", ->
    loggerMock.log = expect("info", "[TEST] WORLD!")
    $l.info("WORLD!")

  it "should nest a logger", ->
    l = $l.nest("TEST2")
    loggerMock.log = expect("info", "[TEST][TEST2] WORLD!")
    l.info("WORLD!")

  it "should configure papertrail correctly", ->
    l = logger.LoggerFactory($p, $u, {papertrail: {host: 'localhost', port:1}})("TEST")
    _.keys(l._parent.baseLogger.transports).should.eql(['Papertrail', 'console'])

  it "should support tagging the currently active scope if one exists", ->
    l = $l.nest("TEST2")
    loggerMock.log = expect("info", "[SCOPE1][SCOPE2][TEST][TEST2] WORLD!")
                    .expect("info", "[TEST][TEST2] WORLD!")
    scope ->
      l.tagScope("SCOPE1")
       .tagScope("SCOPE2")
       .info("WORLD!")
    l.info("WORLD!")

  it "should support setting minimum log level for a scope", ->
    loggerMock.log = expect("error", "[SCOPE][TEST] WORLD!")
    scope ->
      $l.restrictScope("error")
        .tagScope("SCOPE")
        .info("WORLD!")
        .error("WORLD!")