fs = require('fs')
_ = require('lodash')
srcFolder = if fs.existsSync("#{__dirname}/lib") then "lib"  else "src"
$u = require("./#{srcFolder}/utilities")
_.each fs.readdirSync("#{__dirname}/#{srcFolder}"), (mod) ->
  name = mod.match(/^(.*)\..*$/)?[1]
  if name?
    exports[$u.toCamelCase(name)] = require("./#{srcFolder}/#{name}")

exports.$u = exports.utilities
exports.$p = exports.promise
exports.$v = exports.validation
