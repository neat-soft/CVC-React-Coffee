_ = require('lodash')

nextClassName = null
exports.newObject = (name, def) ->
  unless _.isString(name)
    def = name
    name = nextClassName
    nextClassName = null
  name = "CustomObject" unless name?
  throw new Error("Invalid classname #{name}") unless /[a-zA-Z0-9_]/.test(name)
  ctor = (eval "function #{name}() {};#{name}")
  for own n,v of (def?.__prototype || {})
    ctor.prototype[n]=v
  obj = new ctor()
  for own n,v of (def || {})
    obj[n]=v unless n == "__prototype"
  obj

exports.newObject.setNextClassName = (name) -> nextClassName = name

